import SwiftUI
import Testing
@testable import Waypoint

@MainActor
@Suite("Stack navigation")
struct StackTests {
    @Test("The root coordinator's initial route becomes the root screen")
    func rootCoordinator() {
        // GIVEN
        let home = TestCoordinator()

        // WHEN
        let navigator = Navigator(root: home)

        // THEN
        #expect(home.navigator === navigator)
        #expect(navigator.root.route(as: TestCoordinator.Route.self) == .home)
        #expect(navigator.path.isEmpty)
        #expect(home.routes == [.home])
    }

    @Test("Pushing appends routes in order")
    func push() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.push(.detail(1))
        home.push([.detail(2), .detail(3)])

        // THEN
        #expect(home.routes == [.home, .detail(1), .detail(2), .detail(3)])
        #expect(navigator.path.count == 3)
    }

    @Test("Each push builds its screen exactly once")
    func screensBuiltOnce() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.push(.detail(1))
        _ = navigator.path.map(\.screen.view)
        _ = navigator.path.map(\.screen.view)

        // THEN
        #expect(home.madeViewModels.count == 2)
    }

    @Test("Popping frees the popped screen's view model")
    func popReleases() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push([.detail(1), .detail(2)])

        // WHEN
        home.pop()

        // THEN
        #expect(home.routes == [.home, .detail(1)])
        #expect(home.madeViewModels.liveCount == 2)
        withExtendedLifetime(navigator) {}
    }

    @Test("A popped screen that's still animating out keeps its view until it disappears")
    func visibleScreenReleasedAfterDisappearing() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push(.detail(1))
        let screen = navigator.top.screen
        screen.didAppear()

        // WHEN
        navigator.pop()

        // THEN: SwiftUI is still animating it out, so the view (and its view model) stay
        #expect(screen.view != nil)
        #expect(home.madeViewModels.liveCount == 2)

        // WHEN
        screen.didDisappear()

        // THEN: dropped, even though SwiftUI may still retain the screen box itself
        #expect(screen.view == nil)
        #expect(home.madeViewModels.liveCount == 1)
    }

    @Test("SwiftUI's token path maps back to entries, and unknown tokens are ignored")
    func tokenPath() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push([.detail(1), .detail(2), .detail(3)])
        let tokens = navigator.path.map(\.token)
        let stranger = StackEntry(route: AnyHashable(0), content: AnyView(EmptyView()), owner: nil).token

        // WHEN
        navigator.setPath(tokens: [tokens[0], stranger])

        // THEN
        #expect(home.routes == [.home, .detail(1)])
    }

    @Test("A shorter path from SwiftUI's binding (swipe-back) is torn down like a pop")
    func bindingPop() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push([.detail(1), .detail(2), .detail(3)])

        // WHEN
        navigator.setPath(Array(navigator.path.prefix(1)))

        // THEN
        #expect(home.routes == [.home, .detail(1)])
        #expect(home.madeViewModels.liveCount == 2)
    }

    @Test("Popping to root frees every pushed screen")
    func popToRoot() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push([.detail(1), .detail(2)])

        // WHEN
        navigator.popToRoot()

        // THEN
        #expect(navigator.path.isEmpty)
        #expect(home.madeViewModels.liveCount == 1)
    }

    @Test("pop(to:) keeps the target screen")
    func popToEntry() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push([.detail(1), .detail(2), .detail(3)])
        let target = navigator.path[0]

        // WHEN
        navigator.pop(to: target)

        // THEN
        #expect(navigator.path == [target])
    }

    @Test("Popping more screens than are on the stack empties the path without crashing")
    func overPop() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push(.detail(1))

        // WHEN
        navigator.pop(count: 5)
        navigator.pop()

        // THEN
        #expect(navigator.path.isEmpty)
    }

    @Test("setStack on the root coordinator replaces the whole path")
    func setStackOnRoot() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push([.detail(1), .detail(2)])

        // WHEN
        home.setStack([.detail(7), .detail(8)])

        // THEN
        #expect(home.routes == [.home, .detail(7), .detail(8)])
        #expect(home.madeViewModels.liveCount == 3)
        withExtendedLifetime(navigator) {}
    }

    @Test("A coordinator that isn't started yet ignores navigation instead of crashing in release")
    func unstartedCoordinator() {
        // GIVEN
        let home = TestCoordinator()

        // THEN
        #expect(home.navigator == nil)
        #expect(home.routes.isEmpty)
    }
}

@MainActor
@Suite("Pushed child coordinators")
struct PushedChildTests {
    @Test("A pushed child shares the parent's stack")
    func sharesStack() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()

        // WHEN
        home.pushFlow(child)
        child.push(.step(2))

        // THEN
        #expect(child.navigator === navigator)
        #expect(child.routes == [.step(1), .step(2)])
        #expect(navigator.path.count == 2)
    }

    @Test("Popping past a pushed child's first screen finishes and frees it")
    func popPastChild() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        weak var weakChild: ChildFlowCoordinator?
        do {
            let child = ChildFlowCoordinator()
            weakChild = child
            home.pushFlow(child)
            child.push(.step(2))
        }

        // WHEN
        navigator.pop()

        // THEN: the child survives while one of its screens is still there
        #expect(weakChild != nil)
        #expect(weakChild?.isFinished == false)

        // WHEN
        navigator.pop()

        // THEN
        #expect(weakChild == nil)
    }

    @Test("didFinish runs once, when the child's first screen leaves")
    func didFinishOnce() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()
        home.pushFlow(child)
        child.push(.step(2))

        // WHEN
        navigator.popToRoot()
        navigator.popToRoot()

        // THEN
        #expect(child.finishCount == 1)
        #expect(child.isFinished)
    }

    @Test("finish() on a pushed child pops back to the screen that pushed it")
    func finishPushedChild() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push(.detail(1))
        let child = ChildFlowCoordinator()
        home.pushFlow(child)
        child.push([.step(2), .step(3)])

        // WHEN
        child.finish()

        // THEN
        #expect(home.routes == [.home, .detail(1)])
        #expect(child.finishCount == 1)
        #expect(child.madeViewModels.liveCount == 0)
        withExtendedLifetime(navigator) {}
    }

    @Test("setStack on a pushed child keeps the parent's screens below it")
    func setStackOnChild() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push(.detail(1))
        let child = ChildFlowCoordinator()
        home.pushFlow(child)
        child.push(.step(2))

        // WHEN
        child.setStack([.step(5), .step(6)])

        // THEN
        #expect(home.routes == [.home, .detail(1)])
        #expect(child.routes == [.step(1), .step(5), .step(6)])
        withExtendedLifetime(navigator) {}
    }

    @Test("popToStart returns to the child's first screen")
    func popToStart() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()
        home.pushFlow(child)
        child.push([.step(2), .step(3)])

        // WHEN
        child.popToStart()

        // THEN
        #expect(child.routes == [.step(1)])
        withExtendedLifetime(navigator) {}
    }
}

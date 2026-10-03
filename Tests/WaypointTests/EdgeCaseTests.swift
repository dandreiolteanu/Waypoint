import SwiftUI
import Testing
@testable import Waypoint

@MainActor
@Suite("Edge cases")
struct EdgeCaseTests {
    @Test("A finished child can't navigate any more, even while a task keeps it alive")
    func finishedChildCannotPush() async {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()
        home.push(child: child)
        navigator.pop()
        #expect(child.isFinished)

        // WHEN
        child.push(.step(2))
        child.present(.step(3))
        let value = await child.push { _ in .step(4) } as String?

        // THEN
        #expect(navigator.path.isEmpty)
        #expect(navigator.presentation == nil)
        #expect(value == nil)
    }

    @Test("Finishing a pushed child also dismisses what it presented")
    func finishDismissesChildsPresentation() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()
        home.push(child: child)
        child.present(.step(5))

        // WHEN
        child.finish()

        // THEN
        #expect(navigator.presentation == nil)
    }

    @Test("Popping past a pushed child also dismisses what it presented, but not what the parent presented")
    func popDismissesOnlyChildsPresentation() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        let child = ChildFlowCoordinator()
        home.push(child: child)

        // WHEN
        navigator.pop()

        // THEN
        #expect(navigator.presentation?.navigator.root.route(as: TestCoordinator.Route.self) == .detail(1))
    }

    @Test("dismissAll during a dismissal animation also cancels the queued presentation, and its await returns nil")
    func dismissCancelsQueued() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        try #require(navigator.presentation).hasAppeared = true
        let task = Task { await home.present { .pick($0) } }
        await settle()

        // WHEN
        navigator.dismissAll()
        navigator.presentationDidFinishDismissing()

        // THEN
        #expect(navigator.presentation == nil)
        #expect(await task.value == nil)
    }

    @Test("A queued presented child can cancel itself")
    func queuedChildDismissesItself() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        try #require(navigator.presentation).hasAppeared = true
        let child = ChildFlowCoordinator()
        home.present(child: child)

        // WHEN
        child.dismiss()
        navigator.presentationDidFinishDismissing()

        // THEN
        #expect(navigator.presentation == nil)
        #expect(child.isFinished)
    }

    @Test("A child flow's await resumes only after every screen it popped has left the screen")
    func awaitWaitsForWholeFlow() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        weak var weakChild: ChildFlowCoordinator?
        var resumed = false
        let task = Task {
            let value = await home.push(child: { callback in
                let child = ChildFlowCoordinator(onComplete: callback)
                weakChild = child
                return child
            })
            resumed = true
            return value
        }
        await settle()
        let child = try #require(weakChild)
        let first = navigator.top
        first.screen.didAppear()
        child.push(.step(2))
        first.screen.didDisappear()
        let top = navigator.top
        top.screen.didAppear()

        // WHEN
        child.complete(with: "x")
        await settle()

        // THEN: step 2 is still animating out
        #expect(!resumed)

        // WHEN
        top.screen.didDisappear()

        // THEN
        #expect(await task.value == "x")
    }

    @Test("A presented flow's await resumes only after its visible screen has left")
    func presentedAwaitWaitsForVisibleScreen() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        weak var weakChild: ChildFlowCoordinator?
        var resumed = false
        let task = Task {
            let value = await home.present(as: .sheet, child: { callback in
                let child = ChildFlowCoordinator(onComplete: callback)
                weakChild = child
                return child
            })
            resumed = true
            return value
        }
        await settle()
        let child = try #require(weakChild)
        child.push(.step(2))
        let presented = try #require(navigator.presentation?.navigator)
        presented.top.screen.didAppear()

        // WHEN
        child.complete(with: "done")
        await settle()

        // THEN
        #expect(navigator.presentation == nil)
        #expect(!resumed)
        presented.top.screen.didDisappear()
        #expect(await task.value == "done")
    }

    @Test("An alert requested while a sheet animates out waits for it")
    func alertWaitsForDismissal() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        try #require(navigator.presentation).hasAppeared = true
        home.dismissPresented()

        // WHEN
        let task = Task { await home.confirm("Sure?", confirmTitle: "Yes") }
        await settle()

        // THEN
        #expect(navigator.alertRequest == nil)
        navigator.presentationDidFinishDismissing()
        let request = try #require(navigator.alertRequest)
        navigator.finishAlert(request, choosing: 0)
        #expect(await task.value == true)
    }

    @Test("A route shown with present(_:) is reachable through presented and closed with dismissPresented")
    func routePresentationAccessors() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.present(.detail(1), as: .sheet(detents: [.medium, .large]))
        home.presented?.selectedDetent = .large

        // THEN
        #expect(navigator.presentation?.selectedDetent == .large)
        #expect(home.presentation == nil)
        home.dismiss()
        #expect(navigator.presentation != nil, "dismiss() is about the flow's own presentation, and the root flow has none")
        home.dismissPresented()
        #expect(navigator.presentation == nil)
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

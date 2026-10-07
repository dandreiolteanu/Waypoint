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
        home.pushFlow(child)
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
        home.pushFlow(child)
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
        home.pushFlow(child)

        // WHEN
        navigator.pop()

        // THEN
        #expect(navigator.presentation?.route(as: TestCoordinator.Route.self) == .detail(1))
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
        home.presentFlow(child)

        // WHEN
        child.finish()
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
            let value = await home.pushFlow({ callback in
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
            let value = await home.presentFlow(as: .sheet, { callback in
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

    @Test("A route shown with present(_:) is reachable through presented, and closed with dismissPresented")
    func routePresentationAccessors() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.present(.detail(1), as: .sheet(detents: [.medium, .large]))
        home.presented?.selectedDetent = .large

        // THEN
        #expect(navigator.presentation?.selectedDetent == .large)
        #expect(home.enclosingPresentation == nil)
        home.dismissPresented()
        #expect(navigator.presentation == nil)
    }

    @Test("A finished child can't pop, dismiss, or touch presentations that now belong to its parent")
    func finishedChildCannotClose() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.push(.detail(1))
        let child = ChildFlowCoordinator()
        home.pushFlow(child)
        navigator.pop()
        home.present(.detail(2))

        // WHEN
        child.pop()
        child.popToRoot()
        child.dismissPresented()
        child.dismissAll()

        // THEN
        #expect(home.routes == [.home, .detail(1)])
        #expect(navigator.presentation != nil)
        #expect(child.presented == nil)
    }

    @Test("A pushed flow's await waits for a cover the flow presented to leave too")
    func awaitWaitsForChildsCover() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        weak var weakChild: ChildFlowCoordinator?
        var resumed = false
        let task = Task {
            let value = await home.pushFlow { callback in
                let child = ChildFlowCoordinator(onComplete: callback)
                weakChild = child
                return child
            }
            resumed = true
            return value
        }
        await settle()
        let child = try #require(weakChild)
        child.present(.step(9), as: .fullScreenCover)
        let cover = try #require(navigator.presentation)
        cover.didAppear()
        cover.navigator.top.screen.didAppear()

        // WHEN: the flow completes from inside its cover
        child.complete(with: "done")
        await settle()

        // THEN: the cover is dismissed but still animating
        #expect(navigator.presentation == nil)
        #expect(!resumed)
        cover.navigator.top.screen.didDisappear()
        #expect(await task.value == "done")
    }

    @Test("A deep-link tab reset dismisses sheets opened from any tab")
    func tabResetDismissesEveryTab() {
        // GIVEN
        enum AppTab: CaseIterable { case feed, profile }
        let feed = TestCoordinator()
        let profile = TestCoordinator()
        let tabs = TabNavigator(selected: AppTab.feed) { tab in
            switch tab {
            case .feed: Navigator(root: feed)
            case .profile: Navigator(root: profile)
            }
        }
        feed.present(.detail(1))
        profile.push(.detail(2))

        // WHEN
        tabs.select(.profile, reset: true)

        // THEN
        #expect(tabs[.feed].presentation == nil)
        #expect(profile.routes == [.home])
        #expect(tabs.coordinator(for: .profile, as: TestCoordinator.self) === profile)
    }

    @Test("A removed screen SwiftUI never reports as gone still closes, so its await can't hang")
    func removedScreenClosesEventually() async throws {
        // GIVEN
        let saved = ScreenContent.closeTimeout
        ScreenContent.closeTimeout = .milliseconds(50)
        defer { ScreenContent.closeTimeout = saved }
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let task = Task { await home.push { .pick($0) } }
        await settle()
        navigator.top.screen.didAppear()

        // WHEN: popped, and SwiftUI never calls onDisappear
        navigator.pop()

        // THEN
        #expect(await task.value == nil)
    }

    @Test("An alert queued behind a dismissal waits for the next sheet to appear before showing on it")
    func queuedAlertWaitsForNextSheet() async throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        try #require(navigator.presentation).hasAppeared = true
        home.present(.detail(2))
        let task = Task { await home.confirm("Sure?", confirmTitle: "Yes") }
        await settle()

        // WHEN: the old sheet finishes leaving, and the queued one is shown but hasn't appeared yet
        navigator.presentationDidFinishDismissing()
        let next = try #require(navigator.presentation)

        // THEN
        #expect(next.navigator.alertRequest == nil)
        next.didFinishPresenting()
        let request = try #require(next.navigator.alertRequest)
        next.navigator.finishAlert(request, choosing: 0)
        #expect(await task.value == true)
    }

    @Test("A hosted, presented navigator holds its presentations until its own sheet has appeared")
    func stackedPresentationsWaitForEachSheet() throws {
        // GIVEN: a user interface, as in an app
        Navigator.hasUserInterface = true
        defer { Navigator.hasUserInterface = false }
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let first = ChildFlowCoordinator()
        home.presentFlow(first)
        let second = ChildFlowCoordinator()

        // WHEN: the first sheet presents before it has appeared
        first.presentFlow(second)

        // THEN
        let firstSheet = try #require(navigator.presentation)
        let firstNavigator = try #require(first.navigator)
        #expect(firstNavigator.presentation == nil)

        // WHEN: inserted, but still animating in
        firstSheet.didAppear()

        // THEN
        #expect(firstNavigator.presentation == nil)

        // WHEN: the presentation animation finishes
        firstSheet.didFinishPresenting()

        // THEN
        #expect(firstNavigator.presentation?.route(as: ChildFlowCoordinator.Route.self) == .step(1))
        #expect(second.navigator?.presenter === firstNavigator)
    }

    @Test("A deep-link reset closes an alert that's up, and its await returns nil")
    func resetClosesAlerts() async throws {
        // GIVEN
        enum AppTab: CaseIterable { case feed, profile }
        let profile = TestCoordinator()
        let tabs = TabNavigator(selected: AppTab.profile) { tab in
            switch tab {
            case .feed: Navigator(root: TestCoordinator())
            case .profile: Navigator(root: profile)
            }
        }
        let task = Task { await profile.confirm("Sign out?", confirmTitle: "Sign out") }
        await settle()
        #expect(tabs[.profile].alertRequest != nil)

        // WHEN
        tabs.select(.feed, reset: true)

        // THEN
        #expect(tabs[.profile].alertRequest == nil)
        #expect(await task.value == false)
    }

    @Test("A zoom only starts from a settled, on-screen source; otherwise the push uses the default animation")
    func zoomNeedsASettledSource() throws {
        // GIVEN: a user interface, a settled root screen with a zoom source on it
        Navigator.hasUserInterface = true
        defer { Navigator.hasUserInterface = false }
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        navigator.top.screen.didAppear()
        navigator.top.screen.didSettle()
        let root = ObjectIdentifier(navigator.top.screen)
        navigator.registerZoomSource(ScopedSourceID.key(1, in: root))

        // WHEN: tapped once
        home.push(.detail(1), transition: .zoom(sourceID: 1))

        // THEN: it zooms from the source on the screen that was tapped
        #expect(navigator.top.transition.zoomSourceID == ScopedSourceID.key(1, in: root))

        // WHEN: tapped again while that push is still animating (the new top hasn't settled)
        home.push(.detail(1), transition: .zoom(sourceID: 1))

        // THEN: no zoom, so UIKit never morphs from a source that's leaving the window
        #expect(navigator.top.transition == .automatic)
    }

    @Test("A zoom from an unknown source, or from under a sheet, falls back to the default animation")
    func zoomNeedsAVisibleSource() {
        Navigator.hasUserInterface = true
        defer { Navigator.hasUserInterface = false }
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        navigator.top.screen.didAppear()
        navigator.top.screen.didSettle()

        home.push(.detail(1), transition: .zoom(sourceID: "missing"))
        #expect(navigator.top.transition == .automatic)

        navigator.pop()
        navigator.registerZoomSource(ScopedSourceID.key("card", in: ObjectIdentifier(navigator.top.screen)))
        home.present(.detail(2))
        home.push(.detail(3), transition: .zoom(sourceID: "card"))
        #expect(navigator.top.transition == .automatic)
    }

    @Test("The same zoom id on a covered screen doesn't count: the same screen pushed twice can't zoom from the copy underneath")
    func zoomSourcesAreScopedToTheirScreen() {
        // GIVEN: Tram → Tree, where Tram (covered, still in the stack) has a source with id "tram"
        Navigator.hasUserInterface = true
        defer { Navigator.hasUserInterface = false }
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        navigator.registerZoomSource(ScopedSourceID.key("tram", in: ObjectIdentifier(navigator.top.screen)))
        home.push(.detail(1))
        navigator.top.screen.didAppear()
        navigator.top.screen.didSettle()

        // WHEN: Tree pushes with the same id, but Tree has no such source of its own
        home.push(.detail(2), transition: .zoom(sourceID: "tram"))

        // THEN: no zoom, rather than morphing from the covered Tram's view
        #expect(navigator.top.transition == .automatic)
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

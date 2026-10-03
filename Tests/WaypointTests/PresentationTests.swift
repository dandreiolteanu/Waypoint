import SwiftUI
import Testing
@testable import Waypoint

@MainActor
@Suite("Modal presentation")
struct PresentationTests {
    @Test("Presenting a route shows it in a new navigator")
    func presentRoute() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.present(.detail(1), as: .sheet(detents: [.medium, .large]))

        // THEN
        let presentation = try #require(navigator.presentation)
        #expect(presentation.style.kind == .sheet)
        #expect(presentation.navigator.presenter === navigator)
        #expect(presentation.route(as: TestCoordinator.Route.self) == .detail(1))
        #expect(presentation.selectedDetent == .medium)
    }

    @Test("Dismissing frees the presented screen")
    func dismissReleases() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        weak var presented = navigator.presentation?.navigator

        // WHEN
        navigator.dismissPresentation()

        // THEN
        #expect(navigator.presentation == nil)
        #expect(presented == nil)
        #expect(home.madeViewModels.liveCount == 1)
    }

    @Test("A swipe-down reported by SwiftUI tears the presentation down")
    func systemDismissal() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()
        home.presentFlow(child)
        let presentation = try #require(navigator.presentation)

        // WHEN
        navigator.presentationDismissedBySystem(presentation)

        // THEN
        #expect(navigator.presentation == nil)
        #expect(child.isFinished)
    }

    @Test("A stale dismissal for a presentation that was already replaced is ignored")
    func staleSystemDismissal() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        let first = try #require(navigator.presentation)
        home.present(.detail(2))

        // WHEN
        navigator.presentationDismissedBySystem(first)

        // THEN
        #expect(navigator.presentation?.route(as: TestCoordinator.Route.self) == .detail(2))
    }

    @Test("A presented child gets its own stack, and dismiss() releases it")
    func presentChild() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        weak var weakChild: ChildFlowCoordinator?
        do {
            let child = ChildFlowCoordinator()
            weakChild = child
            home.presentFlow(child, as: .fullScreenCover)
        }
        // WHEN
        try #require(weakChild).push(.step(2))

        // THEN
        #expect(weakChild?.navigator === navigator.presentation?.navigator)
        #expect(weakChild?.navigator !== navigator)
        #expect(weakChild?.routes == [.step(1), .step(2)])
        #expect(home.routes == [.home])

        // WHEN
        weakChild?.finish()

        // THEN
        #expect(navigator.presentation == nil)
        #expect(weakChild == nil)
    }

    @Test("finish() on a presented child dismisses it")
    func finishPresentedChild() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()
        home.presentFlow(child)
        child.push(.step(2))

        // WHEN
        child.finish()

        // THEN
        #expect(navigator.presentation == nil)
        #expect(child.finishCount == 1)
        #expect(child.madeViewModels.liveCount == 0)
    }

    @Test("Dismissing a presentation also dismisses everything stacked on it")
    func nestedDismissal() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let first = ChildFlowCoordinator()
        home.presentFlow(first)
        let second = ChildFlowCoordinator()
        first.presentFlow(second)
        let third = ChildFlowCoordinator()
        second.presentFlow(third)
        #expect(navigator.topmost === third.navigator)

        // WHEN
        third.navigator?.dismissAll()

        // THEN
        #expect(navigator.presentation == nil)
        #expect(first.isFinished && second.isFinished && third.isFinished)
        #expect(navigator.topmost === navigator)
    }

    @Test("Dismissing a middle presentation keeps the ones below it")
    func dismissMiddle() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let first = ChildFlowCoordinator()
        home.presentFlow(first)
        let second = ChildFlowCoordinator()
        first.presentFlow(second)
        let third = ChildFlowCoordinator()
        second.presentFlow(third)

        // WHEN
        second.finish()

        // THEN
        #expect(navigator.topmost === first.navigator)
        #expect(!first.isFinished)
        #expect(second.isFinished && third.isFinished)
    }

    @Test("Presenting over an on-screen presentation waits for the dismissal to finish")
    func replaceWaitsForDismissal() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1), as: .sheet)
        try #require(navigator.presentation).hasAppeared = true

        // WHEN
        home.present(.detail(2), as: .fullScreenCover)

        // THEN: the sheet is going away, and the cover waits for it
        #expect(navigator.presentation == nil)

        // WHEN
        navigator.presentationDidFinishDismissing()

        // THEN
        let presentation = try #require(navigator.presentation)
        #expect(presentation.style.kind == .fullScreenCover)
        #expect(presentation.route(as: TestCoordinator.Route.self) == .detail(2))
    }

    @Test("Presenting while a dismissal animates queues the presentation")
    func presentDuringDismissal() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        try #require(navigator.presentation).hasAppeared = true
        navigator.dismissPresentation()

        // WHEN
        home.present(.detail(2))

        // THEN
        #expect(navigator.presentation == nil)
        navigator.presentationDidFinishDismissing()
        #expect(navigator.presentation?.route(as: TestCoordinator.Route.self) == .detail(2))
    }

    @Test("Only the latest queued presentation is shown; earlier ones are torn down")
    func latestQueuedWins() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))
        try #require(navigator.presentation).hasAppeared = true
        let skipped = ChildFlowCoordinator()

        // WHEN
        home.presentFlow(skipped)
        home.present(.detail(3))
        navigator.presentationDidFinishDismissing()

        // THEN
        #expect(skipped.isFinished)
        #expect(navigator.presentation?.route(as: TestCoordinator.Route.self) == .detail(3))
    }

    @Test("A presentation that never appeared is replaced right away")
    func replaceBeforeAppearing() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        home.present(.detail(1))

        // WHEN
        home.present(.detail(2))

        // THEN
        #expect(navigator.presentation?.route(as: TestCoordinator.Route.self) == .detail(2))
    }

    @Test("The initial detent is used, and the selection stays writable")
    func detents() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.present(.detail(1), as: .sheet(detents: [.fraction(0.3), .large], initialDetent: .fraction(0.3)))
        let presentation = try #require(navigator.presentation)

        // THEN
        #expect(presentation.selectedDetent == .fraction(0.3))
        presentation.selectedDetent = .large
        #expect(presentation.selectedDetent == .large)
    }

    @Test("Sheet configuration is carried through to the presentation")
    func sheetConfiguration() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.present(.detail(1), as: .sheet(isInteractiveDismissDisabled: true, embedsInNavigationStack: false), transition: .zoom(sourceID: 42))
        let presentation = try #require(navigator.presentation)

        // THEN
        #expect(presentation.isInteractiveDismissDisabled)
        #expect(!presentation.navigator.embedsInNavigationStack)
        #expect(presentation.transition == .zoom(sourceID: 42))
    }

    @Test("Presenting from a torn-down navigator does nothing")
    func presentAfterTeardown() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        navigator.tearDown()
        let child = ChildFlowCoordinator()

        // WHEN
        navigator.present(Navigator(root: child), style: .sheet, transition: .automatic)

        // THEN
        #expect(navigator.presentation == nil)
        #expect(child.isFinished)
    }
}

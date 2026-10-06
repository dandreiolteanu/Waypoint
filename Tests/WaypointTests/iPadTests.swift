import SwiftUI
import Testing
@testable import Waypoint

@MainActor
@Suite("Split view")
struct SplitNavigatorTests {
    enum Album: Hashable { case travel, food }

    private func makeSplit(selected: Album? = nil) -> (SplitNavigator<Album>, made: () -> Int) {
        var made = 0
        let split = SplitNavigator<Album>(selected: selected) { _ in
            made += 1
            return Navigator(root: TestCoordinator())
        }
        return (split, { made })
    }

    @Test("Nothing is built until something is selected")
    func lazyDetail() {
        // GIVEN
        let (split, made) = makeSplit()

        // THEN
        #expect(split.selected == nil)
        #expect(split.detail == nil)
        #expect(made() == 0)
    }

    @Test("An initial selection builds its detail right away")
    func initialSelection() {
        let (split, made) = makeSplit(selected: .travel)

        #expect(split.selected == .travel)
        #expect(split.detailCoordinator(as: TestCoordinator.self) != nil)
        #expect(made() == 1)
    }

    @Test("Changing the selection tears the old detail flow down and builds a new one")
    func changeSelection() {
        // GIVEN
        let (split, made) = makeSplit(selected: .travel)
        weak var oldCoordinator = split.detailCoordinator(as: TestCoordinator.self)
        oldCoordinator?.push(.detail(1))

        // WHEN
        split.selection.wrappedValue = .food

        // THEN
        #expect(split.selected == .food)
        #expect(oldCoordinator == nil)
        #expect(split.detailCoordinator(as: TestCoordinator.self)?.routes == [.home])
        #expect(made() == 2)
    }

    @Test("Selecting the current item keeps its flow, or resets it when asked")
    func reselect() {
        // GIVEN
        let (split, made) = makeSplit(selected: .travel)
        let coordinator = split.detailCoordinator(as: TestCoordinator.self)
        coordinator?.push(.detail(1))

        // WHEN
        split.select(.travel)

        // THEN
        #expect(coordinator?.routes == [.home, .detail(1)])

        // WHEN
        split.select(.travel, reset: true)

        // THEN
        #expect(coordinator?.routes == [.home])
        #expect(made() == 1)
    }

    @Test("Clearing the selection (back in compact width) frees the detail")
    func clearSelection() {
        let (split, _) = makeSplit(selected: .travel)
        weak var coordinator = split.detailCoordinator(as: TestCoordinator.self)

        split.selection.wrappedValue = nil

        #expect(split.detail == nil)
        #expect(coordinator == nil)
    }

    @Test("Tearing down ends the detail flow and ignores later selections")
    func teardown() {
        let (split, made) = makeSplit(selected: .travel)
        let coordinator = split.detailCoordinator(as: TestCoordinator.self)

        split.tearDown()
        split.select(.food)

        #expect(coordinator?.isFinished == true)
        #expect(split.detail == nil)
        #expect(made() == 1)
    }
}

@MainActor
@Suite("Popovers and sizing")
struct PopoverTests {
    @Test("A popover whose anchor is on screen is presented as a popover")
    func anchoredPopover() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        navigator.registerPopoverSource(AnyHashable("filters"))

        // WHEN
        home.present(.detail(1), as: .popover(from: "filters", arrowEdge: .bottom))

        // THEN
        let presentation = try #require(navigator.presentation)
        #expect(presentation.style.kind == .popover)
        #expect(presentation.style.arrowEdge == .bottom)
        #expect(!presentation.isSheet)
    }

    @Test("A popover with no anchor on screen falls back to a sheet")
    func unanchoredPopover() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        navigator.registerPopoverSource(AnyHashable("filters"))
        navigator.unregisterPopoverSource(AnyHashable("filters"))

        // WHEN
        home.present(.detail(1), as: .popover(from: "filters", detents: [.medium]))

        // THEN
        let presentation = try #require(navigator.presentation)
        #expect(presentation.isSheet)
        #expect(presentation.selectedDetent == .medium)
    }

    @Test("A dismissed popover's disappearance unblocks the next presentation")
    func popoverDismissalCompletes() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        navigator.registerPopoverSource(AnyHashable("info"))
        home.present(.detail(1), as: .popover(from: "info"))
        let popover = try #require(navigator.presentation)
        popover.didAppear()

        // WHEN: replaced while on screen, it animates out; popovers have no onDismiss, so disappearing is the signal
        home.present(.detail(2))
        #expect(navigator.presentation == nil)
        popover.didDisappear()

        // THEN
        #expect(navigator.presentation?.route(as: TestCoordinator.Route.self) == .detail(2))
    }

    @Test("Sheet sizing is carried through")
    func sizing() throws {
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        home.present(.detail(1), as: .sheet(sizing: .page))

        #expect(try #require(navigator.presentation).style.sizing == .page)
    }
}

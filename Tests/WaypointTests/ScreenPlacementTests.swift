import SwiftUI
import Testing
@testable import Waypoint

@MainActor
@Suite("Screen placement")
struct ScreenPlacementTests {
    @Test("A stack nobody presented has a root placement")
    func appRoot() {
        // GIVEN / WHEN
        let navigator = Navigator(root: TestCoordinator())

        // THEN
        #expect(navigator.rootPlacement == .root)
        #expect(!navigator.rootPlacement.isPresented)
    }

    /// `PresentationStyle` isn't `Sendable`, so the arguments name the style and the test builds it.
    enum Style: CaseIterable, Sendable {
        case sheet, cover, chromelessCover

        var presentationStyle: PresentationStyle {
            switch self {
            case .sheet: .sheet(detents: [.medium, .large])
            case .cover: .fullScreenCover
            case .chromelessCover: .fullScreenCover(embedsInNavigationStack: false)
            }
        }

        /// What's actually shown: macOS has no full-screen cover, so it shows a sheet.
        var kind: PresentationKind {
            switch self {
            case .sheet: .sheet
            case .cover, .chromelessCover: Self.coverKind
            }
        }

        static var coverKind: PresentationKind {
            #if os(iOS)
            .fullScreenCover
            #else
            .sheet
            #endif
        }
    }

    @Test("A presented route's root knows how it was presented", arguments: Style.allCases)
    func presentedRoute(style: Style) throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.present(.detail(1), as: style.presentationStyle)

        // THEN
        let presented = try #require(navigator.presentation?.navigator)
        #expect(presented.rootPlacement == .presented(style.kind))
        #expect(presented.rootPlacement.isPresented)
        #expect(navigator.rootPlacement == .root)
    }

    @Test("A presented flow's first screen is presented, and so is a sheet on top of it")
    func presentedFlowAndNestedSheet() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        let child = ChildFlowCoordinator()

        // WHEN
        home.presentFlow(child)
        let presented = try #require(navigator.presentation?.navigator)
        presented.present(Navigator(root: TestCoordinator()), style: .fullScreenCover, transition: .automatic)

        // THEN
        #expect(presented.rootPlacement == .presented(.sheet))
        let nested = try #require(presented.presentation?.navigator)
        #expect(nested.rootPlacement == .presented(Style.coverKind))
    }

    @Test("A popover reports popover when its anchor is on screen, and sheet when it falls back")
    func popover() throws {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)
        navigator.registerPopoverSource(AnyHashable("info"))

        // WHEN
        home.present(.detail(1), as: .popover(from: "info"))
        let anchored = try #require(navigator.presentation?.navigator)
        navigator.dismissPresentation()
        navigator.unregisterPopoverSource(AnyHashable("info"))
        home.present(.detail(2), as: .popover(from: "info"))
        let fallback = try #require(navigator.presentation?.navigator)

        // THEN
        #expect(anchored.rootPlacement == .presented(.popover))
        #expect(fallback.rootPlacement == .presented(.sheet))
    }

    @Test("A flow pushed onto a stack doesn't change the stack's placement")
    func pushedFlow() {
        // GIVEN
        let home = TestCoordinator()
        let navigator = Navigator(root: home)

        // WHEN
        home.pushFlow(ChildFlowCoordinator())

        // THEN
        #expect(navigator.rootPlacement == .root)
        #expect(navigator.depth == 1)
    }
}

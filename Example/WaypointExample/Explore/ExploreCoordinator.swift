import SwiftUI
import Waypoint

/// A lab for every presentation: each detent kind, a detent the coordinator moves, locking dismissal while a form is dirty,
/// covers, zoom sheets, nested sheets, replacing one presentation with another, and a pushed child flow that returns a value.
@MainActor
final class ExploreCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case lab
        case detents(DetentDemo)
        case controlledDetent
        case editor
        case cover
        case replaceable
        case card(Int)
        case zoomedCard(Int)
        case popoverInfo(everywhere: Bool)
        case sized(SheetSizingDemo)
    }

    enum CardSource: Hashable {
        case push(Int)
        case sheet(Int)
        case cover(Int)
    }

    var initialRoute: Route { .lab }

    /// Set while the editor sheet holds a draft. Deep links ask before throwing it away.
    private var hasUnsavedEditorChanges = false

    func destination(for route: Route) -> some View {
        switch route {
        case .lab:
            LabView(viewModel: LabViewModel(navigation: self))
        case let .detents(demo):
            DetentDemoView(demo: demo, onClose: { self.dismissPresented() })
        case .controlledDetent:
            ControlledDetentView(onSelect: { self.presented?.selectedDetent = $0 }, onClose: { self.dismissPresented() })
        case .editor:
            EditorView(viewModel: EditorViewModel(navigation: self))
        case .cover:
            CoverView(onClose: { self.dismissPresented() })
        case .replaceable:
            ReplaceableSheetView(onReplace: { self.present(.cover, as: .fullScreenCover) }, onClose: { self.dismissPresented() })
        case let .card(index):
            CardDetailView(index: index)
        case let .zoomedCard(index):
            CardDetailView(index: index)
                .toolbar { CloseButton { self.dismissPresented() } }
        case let .popoverInfo(everywhere):
            PopoverInfoView(everywhere: everywhere)
        case let .sized(demo):
            SizedSheetView(demo: demo, onClose: { self.dismissPresented() })
        }
    }

    // MARK: Deep links

    func open(_ link: ExploreLink) {
        switch link {
        case let .nestedSheets(depth): showNestedSheets(depth: depth)
        case .editor: showEditor()
        }
    }

    /// Asked before a deep link takes the user somewhere else. With a draft in the editor, the user decides.
    /// The alert shows on top of the editor sheet, because alerts go to the topmost presentation.
    func confirmLeavingUnsavedWork() async -> Bool {
        guard hasUnsavedEditorChanges else { return true }
        let leave = await confirm(
            "Discard your draft?",
            message: "A link wants to open another screen.",
            confirmTitle: "Discard and open",
            role: .destructive,
            cancelTitle: "Keep editing"
        )
        if leave { hasUnsavedEditorChanges = false }
        return leave
    }

    func showNestedSheets(depth: Int) {
        guard depth > 0 else { return }
        let first = NestedSheetCoordinator(depth: 1)
        presentFlow(first, as: .sheet(detents: [.large]))
        first.presentNext(remaining: depth - 1)
    }
}

extension ExploreCoordinator: LabNavigation {
    func showPopover(everywhere: Bool) {
        present(
            .popoverInfo(everywhere: everywhere),
            as: .popover(from: everywhere ? PopoverSource.everywhere : PopoverSource.adaptive, compactAdaptation: everywhere ? .popover : .sheet, detents: [.medium])
        )
    }

    func showSized(_ demo: SheetSizingDemo) {
        // A NavigationStack has no ideal size, so a fitted sheet shows its content without one.
        present(.sized(demo), as: .sheet(sizing: demo.sizing, embedsInNavigationStack: demo != .fitted))
    }

    func showDetents(_ demo: DetentDemo) {
        present(.detents(demo), as: .sheet(detents: demo.detents, initialDetent: demo.initialDetent, dragIndicator: .visible))
    }

    func showControlledDetent() {
        present(.controlledDetent, as: .sheet(detents: ControlledDetentView.detents, initialDetent: .medium, dragIndicator: .visible))
    }

    func showEditor() {
        present(.editor, as: .sheet)
    }

    func showCover() {
        present(.cover, as: .fullScreenCover)
    }

    func showReplaceable() {
        present(.replaceable, as: .sheet(detents: [.medium]))
    }

    func pushCard(_ index: Int) {
        push(.card(index), transition: .zoom(sourceID: CardSource.push(index)))
    }

    func presentCardSheet(_ index: Int) {
        present(.zoomedCard(index), as: .sheet, transition: .zoom(sourceID: CardSource.sheet(index)))
    }

    func presentCardCover(_ index: Int) {
        present(.zoomedCard(index), as: .fullScreenCover, transition: .zoom(sourceID: CardSource.cover(index)))
    }

    func runWizard() async -> String? {
        await pushFlow { WizardCoordinator(onFinish: $0) }
    }
}

extension ExploreCoordinator: EditorNavigation {
    func setDismissLocked(_ isLocked: Bool) {
        hasUnsavedEditorChanges = isLocked
        presented?.isInteractiveDismissDisabled = isLocked
    }

    func closeEditor() {
        hasUnsavedEditorChanges = false
        dismissPresented()
    }
}

// MARK: - iPad

enum PopoverSource: Hashable {
    case adaptive
    case everywhere
}

enum SheetSizingDemo: String, CaseIterable, Identifiable, Hashable {
    case form, page, fitted

    var id: Self { self }
    var title: String { "\(rawValue.capitalized) sheet" }

    var sizing: SheetSizing {
        switch self {
        case .form: .form
        case .page: .page
        case .fitted: .fitted
        }
    }
}

// MARK: - Detents

enum DetentDemo: String, CaseIterable, Identifiable, Hashable {
    case medium, mediumAndLarge, fraction, height, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .medium: "Medium"
        case .mediumAndLarge: "Medium + large"
        case .fraction: "Fraction (30% / 60%)"
        case .height: "Fixed height (240 pt)"
        case .custom: "Custom detent (20% of max)"
        }
    }

    var detents: [PresentationDetent] {
        switch self {
        case .medium: [.medium]
        case .mediumAndLarge: [.medium, .large]
        case .fraction: [.fraction(0.3), .fraction(0.6)]
        case .height: [.height(240)]
        case .custom: [.custom(CompactDetent.self), .large]
        }
    }

    var initialDetent: PresentationDetent? {
        switch self {
        case .fraction: .fraction(0.3)
        case .height: .height(240)
        case .custom: .custom(CompactDetent.self)
        default: nil
        }
    }
}

struct CompactDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        max(160, context.maxDetentValue * 0.2)
    }
}

import SwiftUI

/// Shows a ``Navigator``: its `NavigationStack`, the pushed screens, and its sheets and covers (recursively).
///
/// The simplest setup lets the host own the navigator:
///
/// ```swift
/// @main struct LibraryApp: App {
///     var body: some Scene {
///         WindowGroup { NavigationHost(root: LibraryCoordinator()) }
///     }
/// }
/// ```
///
/// When something else needs the navigator (an app coordinator switching roots, a ``TabNavigator``), create it there
/// and pass it in: `NavigationHost(navigator)`.
///
/// The host, and everything it hands to SwiftUI, holds a passed-in navigator **weakly**. SwiftUI sometimes keeps a removed
/// view tree around for a while (a `TabView` after a root switch, for one); when it does, it keeps an empty shell, never
/// your coordinators and view models.
public struct NavigationHost: View {
    private weak var navigator: Navigator?
    private let makeNavigator: (@MainActor () -> Navigator)?
    @State private var ownedNavigator = OwnedNavigator()
    @Namespace private var namespace

    /// Shows `navigator`, which you keep alive elsewhere (an app coordinator, a ``TabNavigator``).
    public init(_ navigator: Navigator) {
        self.navigator = navigator
        self.makeNavigator = nil
    }

    /// Creates a navigator rooted at the coordinator, once, and keeps it for as long as this view exists.
    /// `root` is evaluated only the first time, so re-rendering the parent doesn't create a new coordinator.
    ///
    /// Use it for a root that lives as long as the app (or the scene). The host never tears the tree down, so the root
    /// coordinator's ``Coordinator/didFinish()`` doesn't run. For roots you swap (sign-in and sign-out), keep the navigator
    /// in an app coordinator and call ``Navigator/tearDown()`` yourself (see <doc:RootSwitching>).
    public init<C: Routing>(root: @autoclosure @escaping @MainActor () -> C) {
        self.navigator = nil
        self.makeNavigator = { Navigator(root: root()) }
    }

    /// The stack, its destinations, and its presentations.
    public var body: some View {
        if let navigator = navigator ?? makeNavigator.map({ ownedNavigator.resolve($0) }) {
            stack(navigator)
                .environment(\.transitionNamespace, namespace)
                .environment(\.navigatorReference, NavigatorReference(navigator: navigator))
                .modifier(PresentationModifier(navigator: navigator, namespace: namespace))
                .modifier(AlertModifier(navigator: navigator))
                .onAppear { Navigator.hasUserInterface = true }
        }
    }

    @ViewBuilder
    private func stack(_ navigator: Navigator) -> some View {
        if navigator.embedsInNavigationStack {
            NavigationStack(path: Binding(
                get: { [weak navigator] in navigator?.path.map(\.token) ?? [] },
                set: { [weak navigator] in navigator?.setPath(tokens: $0) }
            )) {
                ScreenHost(screen: navigator.root.screen)
                    .navigationDestination(for: EntryToken.self) { token in
                        ScreenHost(screen: token.screen)
                            .zoomTransition(sourceID: token.transition.zoomSourceID, in: namespace)
                    }
            }
        } else {
            ScreenHost(screen: navigator.root.screen)
        }
    }
}

/// Lazily creates and keeps the navigator for ``NavigationHost/init(root:)``.
@MainActor
private final class OwnedNavigator {
    private var navigator: Navigator?

    func resolve(_ make: () -> Navigator) -> Navigator {
        if let navigator { return navigator }
        let made = make()
        navigator = made
        return made
    }
}

/// Shows a screen's view and reports when it's on screen. Once a removed screen disappears, its view is dropped,
/// and this host re-renders empty. So even a hosting controller SwiftUI keeps around ends up holding nothing.
private struct ScreenHost: View {
    let screen: ScreenContent

    var body: some View {
        if let view = screen.view {
            view
                .environment(\.screenScope, ObjectIdentifier(screen))
                .onAppear { screen.didAppear() }
                .onDisappear { screen.didDisappear() }
                .background(PresentationCompletionProbe { screen.didSettle() })
        }
    }
}

// MARK: - Presentation

private struct PresentationModifier: ViewModifier {
    weak var navigator: Navigator?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .sheet(item: presentationBinding(navigator, kind: .sheet), onDismiss: { [weak navigator] in navigator?.presentationDidFinishDismissing() }) { presentation in
                PresentedContent(presentation: presentation, namespace: namespace)
            }
            #if os(iOS)
            .fullScreenCover(item: presentationBinding(navigator, kind: .fullScreenCover), onDismiss: { [weak navigator] in navigator?.presentationDidFinishDismissing() }) { presentation in
                PresentedContent(presentation: presentation, namespace: namespace)
            }
            #endif
    }
}

/// The binding SwiftUI's `sheet(item:)`, `fullScreenCover(item:)` and `popover(item:)` read: the navigator's presentation,
/// when it's of `kind` (and, for a popover, anchored at `sourceID`).
@MainActor
func presentationBinding(_ navigator: Navigator?, kind: PresentationStyle.Kind, sourceID: AnyHashable? = nil) -> Binding<PresentationItem?> {
    func matches(_ presentation: Presentation) -> Bool {
        presentation.style.resolvedKind == kind && (sourceID == nil || presentation.style.popoverSourceID == sourceID)
    }
    // The presentation this binding was rendered with. A late write from SwiftUI about an older one must not dismiss a newer one.
    weak let rendered = navigator?.presentation
    return Binding(
        get: { [weak navigator] in
            guard let presentation = navigator?.presentation, matches(presentation) else { return nil }
            return PresentationItem(presentation)
        },
        set: { [weak navigator] newValue in
            // SwiftUI only ever writes nil here, when the user dismisses it (swipe, tap outside, or a SwiftUI `dismiss`).
            guard newValue == nil, let navigator, let current = navigator.presentation, current === rendered, matches(current) else { return }
            navigator.presentationDismissedBySystem(current)
        }
    )
}

/// The value SwiftUI's presentation modifiers hold. It has a stable identity, and only a weak reference to the presentation.
struct PresentationItem: Identifiable {
    let id: ObjectIdentifier
    weak var presentation: Presentation?

    init(_ presentation: Presentation) {
        id = ObjectIdentifier(presentation)
        self.presentation = presentation
    }
}

/// A presented navigator, with its presentation options applied.
struct PresentedContent: View {
    let item: PresentationItem
    /// The presenter's namespace. That's where the zoom source lives.
    let namespace: Namespace.ID

    init(presentation item: PresentationItem, namespace: Namespace.ID) {
        self.item = item
        self.namespace = namespace
    }

    var body: some View {
        if let presentation = item.presentation {
            NavigationHost(presentation.navigator)
                .presentationDetents(Set(presentation.style.detents), selection: Binding(
                    get: { [weak presentation] in presentation?.selectedDetent ?? .large },
                    set: { [weak presentation] in presentation?.selectedDetent = $0 }
                ))
                .presentationDragIndicator(presentation.style.dragIndicator)
                .presentationBackgroundInteraction(presentation.style.backgroundInteraction)
                .presentationCornerRadius(presentation.style.cornerRadius)
                .presentationCompactAdaptation(presentation.style.compactAdaptation)
                .sheetSizing(presentation.style.sizing)
                .interactiveDismissDisabled(presentation.isInteractiveDismissDisabled)
                // The zoom has to wrap the whole presented content, NavigationStack included, or the system ignores it.
                .zoomTransition(sourceID: presentation.transition.zoomSourceID, in: namespace)
                .onAppear { [weak presentation] in presentation?.didAppear() }
                .onDisappear { [weak presentation] in presentation?.didDisappear() }
                .background(PresentationCompletionProbe { [weak presentation] in presentation?.didFinishPresenting() })
        }
    }
}

extension View {
    @ViewBuilder
    func sheetSizing(_ sizing: SheetSizing) -> some View {
        if #available(iOS 18, macOS 15, *) {
            switch sizing {
            case .automatic: self
            case .form: presentationSizing(.form)
            case .page: presentationSizing(.page)
            case .fitted: presentationSizing(.fitted)
            }
        } else {
            self
        }
    }
}

extension PresentationStyle {
    /// Covers don't exist on macOS, so they become sheets there.
    var resolvedKind: Kind {
        #if os(iOS)
        kind
        #else
        kind == .fullScreenCover ? .sheet : kind
        #endif
    }
}

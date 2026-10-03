import SwiftUI

/// Renders a ``Navigator``: its `NavigationStack`, the pushed screens, and any modal presentation, which is rendered recursively.
///
/// Hold the navigator in something long-lived, such as a coordinator or a `@State`. Never create it inside `body`.
///
/// ```swift
/// NavigationHost(appCoordinator.libraryNavigator)
/// ```
///
/// The host and everything it puts into SwiftUI hold the navigator **weakly**. SwiftUI sometimes keeps a removed subtree alive,
/// a `TabView` after a root switch for example. When it does, what it keeps is an empty shell, not your coordinators and view models.
public struct NavigationHost: View {
    private weak var navigator: Navigator?

    @Namespace private var namespace

    public init(_ navigator: Navigator) {
        self.navigator = navigator
    }

    public var body: some View {
        if let navigator {
            stack(navigator)
                .environment(\.transitionNamespace, namespace)
                .modifier(PresentationModifier(navigator: navigator, namespace: namespace))
                .modifier(AlertModifier(navigator: navigator))
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

/// Shows a screen's view and reports when it's on screen. Once a removed screen disappears, its view is dropped,
/// and this host re-renders empty. So even a hosting controller SwiftUI keeps around ends up holding nothing.
private struct ScreenHost: View {
    let screen: ScreenContent

    var body: some View {
        if let view = screen.view {
            view
                .onAppear { screen.didAppear() }
                .onDisappear { screen.didDisappear() }
        }
    }
}

// MARK: - Presentation

private struct PresentationModifier: ViewModifier {
    weak var navigator: Navigator?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .sheet(item: binding(for: .sheet), onDismiss: { [weak navigator] in navigator?.presentationDidFinishDismissing() }) { presentation in
                PresentedContent(presentation: presentation, namespace: namespace)
            }
            #if os(iOS)
            .fullScreenCover(item: binding(for: .fullScreenCover), onDismiss: { [weak navigator] in navigator?.presentationDidFinishDismissing() }) { presentation in
                PresentedContent(presentation: presentation, namespace: namespace)
            }
            #endif
    }

    private func binding(for kind: PresentationStyle.Kind) -> Binding<PresentationItem?> {
        Binding(
            get: { [weak navigator] in
                guard let presentation = navigator?.presentation, presentation.style.resolvedKind == kind else { return nil }
                return PresentationItem(presentation)
            },
            set: { [weak navigator] newValue in
                // SwiftUI only ever writes nil here, when the user swipes the sheet away.
                guard newValue == nil, let navigator, let current = navigator.presentation, current.style.resolvedKind == kind else { return }
                navigator.presentationDismissedBySystem(current)
            }
        )
    }
}

/// The value SwiftUI's `sheet(item:)` holds. It has a stable identity, and only a weak reference to the presentation.
private struct PresentationItem: Identifiable {
    let id: ObjectIdentifier
    weak var presentation: Presentation?

    init(_ presentation: Presentation) {
        id = ObjectIdentifier(presentation)
        self.presentation = presentation
    }
}

private struct PresentedContent: View {
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
                .presentationDetents(presentation.style.detents, selection: Binding(
                    get: { [weak presentation] in presentation?.selectedDetent ?? .large },
                    set: { [weak presentation] in presentation?.selectedDetent = $0 }
                ))
                .presentationDragIndicator(presentation.style.dragIndicator)
                .presentationBackgroundInteraction(presentation.style.backgroundInteraction)
                .presentationCornerRadius(presentation.style.cornerRadius)
                .interactiveDismissDisabled(presentation.isInteractiveDismissDisabled)
                // The zoom has to wrap the whole presented content, NavigationStack included, or the system ignores it.
                .zoomTransition(sourceID: presentation.transition.zoomSourceID, in: namespace)
                .onAppear { [weak presentation] in presentation?.hasAppeared = true }
        }
    }
}

extension PresentationStyle {
    /// Covers don't exist on macOS, so they become sheets there.
    var resolvedKind: Kind {
        #if os(iOS)
        kind
        #else
        .sheet
        #endif
    }
}

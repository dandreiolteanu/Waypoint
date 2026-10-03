import SwiftUI

/// Renders a ``Navigator``: its `NavigationStack`, the pushed screens, and any modal presentation, which is rendered recursively.
///
/// Hold the navigator in something long-lived, such as a coordinator or a `@State`. Never create it inside `body`.
///
/// ```swift
/// NavigationHost(appCoordinator.libraryNavigator)
/// ```
public struct NavigationHost: View {
    let navigator: Navigator

    @Namespace private var namespace

    public init(_ navigator: Navigator) {
        self.navigator = navigator
    }

    public var body: some View {
        stack
            .environment(\.transitionNamespace, namespace)
            .modifier(PresentationModifier(navigator: navigator, namespace: namespace))
    }

    @ViewBuilder
    private var stack: some View {
        if navigator.embedsInNavigationStack {
            NavigationStack(path: Binding(get: { navigator.path }, set: { navigator.setPath($0) })) {
                navigator.root.content
                    .navigationDestination(for: StackEntry.self) { entry in
                        entry.content
                            .zoomTransition(sourceID: entry.transition.zoomSourceID, in: namespace)
                    }
            }
        } else {
            navigator.root.content
        }
    }
}

// MARK: - Presentation

private struct PresentationModifier: ViewModifier {
    let navigator: Navigator
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .sheet(item: binding(for: .sheet), onDismiss: navigator.presentationDidFinishDismissing) { presentation in
                PresentedContent(presentation: presentation, namespace: namespace)
            }
            #if os(iOS)
            .fullScreenCover(item: binding(for: .fullScreenCover), onDismiss: navigator.presentationDidFinishDismissing) { presentation in
                PresentedContent(presentation: presentation, namespace: namespace)
            }
            #endif
    }

    private func binding(for kind: PresentationStyle.Kind) -> Binding<Presentation?> {
        Binding(
            get: {
                guard let presentation = navigator.presentation, presentation.style.resolvedKind == kind else { return nil }
                return presentation
            },
            set: { newValue in
                // SwiftUI only ever writes nil here, when the user swipes the sheet away.
                guard newValue == nil, let current = navigator.presentation, current.style.resolvedKind == kind else { return }
                navigator.presentationDismissedBySystem(current)
            }
        )
    }
}

private struct PresentedContent: View {
    @Bindable var presentation: Presentation
    /// The presenter's namespace. That's where the zoom source lives.
    let namespace: Namespace.ID

    var body: some View {
        NavigationHost(presentation.navigator)
            .presentationDetents(presentation.style.detents, selection: $presentation.selectedDetent)
            .presentationDragIndicator(presentation.style.dragIndicator)
            .presentationBackgroundInteraction(presentation.style.backgroundInteraction)
            .presentationCornerRadius(presentation.style.cornerRadius)
            .interactiveDismissDisabled(presentation.isInteractiveDismissDisabled)
            // The zoom has to wrap the whole presented content, NavigationStack included, or the system ignores it.
            .zoomTransition(sourceID: presentation.transition.zoomSourceID, in: namespace)
            .onAppear { presentation.hasAppeared = true }
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

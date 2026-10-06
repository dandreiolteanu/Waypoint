import SwiftUI

extension View {
    /// Marks this view as the anchor of popovers presented with `.popover(from:)` using the same id.
    ///
    /// ```swift
    /// Button("Share", systemImage: "square.and.arrow.up") { viewModel.share() }
    ///     .popoverSource(id: "share")
    /// // In the coordinator:
    /// present(.share(item), as: .popover(from: "share"))
    /// ```
    ///
    /// The anchor has to be in the same stack as the coordinator that presents (the natural setup: a screen's view model
    /// calls its own coordinator), and on screen when the popover is presented.
    public func popoverSource(id: some Hashable) -> some View {
        modifier(PopoverSourceModifier(id: AnyHashable(id)))
    }
}

private struct PopoverSourceModifier: ViewModifier {
    let id: AnyHashable
    @Environment(\.navigatorReference) private var reference
    @Environment(\.transitionNamespace) private var namespace
    @Namespace private var fallbackNamespace

    func body(content: Content) -> some View {
        let navigator = reference.navigator
        content
            .popover(item: presentationBinding(navigator, kind: .popover, sourceID: id), arrowEdge: arrowEdge(navigator)) { presentation in
                PresentedContent(presentation: presentation, namespace: namespace ?? fallbackNamespace)
            }
            .onAppear { [weak navigator] in navigator?.registerPopoverSource(id) }
            .onDisappear { [weak navigator] in navigator?.unregisterPopoverSource(id) }
    }

    private func arrowEdge(_ navigator: Navigator?) -> Edge {
        navigator?.presentation?.style.arrowEdge ?? .top
    }
}

/// A weak reference to the navigator of the enclosing ``NavigationHost``, for views that anchor presentations.
struct NavigatorReference {
    weak var navigator: Navigator?
}

extension EnvironmentValues {
    @Entry var navigatorReference = NavigatorReference()
}

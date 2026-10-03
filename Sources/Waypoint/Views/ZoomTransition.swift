import SwiftUI

extension View {
    /// Marks this view as where a `.zoom(sourceID:)` push or presentation grows out of, and shrinks back into.
    ///
    /// ```swift
    /// PhotoThumbnail(photo)
    ///     .transitionSource(id: photo.id)
    ///     .onTapGesture { coordinator.showPhoto(photo) }  // push(.photo(photo), transition: .zoom(sourceID: photo.id))
    /// ```
    ///
    /// The source has to be inside the same ``NavigationHost`` (the same stack, or the screens it pushed) as the navigator doing the push or presentation.
    public func transitionSource(id: some Hashable) -> some View {
        modifier(TransitionSourceModifier(id: AnyHashable(id)))
    }

    func zoomTransition(sourceID: AnyHashable?, in namespace: Namespace.ID) -> some View {
        modifier(ZoomDestinationModifier(sourceID: sourceID, namespace: namespace))
    }
}

extension EnvironmentValues {
    @Entry var transitionNamespace: Namespace.ID?
}

private struct TransitionSourceModifier: ViewModifier {
    let id: AnyHashable
    @Environment(\.transitionNamespace) private var namespace

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct ZoomDestinationModifier: ViewModifier {
    let sourceID: AnyHashable?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 18, *), let sourceID {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

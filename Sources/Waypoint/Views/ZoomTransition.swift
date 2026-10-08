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
    /// The screen a view is in. Zoom and popover source ids are scoped to it.
    @Entry var screenScope: ObjectIdentifier?
}

/// A source id scoped to the screen it's on. The same screen type pushed twice puts the same ids in one stack;
/// unscoped, SwiftUI can resolve a zoom to the copy on the covered screen, and UIKit crashes morphing from it
/// ("Cannot morph from a view that is not in the hierarchy").
struct ScopedSourceID: Hashable {
    let screen: ObjectIdentifier
    let id: AnyHashable

    /// `id` scoped to `screen`, or `id` itself outside any screen.
    static func key(_ id: AnyHashable, in screen: ObjectIdentifier?) -> AnyHashable {
        guard let screen else { return id }
        return AnyHashable(ScopedSourceID(screen: screen, id: id))
    }
}

private struct TransitionSourceModifier: ViewModifier {
    let id: AnyHashable
    @Environment(\.transitionNamespace) private var namespace
    @Environment(\.navigatorReference) private var reference
    @Environment(\.screenScope) private var screen

    func body(content: Content) -> some View {
        let navigator = reference.navigator
        let key = ScopedSourceID.key(id, in: screen)
        source(content, key: key)
            // The navigator only starts a zoom from a source that's on screen; see `Navigator.resolved(_:)`.
            .onAppear { [weak navigator] in navigator?.registerZoomSource(key) }
            .onDisappear { [weak navigator] in navigator?.unregisterZoomSource(key) }
    }

    @ViewBuilder
    private func source(_ content: Content, key: AnyHashable) -> some View {
        #if os(iOS)
        if let namespace {
            content.matchedTransitionSource(id: key, in: namespace)
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
        if let sourceID {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

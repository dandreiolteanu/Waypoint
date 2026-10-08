import SwiftUI

/// How a pushed or presented screen animates in.
///
/// `.zoom(sourceID:)` grows the screen out of the view marked with `.transitionSource(id:)` using the same id, and
/// shrinks it back on the way out (including interactive swipe-back and swipe-down). On macOS it falls back to the
/// default animation.
///
/// ```swift
/// // Source, in the screen that pushes:
/// Thumbnail(photo).transitionSource(id: photo.id)
/// // Navigation, in the coordinator:
/// push(.photo(photo.id), transition: .zoom(sourceID: photo.id))
/// ```
public struct ScreenTransition: Hashable {
    enum Kind: Hashable {
        case automatic
        case zoom(sourceID: AnyHashable)
    }

    let kind: Kind

    /// The platform's default: a slide for pushes, a rise for sheets and covers.
    public static var automatic: ScreenTransition { ScreenTransition(kind: .automatic) }

    /// Zooms out of (and back into) the view marked with `.transitionSource(id:)` using `sourceID`.
    /// When the same item can appear in several places on screen (a grid and a "related" row), give each place its own id.
    public static func zoom(sourceID: some Hashable) -> ScreenTransition {
        ScreenTransition(kind: .zoom(sourceID: AnyHashable(sourceID)))
    }

    var zoomSourceID: AnyHashable? {
        guard case let .zoom(sourceID) = kind else { return nil }
        return sourceID
    }
}

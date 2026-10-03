import SwiftUI

/// How a pushed or presented screen animates in.
///
/// `.zoom` grows the screen out of the view marked with ``SwiftUI/View/transitionSource(id:)`` using the same id.
/// It needs iOS 18; on earlier systems and on macOS it falls back to the default animation.
public struct ScreenTransition: Hashable {
    enum Kind: Hashable {
        case automatic
        case zoom(sourceID: AnyHashable)
    }

    let kind: Kind

    public static var automatic: ScreenTransition { ScreenTransition(kind: .automatic) }

    public static func zoom(sourceID: some Hashable) -> ScreenTransition {
        ScreenTransition(kind: .zoom(sourceID: AnyHashable(sourceID)))
    }

    var zoomSourceID: AnyHashable? {
        guard case let .zoom(sourceID) = kind else { return nil }
        return sourceID
    }
}

import SwiftUI

/// A navigator shown modally by another navigator.
///
/// It's observable, so a coordinator can move the sheet between detents (``selectedDetent``),
/// or lock swipe-to-dismiss while a form has unsaved changes (``isInteractiveDismissDisabled``), after it is on screen.
@MainActor
@Observable
public final class Presentation: Identifiable {
    public let style: PresentationStyle
    public let transition: ScreenTransition
    /// The presented content. It has its own stack and can present further.
    public let navigator: Navigator
    public var selectedDetent: PresentationDetent
    public var isInteractiveDismissDisabled: Bool
    /// Set once the presented content has appeared. After that, a dismissal has to wait for UIKit's
    /// dismissal animation to finish before anything else can be presented from the same navigator.
    @ObservationIgnored var hasAppeared = false
    /// The coordinator that asked for this presentation. When that coordinator finishes, the presentation goes with it.
    @ObservationIgnored weak var presentedBy: Coordinator?

    init(navigator: Navigator, style: PresentationStyle, transition: ScreenTransition) {
        self.navigator = navigator
        self.style = style
        self.transition = transition
        self.selectedDetent = style.initialDetent ?? Self.defaultDetent(in: style.detents)
        self.isInteractiveDismissDisabled = style.isInteractiveDismissDisabled
    }

    nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }

    private static func defaultDetent(in detents: Set<PresentationDetent>) -> PresentationDetent {
        // A set has no order, so mirror the system and open at the smaller standard detent. Pass `initialDetent` for custom detents.
        if detents.contains(.medium) { return .medium }
        if detents.contains(.large) || detents.isEmpty { return .large }
        return detents.first ?? .large
    }
}

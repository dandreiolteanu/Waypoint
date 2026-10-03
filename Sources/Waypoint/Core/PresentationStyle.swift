import SwiftUI

/// How a navigator is presented modally: a sheet (with its detents and chrome) or a full-screen cover.
public struct PresentationStyle {
    public enum Kind {
        case sheet
        case fullScreenCover
    }

    public let kind: Kind
    /// Wraps the presented screen in its own `NavigationStack`. Leave it on unless the screen is pure media (a photo viewer, say).
    /// Toolbars and titles need it, and so does pushing inside the presentation.
    public let embedsInNavigationStack: Bool
    public let detents: Set<PresentationDetent>
    /// The detent the sheet opens at. It must be one of ``detents``.
    public let initialDetent: PresentationDetent?
    public let dragIndicator: Visibility
    public let isInteractiveDismissDisabled: Bool
    public let backgroundInteraction: PresentationBackgroundInteraction
    public let cornerRadius: CGFloat?

    public static func sheet(
        detents: Set<PresentationDetent> = [.large],
        initialDetent: PresentationDetent? = nil,
        dragIndicator: Visibility = .automatic,
        isInteractiveDismissDisabled: Bool = false,
        backgroundInteraction: PresentationBackgroundInteraction = .automatic,
        cornerRadius: CGFloat? = nil,
        embedsInNavigationStack: Bool = true
    ) -> PresentationStyle {
        PresentationStyle(
            kind: .sheet,
            embedsInNavigationStack: embedsInNavigationStack,
            detents: detents,
            initialDetent: initialDetent,
            dragIndicator: dragIndicator,
            isInteractiveDismissDisabled: isInteractiveDismissDisabled,
            backgroundInteraction: backgroundInteraction,
            cornerRadius: cornerRadius
        )
    }

    /// A full-screen cover. On macOS, which has no covers, it presents as a large sheet.
    public static func fullScreenCover(
        isInteractiveDismissDisabled: Bool = false,
        embedsInNavigationStack: Bool = true
    ) -> PresentationStyle {
        PresentationStyle(
            kind: .fullScreenCover,
            embedsInNavigationStack: embedsInNavigationStack,
            detents: [.large],
            initialDetent: nil,
            dragIndicator: .automatic,
            isInteractiveDismissDisabled: isInteractiveDismissDisabled,
            backgroundInteraction: .automatic,
            cornerRadius: nil
        )
    }

    public static var sheet: PresentationStyle { .sheet() }
    public static var fullScreenCover: PresentationStyle { .fullScreenCover() }
}

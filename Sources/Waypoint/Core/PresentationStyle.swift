import SwiftUI

/// How a route or flow is shown modally: a sheet (with detents and chrome options) or a full-screen cover.
///
/// ```swift
/// .sheet                                                     // large sheet
/// .sheet(detents: [.medium, .large])                         // opens at medium, can grow to large
/// .sheet(detents: [.height(200), .large], backgroundInteraction: .enabled(upThrough: .height(200)))
/// .sheet(detents: [.medium], isInteractiveDismissDisabled: true)
/// .fullScreenCover
/// .fullScreenCover(embedsInNavigationStack: false)          // chromeless, e.g. a photo viewer
/// ```
public struct PresentationStyle {
    enum Kind {
        case sheet
        case fullScreenCover
    }

    let kind: Kind
    let embedsInNavigationStack: Bool
    let detents: [PresentationDetent]
    let initialDetent: PresentationDetent?
    let dragIndicator: Visibility
    let isInteractiveDismissDisabled: Bool
    let backgroundInteraction: PresentationBackgroundInteraction
    let cornerRadius: CGFloat?

    /// A sheet.
    ///
    /// - Parameters:
    ///   - detents: The heights the sheet can rest at, in order. It opens at the first one. Any `PresentationDetent` works,
    ///     including `.fraction`, `.height` and `.custom`.
    ///   - initialDetent: Opens the sheet at a detent other than the first. It must be one of `detents`.
    ///   - dragIndicator: Whether the grabber is shown. By default the system shows it when there's more than one detent.
    ///   - isInteractiveDismissDisabled: Stops swipe-to-dismiss. You can change it later through ``Presentation/isInteractiveDismissDisabled``.
    ///   - backgroundInteraction: Lets people use the screen behind the sheet, for example `.enabled(upThrough: .medium)`.
    ///   - cornerRadius: Overrides the sheet's corner radius.
    ///   - embedsInNavigationStack: Wraps the content in a `NavigationStack`, so it gets a navigation bar for its title and toolbar.
    ///     Leave it on unless the content draws all of its own chrome.
    public static func sheet(
        detents: [PresentationDetent] = [.large],
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
            detents: detents.isEmpty ? [.large] : detents,
            initialDetent: initialDetent,
            dragIndicator: dragIndicator,
            isInteractiveDismissDisabled: isInteractiveDismissDisabled,
            backgroundInteraction: backgroundInteraction,
            cornerRadius: cornerRadius
        )
    }

    /// A full-screen cover. On macOS, which has no covers, it presents as a large sheet.
    ///
    /// - Parameters:
    ///   - isInteractiveDismissDisabled: Stops the swipe-down that a zoom transition adds to covers.
    ///   - embedsInNavigationStack: Wraps the content in a `NavigationStack`. Turn it off for chromeless content.
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

    /// A large sheet with the default options.
    public static var sheet: PresentationStyle { .sheet() }

    /// A full-screen cover with the default options.
    public static var fullScreenCover: PresentationStyle { .fullScreenCover() }

    /// The detent the sheet opens at.
    var openingDetent: PresentationDetent {
        initialDetent ?? detents.first ?? .large
    }
}

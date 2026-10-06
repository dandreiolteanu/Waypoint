import SwiftUI

/// How a route or flow is shown modally: a sheet, a full-screen cover, or a popover.
///
/// ```swift
/// .sheet                                                     // large sheet
/// .sheet(detents: [.medium, .large])                         // opens at medium, can grow to large
/// .sheet(detents: [.height(200), .large], backgroundInteraction: .enabled(upThrough: .height(200)))
/// .sheet(sizing: .page)                                      // a page-sized sheet on iPad
/// .fullScreenCover
/// .fullScreenCover(embedsInNavigationStack: false)          // chromeless, e.g. a photo viewer
/// .popover(from: "filters")                                  // a popover on iPad, a sheet on iPhone
/// ```
public struct PresentationStyle {
    enum Kind {
        case sheet
        case fullScreenCover
        case popover
    }

    let kind: Kind
    let embedsInNavigationStack: Bool
    let detents: [PresentationDetent]
    let initialDetent: PresentationDetent?
    let dragIndicator: Visibility
    let isInteractiveDismissDisabled: Bool
    let backgroundInteraction: PresentationBackgroundInteraction
    let cornerRadius: CGFloat?
    let sizing: SheetSizing
    let popoverSourceID: AnyHashable?
    let arrowEdge: Edge?
    let compactAdaptation: PresentationAdaptation

    /// A sheet.
    ///
    /// - Parameters:
    ///   - detents: The heights the sheet can rest at, in order. It opens at the first one. Any `PresentationDetent` works,
    ///     including `.fraction`, `.height` and `.custom`. On iPad, where sheets float as cards, detents apply only in
    ///     compact width.
    ///   - initialDetent: Opens the sheet at a detent other than the first. It must be one of `detents`.
    ///   - dragIndicator: Whether the grabber is shown. By default the system shows it when there's more than one detent.
    ///   - isInteractiveDismissDisabled: Stops swipe-to-dismiss. You can change it later through ``Presentation/isInteractiveDismissDisabled``.
    ///   - backgroundInteraction: Lets people use the screen behind the sheet, for example `.enabled(upThrough: .medium)`.
    ///   - cornerRadius: Overrides the sheet's corner radius.
    ///   - sizing: How big the sheet is on iPad (iOS 18 and later). See ``SheetSizing``.
    ///   - embedsInNavigationStack: Wraps the content in a `NavigationStack`, so it gets a navigation bar for its title and toolbar.
    ///     Leave it on unless the content draws all of its own chrome.
    public static func sheet(
        detents: [PresentationDetent] = [.large],
        initialDetent: PresentationDetent? = nil,
        dragIndicator: Visibility = .automatic,
        isInteractiveDismissDisabled: Bool = false,
        backgroundInteraction: PresentationBackgroundInteraction = .automatic,
        cornerRadius: CGFloat? = nil,
        sizing: SheetSizing = .automatic,
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
            cornerRadius: cornerRadius,
            sizing: sizing
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
            isInteractiveDismissDisabled: isInteractiveDismissDisabled
        )
    }

    /// A popover pointing at the view marked with `.popoverSource(id:)` using the same id.
    ///
    /// On iPad it's a popover. In compact width (iPhone, or a narrow iPad window) it adapts as `compactAdaptation` says:
    /// a sheet by default (with `detents`), or `.popover` to stay a popover everywhere. If no view with that id is on
    /// screen when it's presented, it's shown as a sheet instead.
    ///
    /// ```swift
    /// // The anchor, in the screen that presents:
    /// Button("Filters", systemImage: "line.3.horizontal.decrease") { viewModel.showFilters() }
    ///     .popoverSource(id: "filters")
    /// // The coordinator:
    /// present(.filters, as: .popover(from: "filters", detents: [.medium]))
    /// ```
    ///
    /// - Parameters:
    ///   - sourceID: The id of the anchor view.
    ///   - arrowEdge: The edge of the anchor the popover attaches to. `nil` uses the top edge.
    ///   - compactAdaptation: What it becomes in compact width: `.sheet` (the default), `.popover`, or `.fullScreenCover`.
    ///   - detents: The sheet's detents, when it adapts to a sheet.
    ///   - embedsInNavigationStack: Wraps the content in a `NavigationStack`, for a title and toolbar. Off by default,
    ///     because popovers usually show compact content.
    public static func popover(
        from sourceID: some Hashable,
        arrowEdge: Edge? = nil,
        compactAdaptation: PresentationAdaptation = .sheet,
        detents: [PresentationDetent] = [.medium, .large],
        embedsInNavigationStack: Bool = false
    ) -> PresentationStyle {
        PresentationStyle(
            kind: .popover,
            embedsInNavigationStack: embedsInNavigationStack,
            detents: detents.isEmpty ? [.large] : detents,
            popoverSourceID: AnyHashable(sourceID),
            arrowEdge: arrowEdge,
            compactAdaptation: compactAdaptation
        )
    }

    /// A large sheet with the default options.
    public static var sheet: PresentationStyle { .sheet() }

    /// A full-screen cover with the default options.
    public static var fullScreenCover: PresentationStyle { .fullScreenCover() }

    private init(
        kind: Kind,
        embedsInNavigationStack: Bool,
        detents: [PresentationDetent] = [.large],
        initialDetent: PresentationDetent? = nil,
        dragIndicator: Visibility = .automatic,
        isInteractiveDismissDisabled: Bool = false,
        backgroundInteraction: PresentationBackgroundInteraction = .automatic,
        cornerRadius: CGFloat? = nil,
        sizing: SheetSizing = .automatic,
        popoverSourceID: AnyHashable? = nil,
        arrowEdge: Edge? = nil,
        compactAdaptation: PresentationAdaptation = .automatic
    ) {
        self.kind = kind
        self.embedsInNavigationStack = embedsInNavigationStack
        self.detents = detents
        self.initialDetent = initialDetent
        self.dragIndicator = dragIndicator
        self.isInteractiveDismissDisabled = isInteractiveDismissDisabled
        self.backgroundInteraction = backgroundInteraction
        self.cornerRadius = cornerRadius
        self.sizing = sizing
        self.popoverSourceID = popoverSourceID
        self.arrowEdge = arrowEdge
        self.compactAdaptation = compactAdaptation
    }

    /// The detent the sheet opens at.
    var openingDetent: PresentationDetent {
        initialDetent ?? detents.first ?? .large
    }

    /// This style shown as a sheet: what a popover becomes when its anchor isn't on screen.
    var asSheet: PresentationStyle {
        PresentationStyle(
            kind: .sheet,
            embedsInNavigationStack: embedsInNavigationStack,
            detents: detents,
            initialDetent: initialDetent,
            dragIndicator: dragIndicator,
            isInteractiveDismissDisabled: isInteractiveDismissDisabled,
            backgroundInteraction: backgroundInteraction,
            cornerRadius: cornerRadius,
            sizing: sizing
        )
    }
}

/// How big a sheet is where sheets float, as on iPad and Mac. Needs iOS 18; earlier systems use the default size.
public enum SheetSizing: Sendable {
    /// The system default.
    case automatic
    /// A form-sized card, the iPad default for forms and settings.
    case form
    /// A larger, page-sized card, for reading content.
    case page
    /// Sized to fit the content's ideal size. Give the content one (`.frame(idealWidth: 420, idealHeight: 320)`), and
    /// present it with `embedsInNavigationStack: false`: a navigation stack has no ideal size of its own.
    case fitted
}

import SwiftUI

/// How the current screen got on screen. Read it to choose between the system back button and a close button.
///
/// ``NavigationHost`` sets it on every screen it shows: the root of a stack is ``root`` or ``presented(_:)``, and
/// everything pushed on top is ``pushed``. SwiftUI's own `isPresented` and `dismiss` can't tell those apart.
///
/// ```swift
/// struct CloseIfPresented: ViewModifier {
///     @Environment(\.screenPlacement) private var placement
///     let close: () -> Void
///
///     func body(content: Content) -> some View {
///         content.toolbar {
///             if placement.isPresented {
///                 ToolbarItem(placement: .cancellationAction) {
///                     Button("Close", systemImage: "xmark", action: close)
///                 }
///             }
///         }
///     }
/// }
/// ```
public enum ScreenPlacement: Hashable, Sendable {
    /// The first screen of a stack nobody presented: the app's root, a tab, a split view column.
    case root
    /// Pushed onto a stack. The system back button handles leaving.
    case pushed
    /// The first screen of a sheet, cover or popover. It needs its own way to close.
    case presented(PresentationKind)

    /// Whether this is the first screen of a sheet, cover or popover.
    public var isPresented: Bool {
        if case .presented = self { true } else { false }
    }
}

/// How a navigator is actually shown modally: a popover with no anchor on screen is a sheet, and on macOS a
/// full-screen cover is a sheet.
public enum PresentationKind: Hashable, Sendable {
    case sheet
    case fullScreenCover
    case popover

    init(_ kind: PresentationStyle.Kind) {
        switch kind {
        case .sheet: self = .sheet
        case .fullScreenCover: self = .fullScreenCover
        case .popover: self = .popover
        }
    }
}

public extension EnvironmentValues {
    /// How the current screen got on screen. See ``ScreenPlacement``.
    @Entry var screenPlacement: ScreenPlacement = .root
}

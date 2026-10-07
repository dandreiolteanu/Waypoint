import SwiftUI

/// A sheet or full-screen cover that is on screen.
///
/// Reach it through ``Coordinator/presented`` (what a coordinator showed) or ``Coordinator/enclosingPresentation``
/// (the one a presented flow lives in). Both properties are observable and writable while it's up:
///
/// ```swift
/// presented?.selectedDetent = .large                               // move the sheet
/// enclosingPresentation?.isInteractiveDismissDisabled = isDirty    // block swipe-to-dismiss while editing
/// ```
@MainActor
@Observable
public final class Presentation: Identifiable {
    /// The detent the sheet is resting at. It follows the user's drags, and setting it moves the sheet.
    public var selectedDetent: PresentationDetent
    /// Whether swipe-to-dismiss is blocked. Programmatic dismissal still works.
    public var isInteractiveDismissDisabled: Bool

    let style: PresentationStyle
    let transition: ScreenTransition
    /// The presented content, with a stack of its own. It can present further.
    let navigator: Navigator
    /// Set once the presented content has appeared. After that, a dismissal has to wait for UIKit's
    /// dismissal animation to finish before anything else can be presented from the same navigator.
    @ObservationIgnored var hasAppeared = false
    /// Set once the presentation animation has finished. Only then can the presented navigator present on top of it.
    @ObservationIgnored var isFullyPresented = false
    /// The coordinator that asked for this presentation. When that coordinator finishes, the presentation goes with it.
    @ObservationIgnored weak var presentedBy: Coordinator?
    /// An alert waiting for this presentation to finish appearing. UIKit can't present it from a sheet still animating in.
    @ObservationIgnored var alertOnAppear: AlertRequest?

    init(navigator: Navigator, style: PresentationStyle, transition: ScreenTransition) {
        self.navigator = navigator
        self.style = style
        self.transition = transition
        self.selectedDetent = style.openingDetent
        self.isInteractiveDismissDisabled = style.isInteractiveDismissDisabled
    }

    /// Whether this is a sheet rather than a full-screen cover.
    public var isSheet: Bool { style.kind == .sheet }

    /// The route at the bottom of the presented stack, as `Route`, or `nil` for another route type. Mostly for tests.
    public func route<Route: Hashable>(as type: Route.Type) -> Route? {
        navigator.root.route(as: type)
    }

    /// The coordinator at the root of the presented stack, as `C`: the flow shown with `presentFlow`.
    /// In tests, use it to drive a presented flow: `shop.presented?.coordinator(as: CheckoutCoordinator.self)?.next()`.
    public func coordinator<C: Coordinator>(as type: C.Type) -> C? {
        navigator.rootCoordinator(as: type)
    }

    /// The route on top of the presented stack, as `Route`, or `nil` for another route type. Mostly for tests.
    public func topRoute<Route: Hashable>(as type: Route.Type) -> Route? {
        navigator.top.route(as: type)
    }

    /// The presentation's identity.
    nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// The presentation animation finished: it's now safe to present on top of it.
    func didFinishPresenting() {
        hasAppeared = true
        isFullyPresented = true
        navigator.showQueuedPresentation()
        if let alert = alertOnAppear {
            alertOnAppear = nil
            navigator.show(alert)
        }
    }

    /// Popovers have no `onDismiss`, so their content disappearing is the signal that the dismissal finished.
    func didDisappear() {
        guard style.kind == .popover else { return }
        navigator.presenter?.presentationDidFinishDismissing()
    }

    /// The presented content was inserted. Its presentation animation is still running.
    func didAppear() {
        hasAppeared = true
    }
}

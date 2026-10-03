import SwiftUI

/// Base class for coordinators: objects that own a flow's navigation decisions.
///
/// Subclass it and adopt ``Routing``, or inherit from ``FlowCoordinator``, which is the same thing:
///
/// ```swift
/// final class LibraryCoordinator: FlowCoordinator {
///     enum Route: Hashable { case shelf, book(Book.ID) }
///
///     var initialRoute: Route { .shelf }
///
///     func destination(for route: Route) -> some View {
///         switch route {
///         case .shelf: ShelfView(onSelect: { self.push(.book($0)) })
///         case .book(let id): BookView(id: id)
///         }
///     }
/// }
/// ```
///
/// ## Ownership
/// A coordinator is retained by the navigation entries it built, never by its parent.
/// It's released when its last screen is popped or dismissed. Then ``didFinish()`` runs once.
/// Its link to the ``navigator`` is weak, so a view, view model or closure can hold a coordinator strongly without creating a cycle.
/// That's why the example above captures `self` strongly.
/// The one rule: **a coordinator must not hold its own screens' view models strongly.**
@MainActor
open class Coordinator {
    /// The navigator this coordinator's screens are pushed onto. It's `nil` until the coordinator has been started.
    public private(set) weak var navigator: Navigator?
    /// The first entry this coordinator put on screen. Removing it finishes the flow.
    weak var anchor: StackEntry?
    public private(set) var isFinished = false
    private(set) var hasStarted = false

    public init() {
        LifetimeTracker.track(self, kind: .coordinator)
    }

    /// Called once, when the coordinator's first screen leaves navigation (popped, dismissed, or torn down with its tree).
    /// Override it to cancel work the flow started.
    open func didFinish() {}

    func attach(to navigator: Navigator, anchor: StackEntry) {
        assert(!hasStarted, "Waypoint: \(type(of: self)) was started twice. Create a new coordinator per flow.")
        self.navigator = navigator
        self.anchor = anchor
        hasStarted = true
    }

    func finishLifecycle() {
        guard !isFinished else { return }
        isFinished = true
        // Whatever this flow presented goes with it, e.g. a sheet a pushed child opened before the user popped back past it.
        navigator?.dismissPresentations(by: self)
        didFinish()
    }
}

/// A coordinator that builds its screens from a `Route` enum.
@MainActor
public protocol Routing: Coordinator {
    associatedtype Route: Hashable
    associatedtype Destination: View

    /// The first screen shown when the coordinator is pushed, presented, or made a navigator's root.
    var initialRoute: Route { get }

    /// Builds the screen for `route`. It's called once per push or presentation, and the result is kept for as long as the screen is in the stack.
    /// Create view models here, not in a view's `init`, so each screen gets exactly one.
    @ViewBuilder func destination(for route: Route) -> Destination
}

/// A ``Coordinator`` that adopts ``Routing``. Subclass this one.
public typealias FlowCoordinator = Coordinator & Routing

extension Routing {
    func makeEntry(for route: Route, transition: ScreenTransition) -> StackEntry {
        StackEntry(route: AnyHashable(route), content: AnyView(destination(for: route)), owner: self, transition: transition)
    }
}

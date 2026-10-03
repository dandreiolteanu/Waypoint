import SwiftUI

/// The base class of every coordinator. Subclass ``FlowCoordinator`` rather than this class directly.
///
/// A coordinator owns one flow's navigation decisions: which screen comes next, what gets presented, and what happens
/// with the result. Screens and view models ask it to navigate; they never navigate themselves.
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
///         case .book(let id): BookView(viewModel: BookViewModel(id: id, coordinator: self))
///         }
///     }
/// }
/// ```
///
/// ## Lifetime
/// A coordinator is kept alive by the screens it put on screen, not by its parent. When its *first* screen leaves
/// (popped, dismissed, or torn down with its tree) the flow ends and ``didFinish()`` runs, once. The object itself is
/// freed when the last screen, view model or task holding it lets go. Its link to the ``navigator`` is weak, so views,
/// view models and closures can hold a coordinator strongly (as `self.push` above does) without a retain cycle.
///
/// The one rule: **a coordinator must not keep its own screens' view models in stored properties.** That's the only way
/// to create a cycle.
///
/// ## What a coordinator can do
/// - Push: ``Routing/push(_:transition:)``, ``Routing/push(_:)``, ``Routing/setStack(_:)``, ``pushFlow(_:transition:then:)``
/// - Present: ``Routing/present(_:as:transition:)``, ``presentFlow(_:as:transition:)``
/// - Await a result: ``Routing/push(transition:_:)``, ``Routing/present(as:transition:_:)``, ``pushFlow(transition:_:)``, ``presentFlow(as:transition:_:)``
/// - Close: ``finish()``, ``pop()``, ``popToStart()``, ``popToRoot()``, ``dismissPresented()``, ``dismissAll()``
/// - Ask: ``alert(_:message:style:actions:)``, ``confirm(_:message:confirmTitle:role:cancelTitle:style:)``
@MainActor
open class Coordinator {
    /// The navigator this coordinator's screens live in. It's `nil` before the coordinator is started, and after the
    /// navigator is gone. You rarely need it; the coordinator's own methods cover navigation.
    public private(set) weak var navigator: Navigator?
    /// The first entry this coordinator put on screen. Removing it finishes the flow.
    weak var anchor: StackEntry?
    /// Whether this flow has ended (its first screen left navigation). A finished coordinator ignores navigation calls,
    /// which protects the parent's screens from a late `Task` in a flow the user already left.
    public private(set) var isFinished = false
    private(set) var hasStarted = false

    /// Creates a coordinator. Starting it is up to whoever pushes, presents or roots it.
    public init() {
        LifetimeTracker.track(self, kind: .coordinator)
    }

    /// Called once, when this flow ends: its first screen was popped or dismissed, or its tree was torn down.
    /// Override it to cancel work the flow started. Sheets the flow presented are dismissed for you.
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

/// The routes of a coordinator, and how each one becomes a screen. Adopt it through ``FlowCoordinator``.
@MainActor
public protocol Routing: Coordinator {
    /// Every screen this coordinator can show. Associated values carry the data a screen needs; a ``Callback`` carries
    /// data back.
    associatedtype Route: Hashable
    /// The view type built by ``destination(for:)``. Inferred; you never write it.
    associatedtype Destination: View

    /// The first screen, shown when the coordinator is pushed, presented, or made a navigator's root.
    var initialRoute: Route { get }

    /// Builds the screen for `route`.
    ///
    /// It's called **once** per push or presentation, and the view it returns lives as long as the screen does.
    /// So create each screen's view model here, and hand it to the view:
    ///
    /// ```swift
    /// func destination(for route: Route) -> some View {
    ///     switch route {
    ///     case .book(let id): BookView(viewModel: BookViewModel(id: id, coordinator: self))
    ///     }
    /// }
    /// ```
    @ViewBuilder func destination(for route: Route) -> Destination
}

/// The class to subclass for a coordinator: a ``Coordinator`` with ``Routing``.
///
/// ```swift
/// final class SettingsCoordinator: FlowCoordinator {
///     enum Route: Hashable { case list, about }
///     var initialRoute: Route { .list }
///     func destination(for route: Route) -> some View { … }
/// }
/// ```
public typealias FlowCoordinator = Coordinator & Routing

extension Routing {
    func makeEntry(for route: Route, transition: ScreenTransition) -> StackEntry {
        StackEntry(route: AnyHashable(route), content: AnyView(destination(for: route)), owner: self, transition: transition)
    }
}

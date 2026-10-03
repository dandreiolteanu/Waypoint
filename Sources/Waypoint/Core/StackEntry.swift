import SwiftUI

/// One screen in a ``Navigator``: the root, a pushed screen, or the root of a presented navigator.
///
/// An entry owns everything its screen needs. That means the built view and, through ``owner``, the coordinator that built it.
/// Removing the entry from navigation state is what releases them.
@MainActor
public final class StackEntry: Hashable, Identifiable {
    /// The route value the screen was built from, type-erased so one stack can mix routes from several coordinators.
    public let route: AnyHashable
    /// The coordinator that built the screen. It's retained here, so a coordinator lives exactly as long as one of its screens.
    public let owner: Coordinator?
    public let transition: ScreenTransition
    let content: AnyView
    private var removalHandlers: [() -> Void] = []
    private(set) var isRemoved = false

    init(route: AnyHashable, content: AnyView, owner: Coordinator?, transition: ScreenTransition = .automatic) {
        self.route = route
        self.content = content
        self.owner = owner
        self.transition = transition
        LifetimeTracker.track(self, kind: .entry)
    }

    /// The route as a concrete type, or `nil` when the screen came from a different route type.
    public func route<Route: Hashable>(as type: Route.Type) -> Route? {
        route.base as? Route
    }

    nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }

    nonisolated public static func == (lhs: StackEntry, rhs: StackEntry) -> Bool { lhs === rhs }

    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    // MARK: - Removal

    func onRemove(_ handler: @escaping () -> Void) {
        guard !isRemoved else { return handler() }
        removalHandlers.append(handler)
    }

    func markRemoved() {
        guard !isRemoved else { return }
        isRemoved = true
        let handlers = removalHandlers
        removalHandlers.removeAll()
        handlers.forEach { $0() }
        if let owner, owner.anchor === self {
            owner.finishLifecycle()
        }
    }
}

import SwiftUI

// MARK: - Routes

extension Routing {
    /// Pushes `route` onto this coordinator's stack.
    public func push(_ route: Route, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        navigator.push(makeEntry(for: route, transition: transition))
    }

    /// Pushes several routes at once. Useful for deep links.
    public func push(_ routes: [Route]) {
        guard let navigator = requireNavigator() else { return }
        navigator.push(contentsOf: routes.map { makeEntry(for: $0, transition: .automatic) })
    }

    /// Replaces every screen above this coordinator's first screen with `routes`.
    /// Called on a navigator's root coordinator, this is "set the whole stack".
    public func setStack(_ routes: [Route]) {
        guard let navigator = requireNavigator(), let anchor else { return }
        let base: [StackEntry] = if anchor === navigator.root {
            []
        } else if let index = navigator.path.firstIndex(of: anchor) {
            Array(navigator.path.prefix(through: index))
        } else {
            navigator.path
        }
        navigator.setPath(base + routes.map { makeEntry(for: $0, transition: .automatic) })
    }

    /// Presents `route` modally in a new navigator. The screen is built by this coordinator.
    /// To push screens inside the presentation, present a child coordinator with ``Coordinator/present(child:as:transition:)`` instead.
    public func present(_ route: Route, as style: PresentationStyle = .sheet, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        let presented = Navigator(rootEntry: makeEntry(for: route, transition: .automatic), embedsInNavigationStack: style.embedsInNavigationStack)
        navigator.present(presented, style: style, transition: transition)
    }

    /// The routes of this coordinator's screens currently in its navigator, bottom first. Handy in tests.
    public var routes: [Route] {
        navigator?.entries.filter { $0.owner === self }.compactMap { $0.route(as: Route.self) } ?? []
    }
}

// MARK: - Child coordinators

extension Coordinator {
    /// Pushes `child`'s initial route onto this coordinator's stack. The child shares the stack and pushes onto it too.
    /// The child is released once all of its screens are popped.
    public func push<Child: Routing>(child: Child, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        let entry = child.makeEntry(for: child.initialRoute, transition: transition)
        child.attach(to: navigator, anchor: entry)
        navigator.push(entry)
    }

    /// Presents `child` modally with a stack of its own. The child is released once the presentation is dismissed.
    public func present<Child: Routing>(child: Child, as style: PresentationStyle = .sheet, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        navigator.present(Navigator(root: child, embedsInNavigationStack: style.embedsInNavigationStack), style: style, transition: transition)
    }

    // MARK: Closing

    /// Pops the top screen of this coordinator's stack.
    public func pop() {
        navigator?.pop()
    }

    public func popToRoot() {
        navigator?.popToRoot()
    }

    /// Pops back to this coordinator's first screen.
    public func popToStart() {
        guard let anchor else { return }
        navigator?.pop(to: anchor)
    }

    /// Dismisses the modal presentation this coordinator's screens are in.
    public func dismiss() {
        navigator?.dismiss()
    }

    /// Dismisses whatever this coordinator's navigator is presenting.
    public func dismissPresented() {
        navigator?.dismissPresentation()
    }

    /// Ends this flow, whatever the way in was. A presented flow is dismissed. A pushed one is popped back to the screen it was pushed from.
    public func finish() {
        guard let anchor, let navigator else { return }
        navigator.close(anchor)
    }

    func requireNavigator(function: StaticString = #function) -> Navigator? {
        if let navigator, !navigator.isTornDown { return navigator }
        assert(hasStarted, "Waypoint: \(type(of: self)).\(function) called before the coordinator was started. Push, present, or make it a navigator's root first.")
        return nil
    }
}

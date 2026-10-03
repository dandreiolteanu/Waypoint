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

    /// Presents `route` modally in a new navigator. The screen is built, and owned, by this coordinator.
    /// So the screen closes itself with ``Coordinator/dismissPresented()`` (or SwiftUI's `dismiss`), and its detent is ``Coordinator/presented``.
    /// To push screens inside the presentation, present a child coordinator with ``Coordinator/present(child:as:transition:)`` instead.
    public func present(_ route: Route, as style: PresentationStyle = .sheet, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        let presented = Navigator(rootEntry: makeEntry(for: route, transition: .automatic), embedsInNavigationStack: style.embedsInNavigationStack)
        navigator.present(presented, style: style, transition: transition, by: self)
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
        navigator.present(Navigator(root: child, embedsInNavigationStack: style.embedsInNavigationStack), style: style, transition: transition, by: self)
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

    // Two directions, two names:
    // - `presentation` and `dismiss()` are about the modal this coordinator's *flow* lives in (it was presented with `present(child:)`).
    // - `presented` and `dismissPresented()` are about what this coordinator *showed* on top of its flow, including a single route
    //   shown with `present(_:)`. A screen in such a sheet is built by the presenting coordinator, so it closes itself with `dismissPresented()`.

    /// The modal presentation this coordinator's flow is in, if any. Write to it to change the detent, or to block swipe-to-dismiss.
    public var presentation: Presentation? {
        navigator?.containingPresentation
    }

    /// What this coordinator's navigator is presenting right now, if anything. For a route shown with ``Routing/present(_:as:transition:)``,
    /// this is how its coordinator moves the sheet's detent or locks dismissal.
    public var presented: Presentation? {
        navigator?.presentation
    }

    /// Dismisses the modal presentation this coordinator's flow is in. Does nothing for a flow that isn't presented.
    public func dismiss() {
        navigator?.dismiss()
    }

    /// Dismisses whatever this coordinator's navigator is presenting. Screens shown with ``Routing/present(_:as:transition:)`` close themselves with this.
    public func dismissPresented() {
        navigator?.dismissPresentation()
    }

    /// Ends this flow, whatever the way in was. A presented flow is dismissed. A pushed one is popped back to the screen it was pushed from.
    public func finish() {
        guard let anchor, let navigator else { return }
        navigator.close(anchor)
    }

    /// The navigator to act on, or `nil` once this flow has finished.
    /// A finished flow can still be alive (a `Task` it started holds it), but it must not navigate any more.
    func requireNavigator(function: StaticString = #function) -> Navigator? {
        if isFinished { return nil }
        if let navigator, !navigator.isTornDown { return navigator }
        assert(hasStarted, "Waypoint: \(type(of: self)).\(function) called before the coordinator was started. Push, present, or make it a navigator's root first.")
        return nil
    }
}

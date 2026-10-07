import SwiftUI

// MARK: - Routes

extension Routing {
    /// Pushes `route` onto this coordinator's stack.
    ///
    /// ```swift
    /// push(.book(id))
    /// push(.book(id), transition: .zoom(sourceID: id))
    /// ```
    public func push(_ route: Route, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        navigator.push(makeEntry(for: route, transition: navigator.resolved(transition)))
    }

    /// Pushes several routes at once, bottom first. Handy for deep links.
    public func push(_ routes: [Route]) {
        guard let navigator = requireNavigator() else { return }
        navigator.push(contentsOf: routes.map { makeEntry(for: $0, transition: .automatic) })
    }

    /// Replaces every screen above this coordinator's first screen with `routes`.
    /// Called on a navigator's root coordinator, this sets the whole stack.
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

    /// Presents a single `route` modally. The screen is built (and owned) by this coordinator.
    ///
    /// Close it with ``Coordinator/dismissPresented()``, or let the user swipe it away. Its detent and dismiss lock
    /// are on ``Coordinator/presented``. To push screens *inside* the presentation, present a flow with
    /// ``Coordinator/presentFlow(_:as:transition:)`` instead.
    ///
    /// ```swift
    /// present(.filters, as: .sheet(detents: [.medium, .large]))
    /// present(.photo(id), as: .fullScreenCover(embedsInNavigationStack: false), transition: .zoom(sourceID: id))
    /// ```
    public func present(_ route: Route, as style: PresentationStyle = .sheet, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        let presented = Navigator(rootEntry: makeEntry(for: route, transition: .automatic), embedsInNavigationStack: style.embedsInNavigationStack)
        navigator.present(presented, style: style, transition: transition, by: self)
    }

    /// The routes of this coordinator's screens in its stack, bottom first. Mostly for tests: `#expect(library.routes == [.shelf, .book(1)])`.
    public var routes: [Route] {
        navigator?.entries.filter { $0.owner === self }.compactMap { $0.route(as: Route.self) } ?? []
    }
}

// MARK: - Flows

extension Coordinator {
    /// Pushes a child flow onto this coordinator's stack, starting at its ``Routing/initialRoute``.
    ///
    /// The child shares the stack: it pushes onto it too, and ``finish()`` pops back to the screen that pushed it.
    /// It's freed once all of its screens are gone. Pass `then` to push more of the child's routes right away (deep links).
    ///
    /// ```swift
    /// pushFlow(SettingsCoordinator())
    /// pushFlow(SettingsCoordinator(), then: [.about])
    /// ```
    public func pushFlow<Child: Routing>(_ child: Child, transition: ScreenTransition = .automatic, then routes: [Child.Route] = []) {
        guard let navigator = requireNavigator() else { return }
        attachAndPush(child, transition: transition, on: navigator)
        if !routes.isEmpty { child.push(routes) }
    }

    /// Pushes a child flow whose concrete type isn't known here, for example one built by a dependency container.
    ///
    /// ```swift
    /// let settings: any Routing = container.settingsCoordinator()
    /// pushFlow(settings)
    /// ```
    public func pushFlow(_ child: any Routing, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        attachAndPush(child, transition: transition, on: navigator)
    }

    /// Makes the child's first screen, attaches the child to `navigator`, and pushes the screen.
    @discardableResult
    func attachAndPush<Child: Routing>(_ child: Child, transition: ScreenTransition, on navigator: Navigator) -> StackEntry {
        let entry = child.makeEntry(for: child.initialRoute, transition: navigator.resolved(transition))
        child.attach(to: navigator, anchor: entry)
        navigator.push(entry)
        return entry
    }

    /// Presents a child flow modally, with a stack of its own. The child is freed once the presentation is dismissed.
    ///
    /// Inside the flow, ``finish()`` dismisses it and ``enclosingPresentation`` controls the sheet.
    ///
    /// ```swift
    /// presentFlow(CheckoutCoordinator(cart: cart), as: .sheet(detents: [.large]))
    /// ```
    public func presentFlow<Child: Routing>(_ child: Child, as style: PresentationStyle = .sheet, transition: ScreenTransition = .automatic) {
        guard let navigator = requireNavigator() else { return }
        navigator.present(Navigator(root: child, embedsInNavigationStack: style.embedsInNavigationStack), style: style, transition: transition, by: self)
    }

    // MARK: Closing

    /// Ends this flow, whatever the way in was.
    ///
    /// - A presented flow is dismissed.
    /// - A pushed flow is popped back to the screen that pushed it.
    /// - A navigator's root flow can't end this way (there's nothing to go back to). Tear the navigator down instead.
    public func finish() {
        guard let anchor, let navigator else { return }
        navigator.close(anchor)
    }

    /// Pops the top screen of this coordinator's stack, even when that screen belongs to a flow pushed on top.
    public func pop() {
        activeNavigator?.pop()
    }

    /// Pops this coordinator's stack back to its root screen. In a pushed flow, that pops into the parent's screens and
    /// ends the flow; use ``popToStart()`` to stay in it.
    public func popToRoot() {
        activeNavigator?.popToRoot()
    }

    /// Pops back to this coordinator's own first screen.
    public func popToStart() {
        guard let anchor else { return }
        activeNavigator?.pop(to: anchor)
    }

    /// Dismisses whatever this coordinator's stack is presenting (a route from ``Routing/present(_:as:transition:)``, or a
    /// flow from ``presentFlow(_:as:transition:)``), whichever coordinator in the stack presented it. Anything stacked on
    /// top of it goes too.
    public func dismissPresented() {
        activeNavigator?.dismissPresentation()
    }

    /// Dismisses every sheet and cover in this coordinator's presentation tree: everything presented from the stack at
    /// its bottom, however deep. Sheets opened from *another tab* belong to that tab; use ``TabNavigator/select(_:reset:)``.
    public func dismissAll() {
        activeNavigator?.dismissAll()
    }

    // MARK: Presentations

    /// What this coordinator's stack is presenting, while it's on screen. Write to it to move the sheet or lock swipe-to-dismiss:
    ///
    /// ```swift
    /// presented?.selectedDetent = .large
    /// presented?.isInteractiveDismissDisabled = hasUnsavedChanges
    /// ```
    public var presented: Presentation? {
        activeNavigator?.presentation
    }

    /// The sheet or cover this coordinator's stack lives in: set for a presented flow, and for flows pushed inside it.
    /// `nil` when the stack isn't presented (an app root or a tab).
    public var enclosingPresentation: Presentation? {
        activeNavigator?.containingPresentation
    }

    /// The navigator, while this flow is still running. A finished flow kept alive by a `Task` gets `nil`,
    /// so a late `pop()` or `dismissPresented()` can't act on screens that now belong to its parent.
    var activeNavigator: Navigator? {
        isFinished ? nil : navigator
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

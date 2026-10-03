import SwiftUI
import os

let waypointLog = Logger(subsystem: "Waypoint", category: "navigation")

/// The navigation state of one `NavigationStack`: a root screen, the pushed screens, and at most one sheet or cover.
///
/// You create a navigator for each independent stack (the app's root, each tab) and show it with ``NavigationHost``.
/// Coordinators do the navigating; the navigator is the state they act on.
///
/// ```swift
/// let navigator = Navigator(root: LibraryCoordinator())
/// NavigationHost(navigator)
/// ```
///
/// ## Ownership
/// Navigators form a tree: each presentation holds a child navigator, which can present again. Strong references only
/// point *down* the tree, from a navigator to its screens and from the screens to the coordinators and view models that
/// built them. Coordinators hold their navigator weakly. So when a screen leaves (pop, swipe-back, dismissal, root switch)
/// everything it owned is freed. Keep the root navigator in something long-lived: an app coordinator, a
/// ``TabNavigator``, or let ``NavigationHost/init(root:)`` keep it for you.
@MainActor
@Observable
public final class Navigator {
    private(set) var root: StackEntry
    private(set) var path: [StackEntry] = []
    /// The sheet or cover this navigator is showing, if any.
    public private(set) var presentation: Presentation?
    /// The alert or confirmation dialog on screen, if any.
    private(set) var alertRequest: AlertRequest?
    /// The navigator that presented this one, if any.
    @ObservationIgnored private(set) weak var presenter: Navigator?
    let embedsInNavigationStack: Bool

    /// A presentation waiting for the current one to finish animating out.
    @ObservationIgnored private var queuedPresentation: Presentation?
    /// A presentation that has been dismissed and is still animating out.
    @ObservationIgnored private var dismissingPresentation: Presentation?
    /// An alert waiting for a dismissal animation to finish. UIKit refuses to present one mid-dismissal.
    @ObservationIgnored private var queuedAlert: AlertRequest?
    @ObservationIgnored private(set) var isTornDown = false

    /// A navigator whose root screen is `coordinator`'s ``Routing/initialRoute``. The navigator owns the coordinator from here on.
    public convenience init<C: Routing>(root coordinator: C) {
        self.init(root: coordinator, embedsInNavigationStack: true)
    }

    convenience init<C: Routing>(root coordinator: C, embedsInNavigationStack: Bool) {
        let entry = coordinator.makeEntry(for: coordinator.initialRoute, transition: .automatic)
        self.init(rootEntry: entry, embedsInNavigationStack: embedsInNavigationStack)
        coordinator.attach(to: self, anchor: entry)
    }

    init(rootEntry: StackEntry, embedsInNavigationStack: Bool, isTracked: Bool = true) {
        self.root = rootEntry
        self.embedsInNavigationStack = embedsInNavigationStack
        if isTracked { LifetimeTracker.track(self, kind: .navigator) }
    }

    /// An empty, inert navigator, handed out in place of ones that were torn down.
    static let placeholder: Navigator = {
        let navigator = Navigator(
            rootEntry: StackEntry(route: AnyHashable(0), content: AnyView(EmptyView()), owner: nil, isTracked: false),
            embedsInNavigationStack: true,
            isTracked: false
        )
        navigator.tearDown()
        return navigator
    }()

    // MARK: - Reading

    /// The coordinator behind the root screen, as `C`. Use it to reach a tab's coordinator for a deep link:
    /// `tabs[.feed].rootCoordinator(as: FeedCoordinator.self)?.showPhoto(id)`.
    public func rootCoordinator<C: Coordinator>(as type: C.Type) -> C? {
        root.owner as? C
    }

    /// The route on top of the stack, as `Route`, or `nil` when the top screen has another route type. Mostly for tests.
    public func topRoute<Route: Hashable>(as type: Route.Type) -> Route? {
        top.route(as: type)
    }

    /// The number of pushed screens, not counting the root.
    public var depth: Int { path.count }

    /// Every entry, from the root to the top.
    var entries: [StackEntry] { [root] + path }

    var top: StackEntry { path.last ?? root }

    /// The deepest navigator that is currently presented, or `self` when nothing is presented.
    var topmost: Navigator { presentation?.navigator.topmost ?? self }

    /// The presentation showing this navigator, or `nil` when it isn't presented.
    var containingPresentation: Presentation? {
        guard let presentation = presenter?.presentation, presentation.navigator === self else { return nil }
        return presentation
    }

    // MARK: - Stack

    func push(_ entry: StackEntry) {
        push(contentsOf: [entry])
    }

    func push(contentsOf newEntries: [StackEntry]) {
        guard !isTornDown else { return }
        assert(embedsInNavigationStack, "Waypoint: pushing onto a navigator with no NavigationStack. Present with `embedsInNavigationStack: true`.")
        #if DEBUG
        if presentation != nil {
            waypointLog.warning("Waypoint: pushed \(newEntries.map { "\($0.route.base)" }, privacy: .public) behind a presented sheet or cover. If a presented screen pushed this, present a flow (presentFlow) instead, so it has its own stack.")
        }
        #endif
        path.append(contentsOf: newEntries)
    }

    /// Pops `count` screens (fewer if the stack isn't that deep).
    public func pop(count: Int = 1) {
        guard count > 0, !path.isEmpty else { return }
        setPath(Array(path.dropLast(count)))
    }

    /// Pops every pushed screen.
    public func popToRoot() {
        setPath([])
    }

    /// Dismisses every presentation and pops to the root: a clean slate before a deep link.
    public func reset() {
        dismissPresentation()
        popToRoot()
    }

    /// Pops everything above `entry`, which stays on screen. Does nothing when `entry` isn't in this stack.
    func pop(to entry: StackEntry) {
        if entry === root { return popToRoot() }
        guard let index = path.firstIndex(of: entry) else { return }
        setPath(Array(path.prefix(through: index)))
    }

    /// Replaces the pushed screens. Entries that drop out are torn down, top first.
    /// SwiftUI's path binding funnels through here too, so swipe-back and the long-press back menu are handled the same way.
    func setPath(_ newPath: [StackEntry]) {
        guard newPath != path else { return }
        let removed: [StackEntry]
        if newPath.count < path.count, zip(newPath, path).allSatisfy(===) {
            // A pop, which is what every swipe-back and back button produces.
            removed = Array(path[newPath.count...])
        } else {
            let kept = Set(newPath.map(ObjectIdentifier.init))
            removed = path.filter { !kept.contains(ObjectIdentifier($0)) }
        }
        path = newPath
        // Flows whose first screen is leaving end now, and so do the sheets they presented. Those sheets join the same
        // closing group, so an await on the flow resumes only after they've animated out too.
        let endingFlows = removed.compactMap { entry in entry.owner.flatMap { $0.anchor === entry ? $0 : nil } }
        let endingPresentations = [presentation, queuedPresentation].compactMap { $0 }.filter { candidate in
            endingFlows.contains { $0 === candidate.presentedBy }
        }
        let closingGroup = ClosingGroup(screens: removed.map(\.screen) + endingPresentations.flatMap { $0.navigator.subtreeScreens() })
        for ending in endingPresentations {
            if ending === queuedPresentation {
                queuedPresentation = nil
                ending.navigator.tearDown(closingWith: closingGroup)
            } else {
                endPresentation(ending, closingWith: closingGroup)
            }
        }
        removed.reversed().forEach { $0.markRemoved(closingWith: closingGroup) }
    }

    /// SwiftUI's side of `setPath`. The tokens map back to this stack's entries. Tokens of entries that are no longer here are ignored.
    func setPath(tokens: [EntryToken]) {
        let entriesByScreen = Dictionary(uniqueKeysWithValues: path.map { (ObjectIdentifier($0.screen), $0) })
        setPath(tokens.compactMap { entriesByScreen[ObjectIdentifier($0.screen)] })
    }

    /// Removes `entry`, plus everything pushed above it. If `entry` is this navigator's root, the navigator is dismissed instead.
    func close(_ entry: StackEntry) {
        if entry === root {
            dismiss()
        } else if let index = path.firstIndex(of: entry) {
            setPath(Array(path.prefix(upTo: index)))
        }
    }

    // MARK: - Presentation

    /// Presents `navigator` modally. If something is already presented, it's dismissed first,
    /// and the new presentation follows once the old one has animated out. SwiftUI drops a presentation started mid-dismissal.
    func present(_ navigator: Navigator, style: PresentationStyle, transition: ScreenTransition, by coordinator: Coordinator? = nil) {
        guard !isTornDown else { return navigator.tearDown() }
        let newPresentation = Presentation(navigator: navigator, style: style, transition: transition)
        newPresentation.presentedBy = coordinator
        navigator.presenter = self
        if presentation == nil && dismissingPresentation == nil {
            presentation = newPresentation
            return
        }
        cancelQueuedPresentation()
        queuedPresentation = newPresentation
        if let presentation {
            endPresentation(presentation)
        }
    }

    /// Dismisses whatever this navigator presents, including any presentations stacked on top of it.
    /// A presentation still waiting for its turn is cancelled too.
    public func dismissPresentation() {
        cancelQueuedPresentation()
        guard let presentation else { return }
        endPresentation(presentation)
    }

    /// Dismisses this navigator, when it's presented, or cancels it while it's still waiting to be presented.
    func dismiss() {
        guard let presenter else { return }
        if presenter.presentation?.navigator === self {
            presenter.dismissPresentation()
        } else if presenter.queuedPresentation?.navigator === self {
            presenter.cancelQueuedPresentation()
        }
    }

    /// Dismisses whatever `coordinator` presented from this navigator, once the coordinator has finished.
    func dismissPresentations(by coordinator: Coordinator) {
        if queuedPresentation?.presentedBy === coordinator {
            cancelQueuedPresentation()
        }
        if let presentation, presentation.presentedBy === coordinator {
            endPresentation(presentation)
        }
    }

    private func cancelQueuedPresentation() {
        guard let queued = queuedPresentation else { return }
        queuedPresentation = nil
        queued.navigator.tearDown()
    }

    /// Dismisses every presentation, from the root navigator of this presentation tree down.
    public func dismissAll() {
        var root = self
        while let presenter = root.presenter { root = presenter }
        root.dismissPresentation()
    }

    /// Called from the presentation binding's setter, when the user swipes a sheet away.
    func presentationDismissedBySystem(_ dismissed: Presentation) {
        guard presentation === dismissed else { return }
        endPresentation(dismissed)
    }

    /// Called from `onDismiss`, after the dismissal animation has finished.
    func presentationDidFinishDismissing() {
        dismissingPresentation = nil
        showQueuedPresentation()
        showQueuedAlert()
    }

    private func endPresentation(_ ending: Presentation, closingWith closingGroup: ClosingGroup? = nil) {
        presentation = nil
        if ending.hasAppeared {
            dismissingPresentation = ending
        }
        ending.navigator.tearDown(closingWith: closingGroup ?? ClosingGroup(screens: ending.navigator.subtreeScreens()))
        if dismissingPresentation == nil {
            showQueuedPresentation()
            showQueuedAlert()
        }
    }

    private func showQueuedPresentation() {
        guard presentation == nil, let queued = queuedPresentation else { return }
        queuedPresentation = nil
        presentation = queued
    }

    // MARK: - Alerts

    /// Shows `request`. An alert that is already up (or waiting) resolves with `nil` and is replaced.
    /// While a presentation is animating out, the alert waits for it, because UIKit refuses to present mid-dismissal.
    func show(_ request: AlertRequest) {
        guard !isTornDown else { return request.finish(choosing: nil) }
        queuedAlert?.finish(choosing: nil)
        queuedAlert = nil
        if dismissingPresentation != nil {
            queuedAlert = request
            return
        }
        alertRequest?.finish(choosing: nil)
        alertRequest = request
    }

    private func showQueuedAlert() {
        guard let alert = queuedAlert else { return }
        queuedAlert = nil
        // A presentation shown from the queue is now on top, so the alert goes there, once that sheet is actually up.
        let target = topmost
        if let presentation = target.containingPresentation, !presentation.hasAppeared {
            presentation.alertOnAppear = alert
        } else {
            target.show(alert)
        }
    }

    func finishAlert(_ request: AlertRequest, choosing index: Int?) {
        if alertRequest === request { alertRequest = nil }
        if let index {
            request.finish(choosing: index)
        } else {
            // SwiftUI may write `isPresented = false` before it runs the tapped button's action.
            // Resolving "no choice" a turn later lets the button win.
            Task { @MainActor in request.finish(choosing: nil) }
        }
    }

    // MARK: - Teardown

    /// Ends everything in this navigator's tree: pending awaits return `nil`, alerts resolve, and every coordinator's
    /// ``Coordinator/didFinish()`` runs. Call it when you discard a tree yourself (a root switch); the objects are freed
    /// when your last reference goes. Dismissals and pops do this for you.
    public func tearDown() {
        tearDown(closingWith: ClosingGroup(screens: subtreeScreens()))
    }

    /// `closingGroup` holds every screen leaving with this tree. An await on any entry in the tree resumes only once they've all left.
    fileprivate func tearDown(closingWith closingGroup: ClosingGroup) {
        guard !isTornDown else { return }
        isTornDown = true
        for alert in [alertRequest, queuedAlert].compactMap(\.self) { alert.finish(choosing: nil) }
        alertRequest = nil
        queuedAlert = nil
        presentation?.navigator.tearDown(closingWith: closingGroup)
        queuedPresentation?.navigator.tearDown(closingWith: closingGroup)
        queuedPresentation = nil
        path.reversed().forEach { $0.markRemoved(closingWith: closingGroup) }
        root.markRemoved(closingWith: closingGroup)
    }

    fileprivate func subtreeScreens() -> [ScreenContent] {
        entries.map(\.screen)
            + (presentation?.navigator.subtreeScreens() ?? [])
            + (queuedPresentation?.navigator.subtreeScreens() ?? [])
    }
}

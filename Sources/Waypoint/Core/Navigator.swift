import SwiftUI

/// The state behind one `NavigationStack`: a root screen, the pushed screens, and at most one modal presentation.
///
/// Navigators form a tree. Each presentation holds a child navigator, which can present again.
/// Strong references only point down this tree, from the navigator to its entries and from the entries to the coordinators and view models that built them.
/// Coordinators keep only a weak reference back to their navigator. So when a screen leaves the stack, by a pop, a swipe-back, a dismissal or a root switch, everything it owned is released.
@MainActor
@Observable
public final class Navigator {
    public private(set) var root: StackEntry
    public private(set) var path: [StackEntry] = []
    public private(set) var presentation: Presentation?
    /// The alert or confirmation dialog on screen, if any. See ``Coordinator/alert(_:message:style:actions:)``.
    public private(set) var alertRequest: AlertRequest?
    /// The navigator that presented this one, if any.
    @ObservationIgnored public private(set) weak var presenter: Navigator?
    public let embedsInNavigationStack: Bool

    /// A presentation waiting for the current one to finish animating out.
    @ObservationIgnored private var queuedPresentation: Presentation?
    /// A presentation that has been dismissed and is still animating out.
    @ObservationIgnored private var dismissingPresentation: Presentation?
    @ObservationIgnored private(set) var isTornDown = false

    /// A navigator whose root is a plain view, with no coordinator behind it.
    public convenience init(root: some View, embedsInNavigationStack: Bool = true) {
        self.init(rootEntry: StackEntry(route: AnyHashable(RootView()), content: AnyView(root), owner: nil), embedsInNavigationStack: embedsInNavigationStack)
    }

    /// A navigator whose root is the coordinator's ``Routing/initialRoute``.
    /// The navigator owns the coordinator from here on.
    public convenience init<C: Routing>(root coordinator: C, embedsInNavigationStack: Bool = true) {
        let entry = coordinator.makeEntry(for: coordinator.initialRoute, transition: .automatic)
        self.init(rootEntry: entry, embedsInNavigationStack: embedsInNavigationStack)
        coordinator.attach(to: self, anchor: entry)
    }

    init(rootEntry: StackEntry, embedsInNavigationStack: Bool) {
        self.root = rootEntry
        self.embedsInNavigationStack = embedsInNavigationStack
        LifetimeTracker.track(self, kind: .navigator)
    }

    // MARK: - Stack

    /// Every entry, from the root to the top.
    public var entries: [StackEntry] { [root] + path }

    public var top: StackEntry { path.last ?? root }

    /// The deepest navigator that is currently presented, or `self` when nothing is presented.
    public var topmost: Navigator { presentation?.navigator.topmost ?? self }

    /// The presentation showing this navigator, or `nil` when it isn't presented.
    /// Use it to change the sheet's detent, or to lock swipe-to-dismiss, from inside.
    public var containingPresentation: Presentation? {
        guard let presentation = presenter?.presentation, presentation.navigator === self else { return nil }
        return presentation
    }

    func push(_ entry: StackEntry) {
        push(contentsOf: [entry])
    }

    func push(contentsOf newEntries: [StackEntry]) {
        guard !isTornDown else { return }
        assert(embedsInNavigationStack, "Waypoint: pushing onto a navigator with no NavigationStack. Present with `embedsInNavigationStack: true`.")
        path.append(contentsOf: newEntries)
    }

    public func pop(count: Int = 1) {
        guard count > 0, !path.isEmpty else { return }
        setPath(Array(path.dropLast(count)))
    }

    public func popToRoot() {
        setPath([])
    }

    /// Pops everything above `entry`, which stays on screen. Does nothing when `entry` isn't in this stack.
    public func pop(to entry: StackEntry) {
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
        removed.reversed().forEach { $0.markRemoved() }
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
    func present(_ navigator: Navigator, style: PresentationStyle, transition: ScreenTransition) {
        guard !isTornDown else { return navigator.tearDown() }
        let newPresentation = Presentation(navigator: navigator, style: style, transition: transition)
        navigator.presenter = self
        if presentation == nil && dismissingPresentation == nil {
            presentation = newPresentation
            return
        }
        queuedPresentation?.navigator.tearDown()
        queuedPresentation = newPresentation
        if presentation != nil {
            dismissPresentation()
        }
    }

    /// Dismisses whatever this navigator presents, including any presentations stacked on top of it.
    public func dismissPresentation() {
        guard let presentation else { return }
        endPresentation(presentation)
    }

    /// Dismisses this navigator, when it's presented.
    public func dismiss() {
        guard let presenter, presenter.presentation?.navigator === self else { return }
        presenter.dismissPresentation()
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
    }

    private func endPresentation(_ ending: Presentation) {
        presentation = nil
        if ending.hasAppeared {
            dismissingPresentation = ending
        }
        ending.navigator.tearDown()
        if dismissingPresentation == nil {
            showQueuedPresentation()
        }
    }

    private func showQueuedPresentation() {
        guard presentation == nil, let queued = queuedPresentation else { return }
        queuedPresentation = nil
        presentation = queued
    }

    // MARK: - Alerts

    /// Shows `request`. An alert that is already up resolves with `nil` and is replaced.
    func show(_ request: AlertRequest) {
        guard !isTornDown else { return request.finish(choosing: nil) }
        alertRequest?.finish(choosing: nil)
        alertRequest = request
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

    /// Marks every entry removed, top first. That resolves pending results with `nil` and finishes coordinators.
    /// The objects themselves are freed when the last reference to this navigator goes.
    public func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        alertRequest?.finish(choosing: nil)
        alertRequest = nil
        presentation?.navigator.tearDown()
        queuedPresentation?.navigator.tearDown()
        queuedPresentation = nil
        path.reversed().forEach { $0.markRemoved() }
        root.markRemoved()
    }
}

/// The route of a navigator whose root is a plain view.
struct RootView: Hashable {}

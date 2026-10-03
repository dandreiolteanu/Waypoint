import SwiftUI

/// One screen in a navigator: the root, a pushed screen, or the root of a presented navigator.
///
/// An entry owns its coordinator through ``owner``, and its view through ``screen``.
/// Removing the entry from navigation state is what releases them.
@MainActor
final class StackEntry: Hashable, Identifiable {
    /// The route value the screen was built from, type-erased so one stack can mix routes from several coordinators.
    let route: AnyHashable
    /// The coordinator that built the screen. It's retained here, so a coordinator lives exactly as long as one of its screens.
    /// It's released when the entry is removed, so a navigator SwiftUI holds on to after a teardown no longer keeps the coordinator alive.
    private(set) var owner: Coordinator?
    let transition: ScreenTransition
    let screen: ScreenContent
    /// What SwiftUI's path holds instead of the entry itself, so SwiftUI's retained copy of a popped path keeps nothing alive.
    let token: EntryToken
    private var removalHandlers: [() -> Void] = []
    private let closing = ClosingWatch()
    private(set) var isRemoved = false

    init(route: AnyHashable, content: AnyView, owner: Coordinator?, transition: ScreenTransition = .automatic, isTracked: Bool = true) {
        self.route = route
        self.owner = owner
        self.transition = transition
        self.screen = ScreenContent(view: content)
        self.token = EntryToken(screen: screen, transition: transition)
        if isTracked { LifetimeTracker.track(self, kind: .entry) }
    }

    /// The route as a concrete type, or `nil` when the screen came from a different route type.
    func route<Route: Hashable>(as type: Route.Type) -> Route? {
        route.base as? Route
    }

    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    nonisolated static func == (lhs: StackEntry, rhs: StackEntry) -> Bool { lhs === rhs }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    // MARK: - Removal

    /// Runs `handler` as soon as the entry leaves navigation state.
    func onRemove(_ handler: @escaping () -> Void) {
        guard !isRemoved else { return handler() }
        removalHandlers.append(handler)
    }

    /// Runs `handler` once the entry has been removed *and* every screen that left with it has finished leaving the screen.
    /// That's after the pop or dismissal animation, or right away if none of them was visible.
    func onClosed(_ handler: @escaping () -> Void) {
        closing.add(handler)
    }

    /// - Parameter closingGroup: Every screen removed in the same change (a multi-screen pop, a dismissed tree).
    ///   The entry counts as closed once all of them have closed, because the one still animating is usually another entry's.
    func markRemoved(closingWith closingGroup: ClosingGroup? = nil) {
        guard !isRemoved else { return }
        isRemoved = true
        let handlers = removalHandlers
        removalHandlers.removeAll()
        handlers.forEach { $0() }
        let group = closingGroup ?? ClosingGroup(screens: [screen])
        screen.remove()
        group.add(closing)
        if let owner, owner.anchor === self {
            owner.finishLifecycle()
        }
        owner = nil
    }

}

/// Every screen removed in one change, and the entries waiting for all of them to leave the screen.
///
/// The screens still animating retain the group (through their closed handlers), and the group retains the entries'
/// watches. If SwiftUI drops those screens without a disappearance, the group is freed with them, and so is any pending
/// result, whose deinit then resumes the await. One group per change keeps a large pop linear.
@MainActor
final class ClosingGroup {
    private var remaining: Int
    private var watches: [ClosingWatch] = []
    private var isClosed: Bool

    /// Creates the group, and starts listening to `screens`. Create it before removing any of them.
    init(screens: [ScreenContent]) {
        remaining = screens.count
        isClosed = screens.isEmpty
        for screen in screens {
            screen.onClosed { [self] in
                remaining -= 1
                if remaining == 0 { close() }
            }
        }
    }

    func add(_ watch: ClosingWatch) {
        if isClosed { watch.fire() } else { watches.append(watch) }
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        let watches = self.watches
        self.watches.removeAll()
        watches.forEach { $0.fire() }
    }
}

/// Handlers waiting for an entry, and the screens removed with it, to finish leaving the screen.
@MainActor
final class ClosingWatch {
    private var handlers: [() -> Void] = []
    private var isClosed = false

    func add(_ handler: @escaping () -> Void) {
        guard !isClosed else { return handler() }
        handlers.append(handler)
    }

    func fire() {
        guard !isClosed else { return }
        isClosed = true
        let handlers = self.handlers
        self.handlers.removeAll()
        handlers.forEach { $0() }
    }
}

/// The SwiftUI-facing half of an entry: the built view, plus whether it's currently on screen.
///
/// `NavigationStack` keeps the destination it last popped (and its path element) alive until the next navigation.
/// So the view lives here, and it's dropped once the removed screen has disappeared. That forces SwiftUI to let go of the view model too.
@MainActor
@Observable
final class ScreenContent {
    private(set) var view: AnyView?
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var isRemoved = false
    @ObservationIgnored private(set) var isClosed = false
    @ObservationIgnored private var closedHandlers: [() -> Void] = []

    init(view: AnyView) {
        self.view = view
    }

    func onClosed(_ handler: @escaping () -> Void) {
        guard !isClosed else { return handler() }
        closedHandlers.append(handler)
    }

    func didAppear() {
        guard !isRemoved else { return }
        isVisible = true
    }

    func didDisappear() {
        isVisible = false
        if isRemoved { close() }
    }

    func remove() {
        isRemoved = true
        if isVisible {
            closeEventually()
        } else {
            close()
        }
    }

    /// The fallback for a removed screen SwiftUI never reports as gone (it keeps some removed trees for a while).
    /// Without it, an await on the screen could wait indefinitely. Real pop and dismiss animations end well within this.
    private func closeEventually() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.closeTimeout)
            self?.close()
        }
    }

    static var closeTimeout: Duration = .seconds(2)

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        view = nil
        let handlers = closedHandlers
        closedHandlers.removeAll()
        handlers.forEach { $0() }
    }
}

/// An element of SwiftUI's navigation path. It's compared by its screen's identity.
/// That's safe because the token retains the screen, so the address can't be reused while SwiftUI still holds the token.
struct EntryToken: Hashable {
    let screen: ScreenContent
    let transition: ScreenTransition

    nonisolated static func == (lhs: EntryToken, rhs: EntryToken) -> Bool { lhs.screen === rhs.screen }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(screen)) }
}

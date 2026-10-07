import Foundation

// Screens and flows that hand a value back to whoever opened them. See the "Passing Data" article.
//
// The opener awaits the value; the screen (or flow) gets a `Callback` to call. Calling it closes the screen and the await
// returns the value. If the screen goes away any other way (swipe-back, swipe-down, a parent dismissing, the tree being
// torn down) the await returns `nil`. Either way it resumes exactly once, after the screen has fully left the screen.

extension Routing {
    /// Pushes the route built by `makeRoute`, and waits for the screen to call back with a value.
    ///
    /// ```swift
    /// func editName() async {
    ///     guard let name = await push({ .editName(current: user.name, onSave: $0) }) else { return }  // nil: user went back
    ///     user.name = name
    /// }
    /// ```
    ///
    /// Calling the callback pops the screen. The await returns once it's off screen.
    public func push<Value: Sendable>(
        transition: ScreenTransition = .automatic,
        _ makeRoute: (Callback<Value>) -> Route
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            let entry = makeEntry(for: makeRoute(callback), transition: navigator.resolved(transition))
            navigator.push(entry)
            return (entry, navigator)
        }
    }

    /// Presents the route built by `makeRoute`, and waits for the screen to call back with a value.
    ///
    /// ```swift
    /// let color = await present(as: .sheet(detents: [.medium])) { .colorPicker(onPick: $0) }  // nil: swiped away
    /// ```
    ///
    /// Calling the callback dismisses the screen. The await returns once it's off screen.
    public func present<Value: Sendable>(
        as style: PresentationStyle = .sheet,
        transition: ScreenTransition = .automatic,
        _ makeRoute: (Callback<Value>) -> Route
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            let entry = makeEntry(for: makeRoute(callback), transition: .automatic)
            let presented = Navigator(rootEntry: entry, embedsInNavigationStack: style.embedsInNavigationStack)
            navigator.present(presented, style: style, transition: transition, by: self)
            return (entry, presented)
        }
    }
}

extension Coordinator {
    /// Pushes the child flow built by `makeChild`, and waits for it to call back with a value.
    ///
    /// ```swift
    /// let answers = await pushFlow { SurveyCoordinator(onFinish: $0) }  // nil: user backed out of the flow
    /// ```
    ///
    /// Calling the callback pops every screen of the flow. The await returns once they're off screen.
    public func pushFlow<Value: Sendable, Child: Routing>(
        transition: ScreenTransition = .automatic,
        _ makeChild: (Callback<Value>) -> Child
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            return (attachAndPush(makeChild(callback), transition: transition, on: navigator), navigator)
        }
    }

    /// Pushes a child flow whose concrete type isn't known here, for example one built by a dependency container,
    /// and waits for it to call back with a value.
    ///
    /// ```swift
    /// let answers = await pushFlow { container.survey(onFinish: $0) }  // returns any Routing
    /// ```
    public func pushFlow<Value: Sendable>(
        transition: ScreenTransition = .automatic,
        _ makeChild: (Callback<Value>) -> any Routing
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            return (attachAndPush(makeChild(callback), transition: transition, on: navigator), navigator)
        }
    }

    /// Presents the child flow built by `makeChild`, and waits for it to call back with a value.
    ///
    /// ```swift
    /// guard let user = await presentFlow(as: .fullScreenCover, { OnboardingCoordinator(onComplete: $0) }) else { return }
    /// ```
    ///
    /// Calling the callback dismisses the flow. The await returns once it's off screen.
    public func presentFlow<Value: Sendable, Child: Routing>(
        as style: PresentationStyle = .sheet,
        transition: ScreenTransition = .automatic,
        _ makeChild: (Callback<Value>) -> Child
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            let presented = Navigator(root: makeChild(callback), embedsInNavigationStack: style.embedsInNavigationStack)
            navigator.present(presented, style: style, transition: transition, by: self)
            return (presented.root, presented)
        }
    }

    /// Presents a child flow whose concrete type isn't known here, for example one built by a dependency container,
    /// and waits for it to call back with a value.
    ///
    /// ```swift
    /// let result = await presentFlow(as: .sheet) { container.settings(onFinish: $0) }  // returns any Routing
    /// ```
    public func presentFlow<Value: Sendable>(
        as style: PresentationStyle = .sheet,
        transition: ScreenTransition = .automatic,
        _ makeChild: (Callback<Value>) -> any Routing
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            let presented = Navigator(root: makeChild(callback), embedsInNavigationStack: style.embedsInNavigationStack)
            navigator.present(presented, style: style, transition: transition, by: self)
            return (presented.root, presented)
        }
    }

    /// Runs `open`, which puts a screen up and returns its entry plus the navigator it lives in.
    /// The await resumes once that screen has fully left the screen (after its pop or dismissal animation),
    /// so whatever the caller does next (present, push, switch root) never collides with a transition still running.
    func awaitResult<Value: Sendable>(
        _ open: (Callback<Value>) -> (entry: StackEntry, navigator: Navigator)?
    ) async -> Value? {
        await withCheckedContinuation { continuation in
            // Only the screen's route and entry keep `pending` alive, never this suspended frame.
            // So if they're freed without being closed (a whole tree dropped), `pending`'s deinit still resumes the await.
            let pending = PendingResult(continuation)
            let location = EntryLocation()
            let callback = Callback<Value> { value in
                guard let entry = location.entry, !entry.isRemoved, pending.store(value) else { return }
                location.close()
            }
            guard let (entry, navigator) = open(callback) else {
                pending.resume()
                return
            }
            location.entry = entry
            location.navigator = navigator
            entry.onClosed { pending.resume() }
        }
    }
}

/// A weak pointer to where a result-producing screen lives, so its callback can close it.
@MainActor
private final class EntryLocation {
    weak var entry: StackEntry?
    weak var navigator: Navigator?

    func close() {
        guard let entry, let navigator else { return }
        navigator.close(entry)
    }
}

/// Holds an await's continuation and the value it will return, and resumes it exactly once.
/// It resumes on ``resume()``, or on deinit if nothing resumed it first.
final class PendingResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var value: Value?
    private var hasValue = false

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    /// Records the value to return. Only the first value is kept, and this returns `false` for any later one.
    func store(_ value: Value) -> Bool {
        lock.withLock {
            guard !hasValue, continuation != nil else { return false }
            self.value = value
            hasValue = true
            return true
        }
    }

    /// Resumes the await with the stored value, or with `nil` if nothing was stored.
    func resume() {
        let (continuation, value) = lock.withLock {
            defer { self.continuation = nil }
            return (self.continuation, self.value)
        }
        continuation?.resume(returning: value)
    }

    deinit {
        continuation?.resume(returning: value)
    }
}

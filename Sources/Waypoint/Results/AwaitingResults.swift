import Foundation

// Screens and flows that hand a value back to whoever opened them.
//
// The opener awaits the value. The screen gets a `Callback` to call. When it does, the screen is closed and the await
// returns the value. If the screen goes away any other way (swipe-back, swipe-down, a parent dismissing, the tree being
// torn down), the await returns `nil`. Each await resumes exactly once.
//
//     func editName() async {
//         guard let name = await push({ .editName(current: user.name, onSave: $0) }) else { return }
//         user.name = name
//     }

extension Routing {
    /// Pushes the route built by `makeRoute` and waits for the screen to call its callback.
    /// Returns `nil` if the screen is popped first.
    public func push<Value: Sendable>(
        transition: ScreenTransition = .automatic,
        _ makeRoute: (Callback<Value>) -> Route
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            let entry = makeEntry(for: makeRoute(callback), transition: transition)
            navigator.push(entry)
            return (entry, navigator)
        }
    }

    /// Presents the route built by `makeRoute` and waits for the screen to call its callback.
    /// Returns `nil` if the presentation is dismissed first.
    public func present<Value: Sendable>(
        as style: PresentationStyle = .sheet,
        transition: ScreenTransition = .automatic,
        _ makeRoute: (Callback<Value>) -> Route
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            let entry = makeEntry(for: makeRoute(callback), transition: .automatic)
            let presented = Navigator(rootEntry: entry, embedsInNavigationStack: style.embedsInNavigationStack)
            navigator.present(presented, style: style, transition: transition)
            return (entry, presented)
        }
    }
}

extension Coordinator {
    /// Pushes the child flow built by `makeChild` and waits for it to call its callback.
    /// Returns `nil` if the flow is popped first.
    public func push<Value: Sendable, Child: Routing>(
        transition: ScreenTransition = .automatic,
        child makeChild: (Callback<Value>) -> Child
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            let child = makeChild(callback)
            let entry = child.makeEntry(for: child.initialRoute, transition: transition)
            child.attach(to: navigator, anchor: entry)
            navigator.push(entry)
            return (entry, navigator)
        }
    }

    /// Presents the child flow built by `makeChild` and waits for it to call its callback.
    /// Returns `nil` if the flow is dismissed first.
    public func present<Value: Sendable, Child: Routing>(
        as style: PresentationStyle = .sheet,
        transition: ScreenTransition = .automatic,
        child makeChild: (Callback<Value>) -> Child
    ) async -> Value? {
        await awaitResult { callback in
            guard let navigator = requireNavigator() else { return nil }
            let presented = Navigator(root: makeChild(callback), embedsInNavigationStack: style.embedsInNavigationStack)
            navigator.present(presented, style: style, transition: transition)
            return (presented.root, presented)
        }
    }

    /// Runs `open`, which puts a screen on screen and returns its entry plus the navigator it lives in.
    /// Then waits for the screen's callback, or for the entry's removal.
    func awaitResult<Value: Sendable>(
        _ open: (Callback<Value>) -> (entry: StackEntry, navigator: Navigator)?
    ) async -> Value? {
        await withCheckedContinuation { continuation in
            // Only the screen's route and entry keep `pending` alive, never this suspended frame.
            // So if they're freed without being removed (a whole tree dropped), `pending`'s deinit still resumes the await.
            let pending = PendingResult(continuation)
            let location = EntryLocation()
            let callback = Callback<Value> { value in
                guard pending.resolve(value) else { return }
                location.close()
            }
            guard let (entry, navigator) = open(callback) else {
                pending.resolve(nil)
                return
            }
            location.entry = entry
            location.navigator = navigator
            entry.onRemove { pending.resolve(nil) }
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

/// Holds an await's continuation and resumes it exactly once. Resolving with a value, resolving with `nil`, and deinit can race; only the first wins.
final class PendingResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?

    init(_ continuation: CheckedContinuation<Value?, Never>) {
        self.continuation = continuation
    }

    /// Returns `true` if this call resumed the await, and `false` if it had already been resumed.
    @discardableResult
    func resolve(_ value: Value?) -> Bool {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
        return continuation != nil
    }

    deinit {
        continuation?.resume(returning: nil)
    }
}

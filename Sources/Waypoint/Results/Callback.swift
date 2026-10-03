/// A closure that can travel inside a `Hashable` route: how a screen sends a value back.
///
/// Routes must be `Hashable` and closures aren't, so a route that needs to report back carries a `Callback`.
/// Two callbacks are equal only if they're the same instance.
///
/// ```swift
/// enum Route: Hashable {
///     case editName(current: String, onSave: Callback<String>)
///     case confirmDelete(onConfirm: Callback<Void>)
/// }
///
/// // In the coordinator: the awaiting APIs make the callback for you.
/// let name = await push { .editName(current: user.name, onSave: $0) }
///
/// // In the screen: call it like a function.
/// onSave(newName)
/// onConfirm()   // Callback<Void>
/// ```
///
/// You can also build one yourself, for fire-and-forget reporting: `Callback { name in self.rename(to: name) }`.
public struct Callback<Value>: Hashable {
    private let id = UniqueID()
    private let action: @MainActor (Value) -> Void

    /// Wraps `action`.
    public init(_ action: @escaping @MainActor (Value) -> Void) {
        self.action = action
    }

    /// Sends `value` back.
    @MainActor
    public func callAsFunction(_ value: Value) {
        action(value)
    }

    /// Two callbacks are equal only if they're the same instance.
    public static func == (lhs: Callback, rhs: Callback) -> Bool { lhs.id == rhs.id }

    /// Hashes the callback's identity.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Callback where Value == Void {
    /// Reports back, for a callback that carries no value.
    @MainActor
    public func callAsFunction() {
        action(())
    }
}

/// An identity token that is cheap to compare and hash.
private final class UniqueID: Hashable, Sendable {
    static func == (lhs: UniqueID, rhs: UniqueID) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

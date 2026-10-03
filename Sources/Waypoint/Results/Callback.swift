/// A closure that can sit in a `Hashable` route.
///
/// Routes must be `Hashable` and closures aren't, so wrap a "send a value back" closure in `Callback`.
/// Two callbacks are equal only if they are the same instance, so routes carrying different callbacks never compare equal.
///
/// ```swift
/// enum Route: Hashable {
///     case editName(current: String, onSave: Callback<String>)
/// }
/// ```
public struct Callback<Value>: Hashable {
    private let id = UniqueID()
    private let action: @MainActor (Value) -> Void

    public init(_ action: @escaping @MainActor (Value) -> Void) {
        self.action = action
    }

    @MainActor
    public func callAsFunction(_ value: Value) {
        action(value)
    }

    public static func == (lhs: Callback, rhs: Callback) -> Bool { lhs.id == rhs.id }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Callback where Value == Void {
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

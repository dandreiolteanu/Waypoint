import SwiftUI

/// A button in an alert or confirmation dialog. Tapping it returns `value` to whoever awaited the alert.
///
/// ```swift
/// AlertAction("Delete", role: .destructive, value: Choice.delete)
/// ```
public struct AlertAction<Value: Sendable> {
    /// The button's title.
    public let title: String
    /// The button's role, such as `.destructive` or `.cancel`.
    public let role: ButtonRole?
    /// What the awaiting call returns when this button is tapped.
    public let value: Value

    /// A button titled `title` that returns `value`.
    public init(_ title: String, role: ButtonRole? = nil, value: Value) {
        self.title = title
        self.role = role
        self.value = value
    }
}

/// Whether a question shows as a centered alert or as a confirmation dialog (an action sheet on iPhone).
public enum AlertStyle: Sendable {
    /// A centered alert.
    case alert
    /// A confirmation dialog, which rises from the bottom on iPhone.
    case confirmationDialog
}

/// An alert waiting for an answer, held by the navigator showing it.
@MainActor
final class AlertRequest: Identifiable {
    let title: String
    let message: String?
    let style: AlertStyle
    let buttons: [Button]
    private var resolve: ((Int?) -> Void)?

    struct Button: Identifiable {
        let id: Int
        let title: String
        let role: ButtonRole?
    }

    init(title: String, message: String?, style: AlertStyle, buttons: [Button], resolve: @escaping (Int?) -> Void) {
        self.title = title
        self.message = message
        self.style = style
        self.buttons = buttons
        self.resolve = resolve
    }

    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Resolves the alert once. Pass `nil` for "dismissed without choosing".
    func finish(choosing index: Int?) {
        let resolve = self.resolve
        self.resolve = nil
        resolve?(index)
    }
}

extension Coordinator {
    /// Shows an alert or confirmation dialog and returns the value of the tapped button.
    /// Returns `nil` if the alert goes away without a choice: replaced by another alert, its navigator torn down, or a tap outside a confirmation dialog on iPad.
    ///
    /// The alert appears on the topmost presented navigator, so it's visible even when this coordinator's screen is covered by a sheet.
    ///
    /// ```swift
    /// let choice = await alert("Delete photo?", actions: [
    ///     AlertAction("Delete", role: .destructive, value: true),
    ///     AlertAction("Cancel", role: .cancel, value: false),
    /// ])
    /// ```
    public func alert<Value: Sendable>(
        _ title: String,
        message: String? = nil,
        style: AlertStyle = .alert,
        actions: [AlertAction<Value>]
    ) async -> Value? {
        guard let navigator = requireNavigator() else { return nil }
        let index = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let pending = PendingResult(continuation)
            let request = AlertRequest(
                title: title,
                message: message,
                style: style,
                buttons: actions.enumerated().map { AlertRequest.Button(id: $0.offset, title: $0.element.title, role: $0.element.role) },
                resolve: { index in
                    if let index { _ = pending.store(index) }
                    pending.resume()
                }
            )
            navigator.topmost.show(request)
        }
        return index.map { actions[$0].value }
    }

    /// Asks a yes/no question. Returns `true` only if the confirm button was tapped.
    public func confirm(
        _ title: String,
        message: String? = nil,
        confirmTitle: String,
        role: ButtonRole? = nil,
        cancelTitle: String = "Cancel",
        style: AlertStyle = .alert
    ) async -> Bool {
        await alert(title, message: message, style: style, actions: [
            AlertAction(confirmTitle, role: role, value: true),
            AlertAction(cancelTitle, role: .cancel, value: false)
        ]) ?? false
    }
}

// MARK: - Rendering

struct AlertModifier: ViewModifier {
    weak var navigator: Navigator?

    func body(content: Content) -> some View {
        let request = navigator?.alertRequest
        content
            .alert(request?.title ?? "", isPresented: isPresented(.alert), presenting: request) { request in
                buttons(for: request)
            } message: { request in
                if let message = request.message { Text(message) }
            }
            .confirmationDialog(request?.title ?? "", isPresented: isPresented(.confirmationDialog), titleVisibility: .visible, presenting: request) { request in
                buttons(for: request)
            } message: { request in
                if let message = request.message { Text(message) }
            }
    }

    private func buttons(for request: AlertRequest) -> some View {
        ForEach(request.buttons) { button in
            Button(button.title, role: button.role) { [weak navigator] in
                navigator?.finishAlert(request, choosing: button.id)
            }
        }
    }

    private func isPresented(_ style: AlertStyle) -> Binding<Bool> {
        // The request this binding was rendered with. Replacing an alert must not let SwiftUI's "false" for the old one finish the new one.
        weak let rendered = navigator?.alertRequest
        return Binding(
            get: { [weak navigator] in navigator?.alertRequest?.style == style },
            set: { [weak navigator] isPresented in
                // SwiftUI also writes false after a button tap. finishAlert lets the button's choice win, so this only catches dismissals with no choice.
                guard !isPresented, let navigator, let request = navigator.alertRequest, request === rendered, request.style == style else { return }
                navigator.finishAlert(request, choosing: nil)
            }
        )
    }
}

# Alerts

Ask a question from a coordinator, and await the answer.

## Confirm

```swift
func signOutTapped() async {
    guard await confirm("Sign out?", confirmTitle: "Sign out", role: .destructive) else { return }
    session.signOut()
}
```

``Coordinator/confirm(_:message:confirmTitle:role:cancelTitle:style:)`` returns `true` only if the confirm button was tapped.

## Choose

``Coordinator/alert(_:message:style:actions:)`` returns the value of the tapped ``AlertAction``, or `nil` if the alert went away without a choice:

```swift
enum ExportFormat { case pdf, png }

let format = await alert("Export as", style: .confirmationDialog, actions: [
    AlertAction("PDF", value: ExportFormat.pdf),
    AlertAction("PNG", value: ExportFormat.png),
])
```

Use ``AlertStyle/confirmationDialog`` for an action sheet, and ``AlertStyle/alert`` (the default) for a centered alert.

## Where it appears

Alerts show on the topmost presentation, so they're visible even when a sheet covers the screen that asked. An alert requested while a sheet is animating out waits for it to finish; UIKit refuses to present mid-dismissal. A new alert replaces one that's already up, and the replaced one returns `nil`.

## Limitation

Presenting a sheet *while an alert is on screen* can be dropped by UIKit, and SwiftUI offers no "alert finished dismissing" signal to queue on. Await the alert first, then present.

# Troubleshooting Waypoint

| Symptom | Cause | Fix |
| --- | --- | --- |
| `push`/`present` does nothing | Coordinator never started, or its flow already finished (`isFinished`) | Start it with `Navigator(root:)`, `pushFlow` or `presentFlow`; don't navigate from a flow the user left |
| Assertion "called before the coordinator was started" | Navigating from `init` or before the coordinator is in a navigator | Navigate after it's started (in a method called by a screen) |
| A push from a sheet appears behind the sheet | Sheet was shown with `present(.route)`; its screen belongs to the presenter | `presentFlow(Child())` so the sheet has its own stack |
| `dismissPresented()` doesn't close the sheet I'm in | It closes what *this* stack presents | Inside a presented flow use `finish()` |
| View model state resets / created twice | View model built in a view `init` or `@State` default | Build it in `destination(for:)` |
| Coordinator never deinits | It stores a screen's view model, or a long-running `Task` holds it | Don't store screen VMs; cancel work in `didFinish()` |
| Old tabs stay alive after sign-out | Old root not torn down, or `TabView` not wrapped in `TabHost` | `tabs.tearDown()` before replacing the root; always `TabHost` |
| Sheet appears late after another closes | Intentional: presentations wait for the previous dismissal animation | Nothing to fix |
| Stacked sheets from a deep link | Handled: each waits for the one below to finish appearing | Present them in order; no delays needed |
| Zoom falls back to a slide | Ids differ, duplicate ids on one screen, source not on the top screen of the navigating stack, a second tap while the first push animates, a sheet covers the stack, or iOS 17 | Same id both sides, unique per place on a screen; navigate from the source's own coordinator. Read the debug log line starting with "Waypoint:" |
| Crash "Cannot morph from a view that is not in the hierarchy" | A zoom started from a source on a covered screen or a screen leaving the window (Waypoint before scoped zoom sources, or a hand-written `matchedTransitionSource`) | Update Waypoint; use `.transitionSource(id:)`, not SwiftUI's modifiers, inside Waypoint stacks |
| Popover shows as a sheet on iPad | No view with `.popoverSource(id:)` on screen in that stack | Mark the anchor in the presenting screen |
| `.fitted` sheet is tiny | Navigation stack has no ideal size | `embedsInNavigationStack: false` and `.frame(idealWidth:idealHeight:)` |
| Split view inside a tab looks broken | Its navigator wraps it in a NavigationStack | `Navigator(root:, embedsInNavigationStack: false)` |
| `NavigationLink(value:)` does nothing | Waypoint's path holds its own entries | Navigate through the coordinator |
| `guard let x = await presentFlow(as:) { … } else` won't compile | Trailing closure in a `guard` condition | `presentFlow(as: .sheet, { … })` with parentheses |
| "type does not conform to Sendable" on an await | Awaited result type isn't `Sendable` | Make the result a `Sendable` value type |
| Await returns nil though the user picked something | The screen closed by another path first (`finish()`, `pop()`) | Only calling the `Callback` delivers a value |
| Sheet doesn't present while an alert is up | UIKit drops it | Await the alert first, then present |

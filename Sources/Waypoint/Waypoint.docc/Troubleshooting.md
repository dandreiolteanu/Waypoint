# Troubleshooting

Symptoms, causes and fixes, plus the SwiftUI behaviors Waypoint handles for you.

## Common mistakes

**A push or present does nothing.**
Either the coordinator was never started (a debug assertion says so), or its flow has already finished. Finished flows ignore navigation on purpose. Check ``Coordinator/isFinished``.

**The screen's view model is created twice, or loses its state.**
Create view models in ``Routing/destination(for:)`` and pass them in. Don't create them in a view's `init`, and don't use `@State` initial values for them. `destination(for:)` runs exactly once per screen.

**A coordinator never deinits.**
It keeps one of its own screens' view models in a stored property (see <doc:Ownership>), or a long-running `Task` holds it. Cancel work in ``Coordinator/didFinish()``.

**`dismissPresented()` closed the wrong thing, or nothing.**
`dismissPresented()` closes what this coordinator's *stack* is presenting. Inside a presented flow, close the flow itself with ``Coordinator/finish()``.

**A push from a sheet appears behind the sheet.**
The sheet's screen was shown with ``Routing/present(_:as:transition:)``, so it belongs to the presenting coordinator, and its pushes go to the presenter's stack. Present a flow (``Coordinator/presentFlow(_:as:transition:)``) when the sheet needs its own stack. In debug builds, Waypoint logs a warning when this happens.

**A sheet appears late.**
Presenting while another sheet is still animating out waits for that animation. That's deliberate: SwiftUI drops presentations that start mid-dismissal.

**The zoom transition falls back to a slide.**
The source id and the transition id differ, the source isn't in the same stack as the coordinator that navigates (a screen presented with `present(_:)` is the usual case), or the device runs iOS 17. See <doc:ZoomTransitions>.

**A navigator is freed immediately in a test.**
Coordinators hold their navigator weakly. Keep a strong reference in the test.

**`NavigationLink(value:)` does nothing.**
A Waypoint stack's path holds Waypoint's own entries. Navigate through the coordinator instead.

## SwiftUI behaviors handled for you

| Behavior | What Waypoint does |
| --- | --- |
| `NavigationStack` keeps the last popped destination (and its path element) until the next navigation. | The path holds lightweight tokens. A removed screen's view is dropped once it disappears, which releases its view model. |
| A presentation started during another's dismissal animation is silently dropped. | It's queued until the first one reports it's gone. |
| Navigating right after a screen closes can collide with its animation. | Awaits resume only after every closing screen is off screen. |
| A `TabView` removed by a root switch can keep its background tabs' content alive (on iOS 27, indefinitely, growing with every sign-out). | Tearing the tabs down makes ``TabHost`` render nothing while still mounted, so SwiftUI dismantles the `TabView` properly. Hosts also hold state weakly, and torn-down trees are empty. |
| An alert's `isPresented` can be set to `false` before the tapped button's action runs. | The button's choice wins. |
| A zoom must wrap the outermost presented view, and needs a namespace shared with its source. | Every host provides a namespace, and the zoom wraps the presented content, navigation stack included. |
| Zoomed screens can be dismissed by swiping down. | Tracked like any other pop or dismissal. For a cover, `.fullScreenCover(isInteractiveDismissDisabled: true)` turns the gesture off; for a push, use `.automatic`. |

## Known limitations

- Presenting a sheet while an alert from the same screen is up can be dropped by UIKit. Await the alert first.
- Zoom transitions need iOS 18, and fall back to the default animation on iOS 17.
- An awaited screen that SwiftUI keeps without ever reporting it gone resolves after two seconds at most, as a safety net.

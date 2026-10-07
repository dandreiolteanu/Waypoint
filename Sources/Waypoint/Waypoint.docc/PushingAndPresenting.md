# Pushing and Presenting

Every way into a screen, and every way back out.

## Screens and flows

There are two kinds of things to show:

- **A route**: one screen from this coordinator's `Route` enum, built by its ``Routing/destination(for:)``.
- **A flow**: another coordinator with routes of its own. Use one when a step has several screens or its own logic (settings, checkout, onboarding).

| | Route | Flow |
| --- | --- | --- |
| Push | ``Routing/push(_:transition:)`` | ``Coordinator/pushFlow(_:transition:then:)`` |
| Present | ``Routing/present(_:as:transition:)`` | ``Coordinator/presentFlow(_:as:transition:)`` |
| Await a value | ``Routing/push(transition:_:)``, ``Routing/present(as:transition:_:)`` | ``Coordinator/pushFlow(transition:_:)-(_,(Callback<Value>)->Child)``, ``Coordinator/presentFlow(as:transition:_:)-(_,_,(Callback<Value>)->Child)`` |

## Pushing

```swift
push(.recipe(id))
push(.recipe(id), transition: .zoom(sourceID: id))
push([.category(c), .recipe(id)])   // several at once, for deep links
setStack([.category(c)])            // replace everything above this flow's first screen
```

A **pushed flow** shares the parent's stack. Its screens are pushed on top of the parent's, and it can push its own routes:

```swift
pushFlow(SettingsCoordinator())
pushFlow(SettingsCoordinator(), then: [.notifications])   // start a few screens deep
```

## Presenting

```swift
present(.filters, as: .sheet(detents: [.medium, .large]))
present(.paywall, as: .fullScreenCover)
presentFlow(CheckoutCoordinator(cart: cart), as: .sheet)
```

A **presented route** is a single screen, still built by the presenting coordinator. A **presented flow** gets a stack of its own, so it can push inside the sheet. To push inside a sheet, present a flow.

Sheets stack. A flow inside a sheet can present another flow, and so on. Presenting when the same stack (any coordinator in it) is already presenting something *replaces* it. The new presentation waits for the old one's dismissal animation to finish, because SwiftUI drops presentations that start mid-dismissal.

See <doc:SheetsAndDetents> for every presentation option.

### Flows from a dependency container

The flow calls also take a coordinator whose concrete type is hidden (`any Routing`), so a feature can open another feature through a factory without knowing its type:

```swift
// Somewhere both features can see
var settings: (Callback<SettingsResult>) -> any Routing = { SettingsCoordinator(onFinish: $0) }

// The feature that opens it
let result = await presentFlow(as: .sheet) { container.settings($0) }
pushFlow(container.profile())
```

## Coming back

| Call | What it closes |
| --- | --- |
| ``Coordinator/finish()`` | This whole flow. A pushed flow pops back to the screen that pushed it; a presented flow is dismissed. |
| ``Coordinator/pop()`` | The top screen of the stack. |
| ``Coordinator/popToStart()`` | Everything above this flow's own first screen. |
| ``Coordinator/popToRoot()`` | Everything above the stack's root. |
| ``Coordinator/dismissPresented()`` | Whatever this stack is presenting, plus anything stacked on it. |
| ``Coordinator/dismissAll()`` | Every sheet and cover in this presentation tree. |

A screen shown with ``Routing/present(_:as:transition:)`` belongs to the presenting coordinator, so it closes with `dismissPresented()`. A screen inside a presented *flow* closes the flow with `finish()`.

> Important: Because a presented route belongs to the presenting coordinator, anything *it* pushes lands in the presenter's stack, **behind the sheet**. If a presented screen needs to push (or to zoom-present from its own views), present a flow instead.

In a pushed flow, ``Coordinator/pop()`` pops the top screen whoever owns it, and ``Coordinator/popToRoot()`` pops into the parent's screens, ending the flow. ``Coordinator/popToStart()`` stays inside the flow.

Users leave on their own too: the back button, swipe-back, swipe-down, and the long-press back menu. SwiftUI's `@Environment(\.dismiss)` works as well. Waypoint reads all of these from SwiftUI's own bindings, so the state, the coordinators' lifetimes and any awaits stay correct whichever way the user leaves.

## Reading the state

``Routing/routes`` lists this coordinator's routes in its stack, bottom first. ``Coordinator/presented`` is what the stack is presenting (``Presentation/isSheet`` tells a sheet from a cover), ``Navigator/topRoute(as:)`` is what's on top, and ``Navigator/depth`` counts the pushed screens. ``Coordinator/navigator`` reaches the underlying ``Navigator``, for ``Navigator/pop(count:)`` or ``Navigator/reset()``. These are mostly for tests (see <doc:Testing>), and occasionally for logic such as "don't push the same recipe twice".

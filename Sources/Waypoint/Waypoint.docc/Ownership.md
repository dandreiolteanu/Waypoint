# Ownership and Lifetime

Why nothing leaks, and the one rule that keeps it that way.

## The tree

Every stack is a ``Navigator``. A navigator holds its screens, and each screen holds the coordinator and view model that built it. A sheet or cover holds a child navigator, which can present again:

```
App ──► Navigator ──► root screen ──► HomeCoordinator, HomeViewModel
             │        pushed screen ──► SettingsCoordinator (a pushed flow), SettingsViewModel
             │
             └─► Presentation ──► Navigator ──► root screen ──► CheckoutCoordinator (a presented flow)
                                       └─► Presentation ──► …
```

**Strong references only point down this tree.** A coordinator's ``Coordinator/navigator`` is weak. Library views hold navigators, presentations and tab state weakly too.

So when a screen leaves navigation, the reason doesn't matter. It could be a pop, swipe-back, swipe-down, a parent dismissing, or a root switch. The screen's view model and coordinator are released with it.

## A flow's life

A coordinator starts when it's made a navigator's root, pushed with ``Coordinator/pushFlow(_:transition:then:)``, or presented with ``Coordinator/presentFlow(_:as:transition:)``. It ends when its **first** screen leaves. At that moment:

1. ``Coordinator/isFinished`` becomes `true`, and every navigation call on it is ignored. A `Task` that outlives the flow can't push or pop on screens that now belong to its parent.
2. Sheets the flow presented are dismissed.
3. ``Coordinator/didFinish()`` runs, once. Override it to cancel work.
4. Any await on the flow's result returns, once every screen leaving with it is off screen.

The coordinator object is freed when the last screen, view model or task holding it lets go.

## The one rule

**A coordinator must not keep its own screens' view models in stored properties.** The screen owns its view model, and the view model may own the coordinator. If the coordinator also owned the view model, that would be a cycle.

Everything else is safe:

- Views, view models and closures may hold coordinators strongly, including `{ self.push(.next) }` inside `destination(for:)`.
- A flow-wide model shared by several screens (a draft, a cart) can live in the coordinator, as long as it doesn't point back at the coordinator.

## Where to keep the root

Keep each root ``Navigator`` (or ``TabNavigator``) in something long-lived: an app coordinator, or let ``NavigationHost/init(root:)`` own it. Never create a navigator inside `body`.

When you discard a tree yourself (on sign-out, for example), call ``Navigator/tearDown()`` or ``TabNavigator/tearDown()`` first. Pending awaits then return `nil` and `didFinish()` runs right away, instead of whenever SwiftUI lets go of the old views.

## Checking it

``LifetimeTracker`` counts live coordinators, navigators and screens in debug builds. Register your view models with `LifetimeTracker.track(self, kind: .viewModel)` too. Walk into a flow and back out, and every count should return to where it was. The example app shows the counts in an overlay, and its UI tests assert on them after every flow.

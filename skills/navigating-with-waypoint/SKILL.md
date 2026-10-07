---
name: navigating-with-waypoint
description: Use when a SwiftUI app imports Waypoint, or when adding screens, pushing, presenting sheets/covers/popovers, detents, zoom transitions, passing data back from a screen, child coordinators/flows, tabs, split views, sign-in/sign-out root switching, deep links or alerts in such an app; also when navigation leaks, a sheet never appears, a push lands behind a sheet, or an await never returns.
---

# Navigating with Waypoint

## Overview

Waypoint is a coordinator library for SwiftUI. A **coordinator** owns a flow's navigation decisions; views and view models only report intent. Navigation is plain state, owned top-down (navigator → screens → coordinators and view models), so leaving a screen in any way frees what it built.

This file is enough for everyday work. Open a reference only when the task needs it.

## The five rules

1. **Navigation logic lives in coordinators.** Views never use `NavigationLink`, `.sheet(isPresented:)`, `.fullScreenCover`, `.popover` or `navigationDestination`. They call their view model, which calls the coordinator.
2. **View models reach the coordinator through a small `@MainActor protocol`** the coordinator conforms to. Holding the coordinator strongly is fine, and so is capturing `self` strongly in closures inside `destination(for:)`.
3. **Create each screen's view model inside `destination(for:)`** and pass it in. It runs once per screen. Never build view models in a view's `init` or as `@State` initial values.
4. **A coordinator never stores its own screens' view models.** That is the only way to create a retain cycle. Flow-wide models (a draft, a cart) that don't point back at the coordinator are fine; models shared with other flows come in through `init` from the parent.
5. **Navigators live in long-lived owners** (an app coordinator, a `TabNavigator`, `NavigationHost(root:)`), never in `body`. A tree you discard gets `tearDown()`.

## The canonical pattern

```swift
import SwiftUI
import Waypoint                                  // also in views that use transitionSource/popoverSource/Callback

@MainActor
final class ShopCoordinator: FlowCoordinator {
    enum Route: Hashable {                       // value payloads: ids or Hashable & Sendable models
        case list
        case product(Product)
        case quantity(Product, onPick: Callback<Int>)   // Callback = a screen sends a value back
    }

    private let cart: Cart                       // shared with other tabs, so it comes from the parent
    init(cart: Cart) { self.cart = cart }

    var initialRoute: Route { .list }

    func destination(for route: Route) -> some View {
        switch route {
        case .list: ProductListView(viewModel: ProductListViewModel(navigation: self))
        case .product(let product): ProductView(viewModel: ProductViewModel(product: product, cart: cart, navigation: self))
        case .quantity(let product, let onPick): QuantityPicker(product: product, onPick: onPick)
        }
    }
}

@MainActor protocol ProductListNavigation: AnyObject { func showProduct(_ product: Product) }
@MainActor protocol ProductNavigation: AnyObject { func chooseQuantity(for product: Product) async -> Int? }

extension ShopCoordinator: ProductListNavigation, ProductNavigation {
    func showProduct(_ product: Product) {
        push(.product(product), transition: .zoom(sourceID: product.id))
    }

    func chooseQuantity(for product: Product) async -> Int? {   // nil when the user swipes it away
        await present(as: .sheet(detents: [.medium])) { .quantity(product, onPick: $0) }
    }
}

// View: reports intent, marks the zoom source. No navigation code.
List(viewModel.products) { product in
    Button(product.name) { viewModel.didTap(product) }
        .transitionSource(id: product.id)
}

// View model: starts awaits in a Task. The await always resumes, so the Task needs no handle or cancellation.
func addTapped() {
    Task { if let qty = await navigation.chooseQuantity(for: product) { cart.add(product, quantity: qty) } }
}

// App, single stack:
WindowGroup { NavigationHost(root: ShopCoordinator(cart: Cart())) }
```

## Choosing the call

| I need to… | Call |
| --- | --- |
| Show a screen of this flow | `push(.route)` · `push(.route, transition: .zoom(sourceID: id))` |
| Push several, or replace the stack | `push([.a, .b])` · `setStack([.a])` |
| Start another coordinator in this stack | `pushFlow(Child())` · `pushFlow(Child(), then: [.deeper])` |
| Show one screen modally | `present(.route, as: .sheet(detents: [.medium, .large]))` |
| Show a multi-screen flow modally (it can push inside) | `presentFlow(Child(), as: .sheet)` / `.fullScreenCover` |
| iPad popover, sheet on iPhone | `present(.route, as: .popover(from: "id"))` + `.popoverSource(id: "id")` on the anchor (toolbar buttons work) |
| Get a value back | `await push { .r(onDone: $0) }` · `await present(as:) { … }` · `await pushFlow { Child(onFinish: $0) }` · `await presentFlow(as:) { … }` |
| Ask the user | `await confirm("Delete?", confirmTitle: "Delete", role: .destructive)` · `await alert(_:actions:)` |
| Close this whole flow | `finish()` (pops a pushed flow, dismisses a presented one) |
| Close what this stack presented | `dismissPresented()` |
| Go back | `pop()` · `popToStart()` (this flow's first screen) · `popToRoot()` |
| Clear every sheet | `dismissAll()` |
| Move a sheet or lock swipe-down | `presented?.selectedDetent = .large` · `enclosingPresentation?.isInteractiveDismissDisabled = dirty` |
| Run cleanup when the flow ends | `override func didFinish()` |

## Routes vs flows

- **A presented route** (`present(.r)`) is one screen built by *this* coordinator. Anything it pushes lands in this coordinator's stack, **behind the sheet**. It closes with `dismissPresented()`, usually through a closure passed from `destination(for:)`: `InfoView(onDone: { self.dismissPresented() })`.
- **A presented flow** (`presentFlow(Child())`) has its own stack. Inside it, `push` works and `finish()` closes it.
- Rule of thumb: if the modal has more than one screen, or a button that navigates, make it a flow.

## Results

The awaiting calls create the `Callback` for you. A screen gets it in its route; a flow gets it in its `init` (`CheckoutCoordinator(onFinish: $0)`) and calls it to finish with a value. Calling the callback closes the screen or flow and returns the value; don't also call `finish()`. Any other exit (swipe, back, `finish()`, Cancel, a deep-link reset, teardown) returns `nil`, and `confirm` returns `false`. Each await resumes exactly once, after the screen is off screen, so the next line can navigate safely. Result types must be `Sendable`.

In a `guard`, put the closure in parentheses: `guard let x = await presentFlow(as: .sheet, { Child(onDone: $0) }) else { return }`.

## Facts that come up

- **Sheets with detents and popovers adapted to sheets can be swiped down. Full-screen covers can't**, unless they use a zoom transition. Lock what can be swiped while there's unsaved input. The view model tracks dirtiness and reports it, and the coordinator applies it:
  `var text = "" { didSet { navigation.setDismissLocked(text != savedText) } }` → `func setDismissLocked(_ on: Bool) { enclosingPresentation?.isInteractiveDismissDisabled = on }`. From the presenting coordinator, use `presented?` instead of `enclosingPresentation?`.
- **Popovers default to `embedsInNavigationStack: false`.** Their `navigationTitle` and `toolbar` don't show; draw a header in the content, or pass `embedsInNavigationStack: true`.
- **Navigating a navigator that isn't on screen yet is safe**, for example pushing right after `tabs.select(.shop, reset: true)` or right after a root switch. Navigation is state; the host applies it when it appears.
- **`tearDown()` ends a whole tree.** It runs every coordinator's `didFinish()` and makes awaits return `nil`. It also frees the coordinators, view models and the models they own once your last reference goes.
- **Split view sidebars:** `List(items, selection: split.selection)` only selects when each row's `id` *is* the selection value (`var id: Self { self }`), or the row has `.tag(item)`. Otherwise taps select nothing, silently.
- **Zoom and popover ids only need to be unique within one stack** (one `NavigationHost`; each split-view column is its own).
- **A nested `enum Tab` shadows SwiftUI's `Tab`** inside its type. Build the `TabView` in a separate top-level view, or write `SwiftUI.Tab`.
- **`LifetimeTracker` tracks coordinators, navigators and screens automatically.** Register only view models.

## Where to look

| Need | Read |
| --- | --- |
| Tabs, sign-in ↔ signed-in root switching, deep links, split view, multiple windows | [references/app-structure.md](references/app-structure.md) |
| Every signature and option (styles, detents, sizing, transitions, readers) | [references/api.md](references/api.md) |
| Unit tests for coordinators, adding a test target, leak checks | [references/testing.md](references/testing.md) |
| Something misbehaves | [references/troubleshooting.md](references/troubleshooting.md) |

## Common mistakes

| Mistake | Fix |
| --- | --- |
| `NavigationLink`, `.sheet`, `navigationDestination` in a view | Report intent to the view model; navigate in the coordinator |
| View model created in a view's `init` / `@State var vm = VM()` | Create it in `destination(for:)` |
| Coordinator keeps `private var listViewModel` | Don't store screen view models; let the screen own them |
| A flow creates a model other flows must share | Create it in the parent and pass it into each flow's `init` |
| `Navigator(root:)` created inside `body` | Hold it in an app coordinator / `TabNavigator`, or use `NavigationHost(root:)` |
| `TabView` built without `TabHost`, or old root not torn down on sign-out | `TabHost(tabs) { … }` and `tabs.tearDown()` / `navigator.tearDown()` before replacing the root |
| Pushing from a screen shown with `present(.r)` | `presentFlow(Child())` so the modal has its own stack |
| `dismissPresented()` inside a presented flow to close itself | `finish()` |
| Zoom source and transition use different ids, or the same id twice on one screen | Same id on both sides; distinct ids per place (`.grid(id)`, `.related(id)`) |
| `.sheet(sizing: .fitted)` content shows tiny | Also pass `embedsInNavigationStack: false` and give the content an ideal size |
| Deep link pushes directly on a hidden tab | `tabs.select(.tab, reset: true)` first, then the tab coordinator's `open(link)` |

## Verify before you finish

1. It builds.
2. If the project has a test target, add a unit test that drives the coordinator and asserts `coordinator.routes` / `coordinator.presented?.route(as:)`. If it has none, say so in your summary instead of skipping silently; testing.md shows how to add one.
3. New view models call `LifetimeTracker.track(self, kind: .viewModel)` in `init`.

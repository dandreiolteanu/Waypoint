# Testing Waypoint navigation

## Adding a test target

With XcodeGen:

```yaml
targets:
  ShopperTests:
    type: bundle.unit-test
    platform: iOS
    sources: [ShopperTests]
    dependencies:
      - target: Shopper
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
schemes:
  Shopper:
    build: { targets: { Shopper: all, ShopperTests: [test] } }
    test: { targets: [ShopperTests] }
```

Then `xcodebuild test -scheme Shopper -destination 'platform=iOS Simulator,id=<udid>'`, with a udid from `xcrun simctl list devices available` (a device name can fail to match when several runtimes are installed). If the first run reports "Test crashed with signal kill while preparing", it's the simulator starting up: run it again.

## Unit tests (no SwiftUI)

Navigation is state, so coordinator tests run in milliseconds on macOS or the simulator. Keep the navigator in a local, and reference it at the end (`_ = navigator`) if the test doesn't otherwise use it: coordinators hold it weakly. Tests can build a `Callback { … }` themselves to pass into a flow's `init`.

```swift
import Testing
@testable import Shopper
import Waypoint

@MainActor
struct ShopCoordinatorTests {
    @Test func tappingAProductPushesIt() {
        let shop = ShopCoordinator(cart: Cart())
        let navigator = Navigator(root: shop)

        shop.showProduct(Product(id: 7))

        #expect(shop.routes == [.list, .product(7)])
        #expect(navigator.presentation == nil)
    }

    @Test func quantityPickerReturnsTheValue() async throws {
        let shop = ShopCoordinator(cart: Cart())
        let navigator = Navigator(root: shop)
        let task = Task { await shop.chooseQuantity(for: Product(id: 7)) }
        for _ in 0..<5 { await Task.yield() }                       // let it reach the sheet

        let route = try #require(shop.presented?.route(as: ShopCoordinator.Route.self))
        guard case .quantity(_, let onPick) = route else { Issue.record("wrong route"); return }
        onPick(3)

        #expect(await task.value == 3)
        #expect(navigator.presentation == nil)
    }

    @Test func swipingTheSheetAwayReturnsNil() async {
        let shop = ShopCoordinator(cart: Cart())
        let navigator = Navigator(root: shop)
        let task = Task { await shop.chooseQuantity(for: Product(id: 7)) }
        for _ in 0..<5 { await Task.yield() }

        navigator.dismissPresentation()                              // what a swipe-down does

        #expect(await task.value == nil)
    }
}
```

Readers: `coordinator.routes`, `navigator.topRoute(as:)`, `navigator.depth`, `coordinator.presented?.route(as:)` / `.topRoute(as:)` / `.selectedDetent` / `.isInteractiveDismissDisabled`, `navigator.rootCoordinator(as:)`, `tabs.coordinator(for:as:)`, `tabs.selectedTab`.

Drive a presented flow through its coordinator:

```swift
let task = Task { await shop.startCheckout() }
for _ in 0..<5 { await Task.yield() }
let checkout = try #require(shop.presented?.coordinator(as: CheckoutCoordinator.self))
checkout.addressEntered("1 Main St")        // whatever the flow's navigation methods are
checkout.placeOrder()
#expect(await task.value?.address == "1 Main St")
```

Simulate the user: `navigator.pop()` (swipe-back), `navigator.dismissPresentation()` (swipe-down), `navigator.tearDown()` (tree discarded). Deep links: `await main.open(.shop(.product(id: 7)))`, then assert `tabs.selectedTab` and the tab coordinator's `routes`.

Alerts can't be answered from an app's tests. Keep the decision in the coordinator method and put what happens after the answer in its own method (`func signOutConfirmed()`), then test that method directly.

## Deep links on the simulator

`xcrun simctl openurl booted 'shopper://product/7'` opens a link, but iOS first asks "Open in Shopper?". In a UI test, open it with `XCUIDevice.shared.system.open(url)` and tap the springboard's "Open" button if it appears:

```swift
XCUIDevice.shared.system.open(URL(string: "shopper://product/7")!)
let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
if open.waitForExistence(timeout: 2) { open.tap() }
```

## Leak checks

Unit tests prove state; only real SwiftUI proves objects are freed.

1. Register view models: `init(...) { …; LifetimeTracker.track(self, kind: .viewModel) }`.
2. In debug builds, show the counts somewhere a UI test can read them (an overlay with `accessibilityValue` = `"c=\(LifetimeTracker.liveCount(of: .coordinator)) …"`).
3. UI test: read the counts, walk into a flow and back out (including swipe-back and swipe-down), wait, and assert the counts returned to the starting values. On failure, print `LifetimeTracker.liveTypeNames()`.

The Waypoint repo's example app (`Example/WaypointExampleUITests`) has a complete overlay and helpers to copy.

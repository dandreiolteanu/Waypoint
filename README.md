# Waypoint

Coordinators for SwiftUI navigation. Pure SwiftUI (`NavigationStack`, `sheet`, `fullScreenCover`), with no UIKit hosting. Built for Swift 6 strict concurrency and `@Observable`.

- **Push, sheet, full-screen cover, zoom.** Push or present any route, with `.zoom(sourceID:)` for both (iOS 18+; earlier systems fall back).
- **Every detent.** `.medium`, `.large`, `.fraction`, `.height`, custom detents, a selected detent the coordinator can drive, background interaction, and locking swipe-to-dismiss while a form is dirty.
- **Child coordinators.** Push a child onto the parent's stack, or present it with a stack of its own. Nest them as deep as you like.
- **Results.** `let name = await push { .editName(onSave: $0) }`. You get the value back, or `nil` if the user swiped away. Each await resumes exactly once, and never hangs.
- **Tabs.** One stack per tab, and tapping the selected tab again pops it to root.
- **Root switching.** Sign in and sign out swap the whole tree, and the old one is freed.
- **Deep links.** Navigation is plain state, so a deep link is a few method calls.
- **Leak-proof by construction.** Coordinators are owned by the screens they put on screen. Popping, swiping back, swiping down, dismissing a parent, or switching root frees everything. The test suite and the example's UI tests prove it.

Requires iOS 17 / macOS 14, and Swift 6. Zoom transitions need iOS 18.

## Install

```swift
.package(url: "https://github.com/dandreiolteanu/Waypoint.git", from: "1.0.0")
```

## The model in one picture

```
App ──► Navigator (root) ──► StackEntry (root) ──► HomeCoordinator, HomeViewModel
             │                StackEntry (pushed) ──► ProfileCoordinator (pushed child), ProfileViewModel
             │
             └─► Presentation ──► Navigator ──► StackEntry (root) ──► CheckoutCoordinator (presented child)
                                       └─► Presentation ──► …
```

Strong references only point **down** this tree. A coordinator's link to its navigator is `weak`, so views and view models can hold coordinators strongly without creating cycles.
When an entry leaves the tree, through `pop`, swipe-back, swipe-down, `dismiss`, `finish`, or a root switch, three things happen:

1. Any await waiting on that screen returns `nil`.
2. The owning coordinator's `didFinish()` runs, if this was its first screen.
3. The entry and everything it owned are freed.

This is the main difference from libraries that keep a `children` array per coordinator, which must be pruned by hand.
Waypoint has no list to forget to prune. The navigation state is the ownership graph.

## Quick start

```swift
import SwiftUI
import Waypoint

@MainActor
final class LibraryCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case shelf
        case book(Book.ID)
        case editTitle(current: String, onSave: Callback<String>)
    }

    var initialRoute: Route { .shelf }

    // Called once per push/presentation; the result lives as long as the screen does.
    func destination(for route: Route) -> some View {
        switch route {
        case .shelf:
            ShelfView(viewModel: ShelfViewModel(navigation: self))
        case .book(let id):
            BookView(viewModel: BookViewModel(id: id, navigation: self))
        case .editTitle(let current, let onSave):
            EditTitleView(title: current, onSave: onSave)
        }
    }

    func showBook(_ id: Book.ID) {
        push(.book(id), transition: .zoom(sourceID: id))
    }

    func editTitle(_ current: String) async -> String? {
        await present(as: .sheet(detents: [.medium])) { .editTitle(current: current, onSave: $0) }
    }
}

@main
struct LibraryApp: App {
    @State private var navigator = Navigator(root: LibraryCoordinator())

    var body: some Scene {
        WindowGroup { NavigationHost(navigator) }
    }
}
```

On the source view, mark where the zoom starts:

```swift
BookCover(book).transitionSource(id: book.id)
```

## Recipes

### 1. Root switching (auth to signed in)

Keep the root as an enum in an `@Observable` app coordinator. Tear the old root down when you replace it.

```swift
@MainActor @Observable
final class AppCoordinator {
    enum Root { case auth(Navigator), main(MainCoordinator) }
    private(set) var root: Root

    func signedIn(_ user: User) {
        replaceRoot(with: .main(MainCoordinator(user: user, onSignOut: { [weak self] in self?.signedOut() })))
    }

    private func replaceRoot(with newRoot: Root) {
        switch root {
        case .auth(let navigator): navigator.tearDown()   // pending results → nil, didFinish() runs
        case .main(let main): main.tabs.tearDown()
        }
        root = newRoot                                     // dropping the reference frees the old tree
    }
}
```

The view switches on `root` with any transition you like. See `Example/WaypointExample/App/`.

### 2. Tabs

```swift
let tabs = TabNavigator(selectedTab: .feed, tabs: [
    .feed: Navigator(root: FeedCoordinator()),
    .profile: Navigator(root: ProfileCoordinator()),
])

TabView(selection: tabs.selection) {
    Tab("Feed", systemImage: "photo", value: AppTab.feed) { NavigationHost(tabs[.feed]) }
    Tab("Profile", systemImage: "person", value: AppTab.profile) { NavigationHost(tabs[.profile]) }
}
```

Tapping the selected tab again pops it to root (`popsToRootOnReselect`). For deep links, use `tabs.select(.profile, popToRoot: true)`.

### 3. Presenting: detents, covers, zoom

```swift
present(.filters, as: .sheet(detents: [.medium, .large], dragIndicator: .visible))
present(.map, as: .sheet(detents: [.height(200), .large], backgroundInteraction: .enabled(upThrough: .height(200))))
present(.compact, as: .sheet(detents: [.custom(CompactDetent.self)], initialDetent: .custom(CompactDetent.self)))
present(.paywall, as: .fullScreenCover)
present(.photo(id), as: .fullScreenCover(embedsInNavigationStack: false), transition: .zoom(sourceID: id))
present(child: CheckoutCoordinator(cart: cart), as: .sheet)   // a flow with its own stack
```

You can change things from inside the presented flow after it is on screen:

```swift
presentation?.selectedDetent = .large                  // move the sheet
presentation?.isInteractiveDismissDisabled = isDirty   // lock swipe-to-dismiss while editing
```

Presenting while something is already presented replaces it. The new presentation waits for the old one's dismissal animation to finish, because SwiftUI silently drops a presentation that starts mid-dismissal.
Use `dismiss()` for the presentation you're in, `dismissPresented()` for what you presented, and `navigator?.dismissAll()` to clear the whole stack of sheets.

### 4. Pushing, and pushed child flows

```swift
push(.book(id))
push(.book(id), transition: .zoom(sourceID: id))
push([.author(a), .book(b)])          // deep link
setStack([.author(a)])                // replace everything above this coordinator's first screen
push(child: SettingsCoordinator())    // shares this stack and pushes onto it too
```

Inside a pushed child, `finish()` pops back to the screen that pushed it, however deep the user went. `popToStart()` returns to the child's own first screen.

### 5. Passing data between screens

| Direction | How |
| --- | --- |
| Forward | Put it in the route (`.book(id)`) or the child coordinator's `init`. |
| Shared across a flow | The flow coordinator owns an `@Observable` draft and hands it to each step (see `OnboardingCoordinator`). |
| Back, awaited | `await push { .editName(onSave: $0) }` or `await present(as:) { … }` returns `Value?`. The callback closes the screen, and the await resumes once it's gone, so you can navigate again straight away. |
| Back from a flow | `await present(as: .sheet, child: { CheckoutCoordinator(onFinish: $0) })`. Same rules. |
| Back, fire-and-forget | Pass a `Callback<T>` or closure into the route or child yourself, and close it with `pop()` or `finish()`. |

`Callback<Value>` is a `Hashable` closure wrapper (compared by identity), so routes stay `Hashable`.

### 6. Alerts and confirmation dialogs

```swift
if await confirm("Sign out?", confirmTitle: "Sign out", role: .destructive) { signOut() }

// Format? (nil if dismissed without a choice, e.g. tapping outside on iPad)
let format = await alert("Export as", style: .confirmationDialog, actions: [
    AlertAction("PDF", value: Format.pdf),
    AlertAction("PNG", value: Format.png),
])
```

Alerts show on the topmost presented navigator, so they're visible even when a sheet covers the screen that asked.

## SwiftUI quirks Waypoint handles

Each of these was found by the example's UI tests, which run every flow in real SwiftUI and count live objects.

| Quirk | What Waypoint does |
| --- | --- |
| `NavigationStack` keeps the last popped destination (and its path element) alive until the next navigation. | SwiftUI's path holds lightweight tokens, not entries. A removed screen's view is dropped once it has disappeared, which makes SwiftUI release the view model. |
| Presenting while a sheet is still animating out is silently dropped. | The new presentation is queued until `onDismiss` reports the old one gone. |
| Doing the next navigation while a screen is still animating away (a root switch right after a cover dismisses, for example) leaves the old tree alive. | `await push` and `await present` resume only after the screen has fully left the screen. |
| A `TabView` removed by a root switch can keep its background tabs' content for a few more updates. | Library views hold navigators, presentations and tab state **weakly**, and entries drop their coordinator when removed. So what SwiftUI keeps is a shell, released as SwiftUI settles. Hold your own root view's model weakly too (see `MainView` in the example). |
| An alert's `isPresented` binding can be set to `false` before the tapped button's action runs. | The button's choice always wins. |
| Zoom transitions need the modifier on the outermost presented view, plus a namespace shared with the source. | Every `NavigationHost` provides a namespace. The zoom wraps the presented content, NavigationStack included. |

## Testing your coordinators

Navigation is state, so coordinator tests don't need SwiftUI:

```swift
@Test @MainActor func tappingABookPushesIt() {
    let library = LibraryCoordinator()
    let navigator = Navigator(root: library)

    library.showBook(42)

    #expect(library.routes == [.shelf, .book(42)])
    #expect(navigator.presentation == nil)
}
```

`LifetimeTracker` (debug only) counts live coordinators, navigators, screens and anything you register, such as view models.
Show `LifetimeTracker.liveCount(of:)` in a debug overlay, or assert on it in UI tests, the way the example does.

## Rules of thumb

- Create view models in `destination(for:)`, not in a view's `init`. The library calls it exactly once per screen.
- A coordinator must not hold its screens' view models strongly. It's the one way to create a cycle.
- Hold `Navigator`s in something long-lived (`@State`, an app coordinator), never in `body`. Views only need weak references, and Waypoint's own views hold them weakly.
- To push inside a presented sheet, present a child coordinator. A route presented with `present(_:)` is a single screen owned by the presenter.
- SwiftUI's own `@Environment(\.dismiss)`, the back button, swipe-back and swipe-down all work. They write through the same bindings, so Waypoint sees and handles them.
- Don't use `NavigationLink(value:)` inside a hosted stack. The path holds Waypoint entries, so navigate through the coordinator instead.

## Repository

- `Sources/Waypoint`: the library (about 700 lines).
- `Tests/WaypointTests`: Swift Testing suites for stack, presentation, results, tabs and memory, plus XCTest benchmarks.
- `Example/`: an app covering every case above, with UI tests that walk each flow and assert that every object it created is freed. Run `xcodegen generate` in `Example/`, then open `WaypointExample.xcodeproj`.

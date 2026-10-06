# Waypoint

Coordinators for SwiftUI navigation, in pure SwiftUI (`NavigationStack`, `sheet`, `fullScreenCover`), for Swift 6 and `@Observable`.

```swift
final class LibraryCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case shelf
        case book(Book.ID)
        case rename(current: String, onSave: Callback<String>)
    }

    var initialRoute: Route { .shelf }

    func destination(for route: Route) -> some View {
        switch route {
        case .shelf: ShelfView(viewModel: ShelfViewModel(coordinator: self))
        case .book(let id): BookView(viewModel: BookViewModel(id: id, coordinator: self))
        case .rename(let current, let onSave): RenameView(name: current, onSave: onSave)
        }
    }

    func open(_ book: Book) {
        push(.book(book.id), transition: .zoom(sourceID: book.id))
    }

    func rename(_ book: Book) async -> String? {
        await present(as: .sheet(detents: [.medium])) { .rename(current: book.title, onSave: $0) }
    }
}

@main struct LibraryApp: App {
    var body: some Scene {
        WindowGroup { NavigationHost(root: LibraryCoordinator()) }
    }
}
```

- **Push and present** routes, or whole flows (child coordinators), with any detent, full-screen covers and zoom transitions.
- **Await results.** `await push { … }` returns the value, or `nil` if the user left. It resumes exactly once, after the screen has fully left the screen.
- **Tabs, split views and root switching**, with tap-again-to-pop and teardown of the old tree.
- **iPad**: `NavigationSplitView` flows, popovers that adapt to sheets on iPhone, sheet sizing, multiple windows.
- **Leak-proof by construction.** Navigation state owns coordinators. However the user leaves (pop, swipe-back, swipe-down, dismissal, root switch), the flow is freed. Forty UI flows prove it on iPhone (iOS 18 and 27) and iPad, including repeated sign-out.
- **Testable without SwiftUI.** Navigation is plain state.

Requires iOS 17 (zoom transitions need iOS 18) and Swift 6. No dependencies.

```swift
.package(url: "https://github.com/dandreiolteanu/Waypoint.git", from: "1.0.0")
```

## Documentation

The full documentation is a DocC catalog. Build it with **Product › Build Documentation** in Xcode, or read the articles directly:

| Article | |
| --- | --- |
| [Getting Started](Sources/Waypoint/Waypoint.docc/GettingStarted.md) | A first coordinator, pushing, presenting, navigating from a view model |
| [Ownership and Lifetime](Sources/Waypoint/Waypoint.docc/Ownership.md) | Why nothing leaks, and the one rule |
| [Pushing and Presenting](Sources/Waypoint/Waypoint.docc/PushingAndPresenting.md) | Routes vs flows, every way in and out |
| [Sheets and Detents](Sources/Waypoint/Waypoint.docc/SheetsAndDetents.md) | Every detent, background interaction, locking dismissal |
| [Zoom Transitions](Sources/Waypoint/Waypoint.docc/ZoomTransitions.md) | Zoom pushes, sheets and covers |
| [Passing Data](Sources/Waypoint/Waypoint.docc/PassingData.md) | Forward, across a flow, and awaited results |
| [Tabs](Sources/Waypoint/Waypoint.docc/Tabs.md) | `TabNavigator` and `TabHost` |
| [Root Switching](Sources/Waypoint/Waypoint.docc/RootSwitching.md) | Signed out to signed in, and back |
| [Deep Links](Sources/Waypoint/Waypoint.docc/DeepLinks.md) | Links handed down the coordinator tree, sign-in gating, unsaved-work guards, notifications |
| [iPad](Sources/Waypoint/Waypoint.docc/iPad.md) | Split views, popovers, sheet sizing, sidebar tabs, multiple windows |
| [Alerts](Sources/Waypoint/Waypoint.docc/Alerts.md) | `confirm` and `alert`, awaited |
| [Testing](Sources/Waypoint/Waypoint.docc/Testing.md) | Unit tests for coordinators, leak checks in UI tests |
| [Troubleshooting](Sources/Waypoint/Waypoint.docc/Troubleshooting.md) | Symptoms and fixes, SwiftUI quirks handled, limitations |

## Cheat sheet

```swift
// Push
push(.recipe(id))
push(.recipe(id), transition: .zoom(sourceID: id))
push([.category(c), .recipe(id)])
setStack([.category(c)])
pushFlow(SettingsCoordinator())
pushFlow(SettingsCoordinator(), then: [.notifications])

// Present
present(.filters, as: .sheet(detents: [.medium, .large]))
present(.map, as: .sheet(detents: [.height(200), .large], backgroundInteraction: .enabled(upThrough: .height(200))))
present(.paywall, as: .fullScreenCover)
present(.photo(id), as: .fullScreenCover(embedsInNavigationStack: false), transition: .zoom(sourceID: id))
presentFlow(CheckoutCoordinator(cart: cart), as: .sheet)

// Await a value (nil if the user leaves another way)
let name  = await push { .editName(current: user.name, onSave: $0) }
let color = await present(as: .sheet(detents: [.medium])) { .colorPicker(onPick: $0) }
let order = await pushFlow { CheckoutCoordinator(onFinish: $0) }
let user  = await presentFlow(as: .fullScreenCover) { OnboardingCoordinator(onComplete: $0) }

// Close
finish()             // this flow: pops back to whoever pushed it, or dismisses it
pop(); popToStart(); popToRoot()
dismissPresented()   // what this stack is presenting
dismissAll()         // every sheet and cover in this presentation tree

// Control a sheet on screen
presented?.selectedDetent = .large
enclosingPresentation?.isInteractiveDismissDisabled = hasUnsavedChanges

// Ask
if await confirm("Sign out?", confirmTitle: "Sign out", role: .destructive) { signOut() }

// Tabs
let tabs = TabNavigator(selected: AppTab.feed) { tab in
    switch tab {
    case .feed: Navigator(root: FeedCoordinator())
    case .profile: Navigator(root: ProfileCoordinator())
    }
}
TabHost(tabs) { tabs in
    TabView(selection: tabs.selection) {
        Tab("Feed", systemImage: "house", value: AppTab.feed) { NavigationHost(tabs[.feed]) }
        Tab("Profile", systemImage: "person", value: AppTab.profile) { NavigationHost(tabs[.profile]) }
    }
}
tabs.select(.feed, reset: true)
tabs.coordinator(for: .feed, as: FeedCoordinator.self)?.showPost(id)

// Zoom source, in the view that's tapped
Thumbnail(photo).transitionSource(id: photo.id)

// iPad
present(.filters, as: .popover(from: "filters"))     // anchored to a view marked .popoverSource(id: "filters")
present(.settings, as: .sheet(sizing: .form))
let split = SplitNavigator<Album>(selected: .all) { album in Navigator(root: AlbumCoordinator(album: album)) }
SplitHost(split) { split in List(albums, selection: split.selection) { … } } placeholder: { … }
```

## The model in one picture

```
App ──► Navigator ──► root screen ──► HomeCoordinator, HomeViewModel
             │        pushed screen ──► SettingsCoordinator (a pushed flow), SettingsViewModel
             │
             └─► Presentation ──► Navigator ──► root screen ──► CheckoutCoordinator (a presented flow)
```

Strong references only point down the tree. Coordinators hold their navigator weakly, and Waypoint's views hold their state weakly. When a screen leaves, everything it owned is freed. The only rule is that **a coordinator must not keep its own screens' view models in stored properties.**

## How it compares

| | Waypoint | Typical coordinator libraries |
| --- | --- | --- |
| Child coordinator ownership | By the screens they show. Freed however the user leaves. | A `children` array pruned by hand, which leaks on swipe-back. |
| Swipe-back and swipe-down | Read from SwiftUI's own bindings | Often missed, or caught with `onDisappear` heuristics |
| Results | `await`, typed, exactly once, after the screen is gone | Delegates, closures, `Any` payloads |
| Sheet after sheet | Queued until the dismissal finishes | `asyncAfter(0.5)`, or silently dropped |
| Detents | Every kind, plus a detent the coordinator can read and write | Fixed at presentation time, if supported at all |
| Zoom | Push and present, namespaces handled | Left to the app |
| Globals | None. Every scene owns its tree. | Shared stores keyed by type |
| Proof | Unit tests, benchmarks, doc examples compiled as tests, UI tests counting live objects | Usually none for memory |

## Example app

`Example/WaypointExample.xcodeproj` is a complete app covering every case:
- signing in, signing out, and onboarding with root switching
- tabs
- zoom push, zoom cover, and zoom sheet
- every detent, plus a coordinator-driven detent
- locking dismissal while a form has unsaved changes
- nested sheets, and replacing one sheet with another
- awaited results and pushed flows
- an iPad split view (Albums), popovers, and sheet sizing; the app runs on iPhone and iPad, with multiple windows
- nine deep links, from Profile › Deep links: into tabs, the split view, stacked sheets, a flow several screens deep, a link that awaits a result, a guard that protects unsaved work, and a notification tap
- alerts

A debug overlay shows the number of live coordinators, navigators, screens and view models. Walk into any flow and back out, and they return to where they started.

## Running the tests

```bash
swift test   # unit tests, documentation examples and benchmarks, on macOS (about 10s)

xcodebuild test -project Example/WaypointExample.xcodeproj -scheme WaypointExample \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'   # 40 UI flows, about 13 minutes; also runs on iPad
```

Each UI test reads the overlay before and after a flow, and fails with the names of whatever is still alive. Run `xcodegen generate` in `Example/` only if you change `project.yml`.

## Repository

- `Sources/Waypoint`: the library (about 1,100 lines of code plus doc comments, no dependencies) and its DocC catalog.
- `Tests/WaypointTests`: Swift Testing suites for stack, presentation, results, tabs, alerts, memory, edge cases and the documentation examples, plus XCTest benchmarks.
- `Example`: the example app and its UI tests.

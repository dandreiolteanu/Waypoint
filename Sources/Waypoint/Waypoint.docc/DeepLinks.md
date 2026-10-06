# Deep Links

Turn a URL, a notification, or a shortcut into navigation, with each coordinator handling its own part.

## The shape

Navigation is state, so a deep link is a few method calls. The pattern that scales:

1. **Parse at the edge.** Turn the URL into a value, once. The rest of the app never sees strings.
2. **Hand it down the tree.** The app coordinator decides *whether* (sign-in). The tab coordinator decides *where* (which tab, from a clean slate). The feature's coordinator decides *how* (what to push or present).

Each feature owns its piece of the link, so adding a screen touches only that feature.

## Parse into values

```swift
enum DeepLink: Equatable {
    case feed(FeedLink)
    case profile(ProfileLink)

    init?(url: URL) {
        guard url.scheme == "myapp", let host = url.host() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "feed": guard let link = FeedLink(path: path) else { return nil }; self = .feed(link)
        case "profile": guard let link = ProfileLink(path: path) else { return nil }; self = .profile(link)
        default: return nil
        }
    }
}

enum FeedLink: Equatable {
    case post(id: Int)

    init?(path: [String]) {
        guard path.first == "post", let id = path.dropFirst().first.flatMap(Int.init) else { return nil }
        self = .post(id: id)
    }
}

enum ProfileLink: Equatable {
    case settings(SettingsCoordinator.Route?)   // myapp://profile/settings, …/settings/privacy
    case pickAvatar                             // myapp://profile/avatar

    init?(path: [String]) { … }                 // parsed like FeedLink
}
```

## The top: whether

The app coordinator receives every URL. Signed in, it forwards the link. Signed out, it parks it and opens it after sign-in:

```swift
// AppCoordinator
private var pendingDeepLink: DeepLink?

func open(_ url: URL) {
    guard let link = DeepLink(url: url) else { return }
    if case .main(let main) = root {
        Task { await main.open(link) }
    } else {
        pendingDeepLink = link
    }
}

private func showMain() {
    let main = MainCoordinator(…)
    replaceRoot(with: .main(main))
    if let link = pendingDeepLink {
        pendingDeepLink = nil
        Task { await main.open(link) }
    }
}
```

Wire it up per window: `.onOpenURL { app.open($0) }`.

## The middle: where

The tab coordinator picks the tab, gives it a clean slate, and hands over the feature's part. ``TabNavigator/select(_:reset:)`` with `reset: true` dismisses every sheet (whichever tab opened it) and pops the target tab to its root, so a link lands the same way wherever the user was. ``TabNavigator/coordinator(for:as:)`` reaches the tab's coordinator.

```swift
// MainCoordinator
func open(_ link: DeepLink) async {
    switch link {
    case .feed(let link):
        tabs.select(.feed, reset: true)
        tabs.coordinator(for: .feed, as: FeedCoordinator.self)?.open(link)
    case .profile(let link):
        tabs.select(.profile, reset: true)
        await tabs.coordinator(for: .profile, as: ProfileCoordinator.self)?.open(link)
    }
}
```

## The bottom: how

Each feature coordinator navigates inside its own flow, with everything it already uses:

```swift
// FeedCoordinator
func open(_ link: FeedLink) {
    switch link {
    case .post(let id): push(.post(id))
    }
}

// ProfileCoordinator
func open(_ link: ProfileLink) async {
    switch link {
    case .settings(let section):
        pushFlow(SettingsCoordinator(), then: section.map { [$0] } ?? [])   // a flow, a few screens deep
    case .pickAvatar:
        guard let image = await present(as: .sheet, { .avatarPicker(onPick: $0) }) else { return }
        session.updateAvatar(image)                                         // a link can await a result too
    }
}
```

For a split view, select first, then navigate inside the detail: `split.select(.sky, reset: true)`, then `split.detailCoordinator(as: AlbumCoordinator.self)?.showPhoto(id)`. See <doc:iPad>.

## Protecting unsaved work

A link shouldn't silently throw away a half-written draft. Before switching tabs, ask the coordinators that hold work:

```swift
// MainCoordinator.open(_:), first line
guard await editor.confirmLeavingUnsavedWork() else { return }

// The coordinator that knows about the draft
func confirmLeavingUnsavedWork() async -> Bool {
    guard hasUnsavedDraft else { return true }
    return await confirm("Discard your draft?", confirmTitle: "Discard and open", role: .destructive, cancelTitle: "Keep editing")
}
```

The alert shows on top of the editor's sheet, because alerts go to the topmost presentation. The same check suits checkout or payment flows that must not be interrupted. Decline the link there, or park it until the flow finishes.

## Notifications, shortcuts and Handoff

Give every entry point a URL, and send it through the same path:

- **Push notifications** carry a link in their payload. In `userNotificationCenter(_:didReceive:)`, read it and open it with `UIApplication.shared.open(url)`. The system routes it to the right window's `onOpenURL`, so there's one code path for everything.
- **Universal links** arrive through `onOpenURL` like custom schemes; parse the `https` host and path the same way.
- **Shortcuts and App Intents** can open a URL (`OpenURLIntent`).
- **Handoff and Spotlight** deliver an `NSUserActivity`. Read its `webpageURL`, or a link you put in `userInfo`, in `.onContinueUserActivity`, then call the same `open`.

## Testing deep links

Links are values and navigation is state, so routing is unit-testable without SwiftUI:

```swift
@Test @MainActor func postLinkOpensThePost() async {
    let main = MainCoordinator(…)

    await main.open(.feed(.post(id: 7)))

    #expect(main.tabs.selectedTab == .feed)
    #expect(main.tabs.coordinator(for: .feed, as: FeedCoordinator.self)?.routes == [.feed, .post(7)])
}

@Test func parsing() {
    #expect(DeepLink(url: URL(string: "myapp://feed/post/7")!) == .feed(.post(id: 7)))
    #expect(DeepLink(url: URL(string: "myapp://nope")!) == nil)
}
```

## In the example app

The example handles nine links, all listed in **Profile › Deep links**:
- a photo in a tab
- an album in the split view, and a photo inside it
- stacked sheets
- the editor, then a link that asks before discarding its draft
- a flow several screens deep
- a link that awaits a picker's result and saves it
- a simulated notification tap

UI tests open each one through the system, as Safari or another app would.

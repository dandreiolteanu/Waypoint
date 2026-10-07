# Tabs

One stack per tab, kept while you switch, with tap-again-to-pop.

## Set up

A ``TabNavigator`` holds the selected tab and one ``Navigator`` per tab. With a `CaseIterable` tab enum, the builder's `switch` is checked for exhaustiveness:

```swift
enum AppTab: Hashable, CaseIterable {
    case feed, search, profile
}

let tabs = TabNavigator(selected: AppTab.feed) { tab in
    switch tab {
    case .feed: Navigator(root: FeedCoordinator())
    case .search: Navigator(root: SearchCoordinator())
    case .profile: Navigator(root: ProfileCoordinator(session: session))
    }
}
```

Keep `tabs` in your app coordinator (see <doc:RootSwitching>). Show it with ``TabHost`` and your own `TabView`, so you choose the style, labels, badges and `Tab` API:

```swift
TabHost(tabs) { tabs in
    TabView(selection: tabs.selection) {
        Tab("Feed", systemImage: "house", value: AppTab.feed) { NavigationHost(tabs[.feed]) }
        Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) { NavigationHost(tabs[.search]) }
        Tab("Profile", systemImage: "person", value: AppTab.profile) { NavigationHost(tabs[.profile]) }
    }
}
```

Always wrap the `TabView` in ``TabHost``. When the tabs are torn down (``TabNavigator/tearDown()``), `TabHost` empties itself while still on screen, so SwiftUI dismantles the `TabView` properly. Without it, some OS versions keep a removed `TabView`'s background tabs alive after every sign-out. The teardown also releases every tab's navigator, so even your own view holding the tabs is harmless.

On iOS 17, which has no `Tab` API, use `.tabItem` and `.tag` the classic way:

```swift
TabHost(tabs) { tabs in
    TabView(selection: tabs.selection) {
        NavigationHost(tabs[.feed])
            .tabItem { Label("Feed", systemImage: "house") }
            .tag(AppTab.feed)
        NavigationHost(tabs[.profile])
            .tabItem { Label("Profile", systemImage: "person") }
            .tag(AppTab.profile)
    }
}
```

For a tab type that isn't `CaseIterable`, list the tabs yourself: ``TabNavigator/init(selected:tabs:popsToRootOnReselect:navigator:)``. ``TabNavigator/selectedTab`` is read-only; change it with ``TabNavigator/select(_:reset:)``, and read a tab's navigator with `tabs[.feed]`.

## Behavior

- Every tab keeps its stack while another tab is selected. (A sheet covers the tab bar, so users switch tabs only with no sheet up. A sheet opened in a tab you switch away from in code stays with that tab, unless you use `reset: true`.)
- Tapping the selected tab again pops it to its root. Turn that off with ``TabNavigator/popsToRootOnReselect``.
- ``TabNavigator/select(_:reset:)`` switches tabs from code. Pass `reset: true` for a deep link: it dismisses every tab's sheets and alerts (a pending `confirm` returns `false`) and pops the target tab to its root.

## Reaching a tab's coordinator

``TabNavigator/coordinator(for:as:)`` returns a tab's root coordinator, so a deep link doesn't need your own stored reference:

```swift
tabs.select(.feed, reset: true)
tabs.coordinator(for: .feed, as: FeedCoordinator.self)?.showPost(id)
```

## Tearing down

When the tabs go away (sign-out), call ``TabNavigator/tearDown()`` before dropping them. Pending awaits then return `nil`, and every coordinator's ``Coordinator/didFinish()`` runs right away.

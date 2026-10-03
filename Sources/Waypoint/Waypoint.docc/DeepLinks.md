# Deep Links

Turn a URL into a few coordinator calls.

## Parse, then navigate

Navigation is state, so a deep link is plain method calls: parse the URL into a value, then route it from the top.

```swift
enum DeepLink {
    case post(id: Int)
    case settings(SettingsCoordinator.Route?)

    init?(url: URL) { … }
}

// AppCoordinator
func open(_ url: URL) {
    guard let link = DeepLink(url: url) else { return }
    if case .main(let tabs) = root {
        route(link, in: tabs)
    } else {
        pendingDeepLink = link   // open it after sign-in
    }
}

private func route(_ link: DeepLink, in tabs: TabNavigator<AppTab>) {
    switch link {
    case .post(let id):
        tabs.select(.feed, reset: true)
        tabs.coordinator(for: .feed, as: FeedCoordinator.self)?.showPost(id)
    case .settings(let section):
        tabs.select(.profile, reset: true)
        tabs.coordinator(for: .profile, as: ProfileCoordinator.self)?
            .pushFlow(SettingsCoordinator(), then: section.map { [$0] } ?? [])
    }
}
```

Hook it up with `.onOpenURL { app.open($0) }`.

## Useful pieces

- ``TabNavigator/select(_:reset:)`` with `reset: true` dismisses every tab's sheets and pops the target tab, which gives a clean slate.
- ``Navigator/reset()`` does the same for a single stack.
- ``Routing/push(_:)`` pushes several routes at once, and ``Routing/setStack(_:)`` replaces the stack.
- ``Coordinator/pushFlow(_:transition:then:)`` starts a flow several screens deep.
- Presenting while a sheet is up queues the new presentation until the old one has gone, so "dismiss, then present" can be written as two lines.

## Links that arrive signed out

Store the parsed link, and open it once the root switches to the signed-in state. See <doc:RootSwitching>. The example app does exactly this with `waypoint://profile/settings`.

# Root Switching

Swap the whole app between signed-out and signed-in, and free the old tree.

## Model the root as state

An app coordinator holds the current root as an enum. Each case owns its tree: a ``Navigator`` for a single flow, or a ``TabNavigator`` for tabs.

```swift
@MainActor @Observable
final class AppCoordinator {
    enum Root {
        case launching
        case auth(Navigator)
        case main(TabNavigator<AppTab>)

        var id: String {
            switch self {
            case .launching: "launching"
            case .auth: "auth"
            case .main: "main"
            }
        }
    }

    private(set) var root: Root = .launching
    private let session: Session

    init(session: Session) {
        self.session = session
        if session.user != nil { showMain() } else { showAuth() }
    }

    private func showAuth() {
        replaceRoot(with: .auth(Navigator(root: AuthCoordinator(session: session, onSignedIn: { [weak self] _ in
            self?.showMain()
        }))))
    }

    private func showMain() {
        replaceRoot(with: .main(TabNavigator(selected: .feed) { tab in
            switch tab {
            case .feed: Navigator(root: FeedCoordinator())
            case .profile: Navigator(root: ProfileCoordinator(onSignOut: { [weak self] in self?.signOut() }))
            }
        }))
    }

    private func signOut() {
        session.signOut()
        showAuth()
    }

    private func replaceRoot(with newRoot: Root) {
        switch root {
        case .launching: break
        case .auth(let navigator): navigator.tearDown()
        case .main(let tabs): tabs.tearDown()
        }
        root = newRoot
    }
}
```

Two details matter:

- **Tear the old root down before replacing it.** Pending awaits in it return `nil`, its coordinators' ``Coordinator/didFinish()`` runs immediately, and a ``TabHost`` empties itself so SwiftUI can't keep the old tabs alive.
- **Callbacks to the app coordinator capture it weakly** (`[weak self]`). The flows don't own the app.

## Show it

```swift
struct AppRootView: View {
    let app: AppCoordinator

    var body: some View {
        ZStack {
            switch app.root {
            case .launching:
                ProgressView()
            case .auth(let navigator):
                NavigationHost(navigator).transition(.opacity)
            case .main(let tabs):
                TabHost(tabs) { tabs in
                    TabView(selection: tabs.selection) {
                        Tab("Feed", systemImage: "house", value: AppTab.feed) { NavigationHost(tabs[.feed]) }
                        Tab("Profile", systemImage: "person", value: AppTab.profile) { NavigationHost(tabs[.profile]) }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.default, value: app.root.id)
    }
}

@main struct MyApp: App {
    @State private var app = AppCoordinator(session: .shared)
    var body: some Scene { WindowGroup { AppRootView(app: app) } }
}
```

``NavigationHost`` and ``TabHost`` hold the trees weakly, and tearing a tree down empties it. So when SwiftUI keeps the old view around for its removal animation (or longer, which a `TabView` sometimes does), it can't keep the old flows alive.

## Opening a deep link after sign-in

A link that arrives while signed out is parked, then opened once the tabs exist:

```swift
private var pendingDeepLink: DeepLink?

private func showMain() {
    let tabs = makeTabs()
    replaceRoot(with: .main(tabs))
    if let link = pendingDeepLink {
        pendingDeepLink = nil
        route(link, in: tabs)   // see Deep Links
    }
}
```

## Switching after a flow returns

When a presented flow ends the signed-out state (onboarding creating an account), await it and switch on the next line:

```swift
func createAccount() async {
    guard let user = await presentFlow(as: .fullScreenCover, { OnboardingCoordinator(onComplete: $0) }) else { return }
    onSignedIn(user)
}
```

The await resumes only after the cover is fully off screen, so the root switch never races its dismissal.

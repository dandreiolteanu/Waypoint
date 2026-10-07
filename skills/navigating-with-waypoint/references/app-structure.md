# App structure with Waypoint

## Contents
- Root switching (sign-in ↔ signed in)
- Tabs
- Deep links (and notifications)
- Split view (iPad)
- Multiple windows

## Root switching

The app coordinator holds the root as an enum. Tear the old tree down before replacing it. Callbacks into the app coordinator capture it weakly. The `.launching` case exists so `root` has a value before `init` calls `showAuth()` / `showMain()` (which need `self`); it is never on screen.

```swift
@MainActor @Observable
final class AppCoordinator {
    enum Root {
        case launching
        case auth(Navigator)
        case main(MainCoordinator)

        var id: String {
            switch self { case .launching: "launching"; case .auth: "auth"; case .main: "main" }
        }
    }

    private(set) var root: Root = .launching
    private let session: Session
    private var pendingDeepLink: DeepLink?

    init(session: Session) {
        self.session = session
        if session.user != nil { showMain() } else { showAuth() }
    }

    private func showAuth() {
        replaceRoot(with: .auth(Navigator(root: AuthCoordinator(session: session, onSignedIn: { [weak self] in self?.showMain() }))))
    }

    private func showMain() {
        let main = MainCoordinator(session: session, onSignOut: { [weak self] in self?.signOut() })
        replaceRoot(with: .main(main))
        if let link = pendingDeepLink {
            pendingDeepLink = nil
            Task { await main.open(link) }
        }
    }

    private func signOut() {
        session.signOut()
        showAuth()
    }

    private func replaceRoot(with newRoot: Root) {
        switch root {
        case .launching: break
        case .auth(let navigator): navigator.tearDown()
        case .main(let main): main.tabs.tearDown()
        }
        root = newRoot
    }
}

struct AppRootView: View {
    let app: AppCoordinator

    var body: some View {
        ZStack {
            switch app.root {
            case .launching: ProgressView()
            case .auth(let navigator): NavigationHost(navigator).transition(.opacity)
            case .main(let main): MainView(tabs: main.tabs).transition(.opacity)
            }
        }
        .animation(.default, value: app.root.id)
    }
}
```

When a flow's result triggers the switch (onboarding creates an account), await the flow, then switch on the next line. The await returns only after the cover is off screen.

Everything signed-in (tabs, their coordinators and view models, models created in `MainCoordinator` such as a cart) hangs off `MainCoordinator`, so tearing it down and replacing the root frees all of it. Clear app-wide services (the session) yourself.

Sign-out confirmation belongs in the coordinator: `guard await confirm("Sign out?", confirmTitle: "Sign out", role: .destructive) else { return }; onSignOut()`.

## Tabs

```swift
@MainActor
final class MainCoordinator {
    enum Tab: Hashable, CaseIterable { case shop, cart, account }
    let tabs: TabNavigator<Tab>

    init(session: Session, onSignOut: @escaping () -> Void) {
        let cart = Cart()                                   // shared across tabs: create here, pass in
        tabs = TabNavigator(selected: .shop) { tab in
            switch tab {
            case .shop: Navigator(root: ShopCoordinator(cart: cart))
            case .cart: Navigator(root: CartCoordinator(cart: cart))
            case .account: Navigator(root: AccountCoordinator(session: session, onSignOut: onSignOut))
            }
        }
    }
}

struct MainView: View {
    let tabs: TabNavigator<MainCoordinator.Tab>

    var body: some View {
        TabHost(tabs) { tabs in                             // always wrap in TabHost
            TabView(selection: tabs.selection) {
                Tab("Shop", systemImage: "bag", value: .shop) { NavigationHost(tabs[.shop]) }
                Tab("Cart", systemImage: "cart", value: .cart) { NavigationHost(tabs[.cart]) }
                Tab("Account", systemImage: "person", value: .account) { NavigationHost(tabs[.account]) }
            }
            .tabViewStyle(.sidebarAdaptable)                // tab bar on iPhone, sidebar option on iPad
        }
    }
}
```

Tapping the selected tab again pops it to root (built in; `popsToRootOnReselect`). iOS 17: use `.tabItem { Label(…) }.tag(Tab.shop)` instead of `Tab(…)`.

## Deep links

Parse once into values, then hand down the tree: app (sign-in gate) → main (unsaved-work guard, pick and reset tab) → feature coordinator (`open(_:)`).

```swift
enum DeepLink: Equatable {
    case shop(ShopLink)
    init?(url: URL) {
        guard url.scheme == "shopper", let host = url.host() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "product": guard let id = path.first.flatMap(Int.init) else { return nil }; self = .shop(.product(id: id))
        default: return nil
        }
    }
}
enum ShopLink: Equatable { case product(id: Int) }

// AppCoordinator
func open(_ url: URL) {
    guard let link = DeepLink(url: url) else { return }
    if case .main(let main) = root { Task { await main.open(link) } } else { pendingDeepLink = link }
}

// MainCoordinator
func open(_ link: DeepLink) async {
    // optional guard: ask before discarding a draft somewhere
    // guard await editor.confirmLeavingUnsavedWork() else { return }
    switch link {
    case .shop(let link):
        tabs.select(.shop, reset: true)                     // dismisses every tab's sheets and alerts, pops shop
        tabs.coordinator(for: .shop, as: ShopCoordinator.self)?.open(link)
    }
}

// ShopCoordinator
func open(_ link: ShopLink) {
    switch link {
    case .product(let id): push(.product(id))
    }
}
```

Wire it per window: `.onOpenURL { app.open($0) }`. Register the scheme in Info.plist (`CFBundleURLTypes`). URL types have no `INFOPLIST_KEY_*` build setting, so a project using `GENERATE_INFOPLIST_FILE` still needs a real Info.plist for them. With XcodeGen:

```yaml
targets:
  Shopper:
    info:
      path: Shopper/Info.plist
      properties:
        CFBundleURLTypes:
          - CFBundleURLName: com.example.shopper
            CFBundleURLSchemes: [shopper]
```

`select(_:reset:)` also closes an open alert (its `confirm` returns `false`), and pushing on the very next line is safe.

Unsaved-work guard, in the coordinator that knows about the draft:

```swift
func confirmLeavingUnsavedWork() async -> Bool {
    guard hasUnsavedDraft else { return true }
    return await confirm("Discard your draft?", confirmTitle: "Discard and open", role: .destructive, cancelTitle: "Keep editing")
}
```

Push notifications: read the link from the payload in `userNotificationCenter(_:didReceive:)` and `UIApplication.shared.open(url)`, so it takes the same path. Universal links arrive in `onOpenURL` too.

## Split view (iPad)

```swift
@MainActor
final class AlbumsCoordinator: FlowCoordinator {
    enum Route: Hashable { case library }
    let split = SplitNavigator<Album>(selected: .all, columnVisibility: .all) { album in
        Navigator(root: AlbumCoordinator(album: album))      // a fresh flow per selection
    }
    var initialRoute: Route { .library }

    func destination(for route: Route) -> some View {
        SplitHost(split) { split in
            List(Album.allCases, selection: split.selection) { Label($0.title, systemImage: $0.icon) }
        } placeholder: {
            ContentUnavailableView("Pick an album", systemImage: "photo")
        }
    }

    override func didFinish() { split.tearDown() }
}

// Its navigator must not embed a NavigationStack:
Navigator(root: AlbumsCoordinator(), embedsInNavigationStack: false)
```

Deep link into it: `split.select(.sky, reset: true)`, then `split.detailCoordinator(as: AlbumCoordinator.self)?.showPhoto(id)`. `select` builds the detail flow synchronously, so `detailCoordinator` is ready on the next line, collapsed (iPhone) or not. Selecting the item that's already selected keeps its flow; with `reset: true` it dismisses its sheets and pops it to its root.

Sidebar rows must use the selection value as their id (`var id: Self { self }`), or carry `.tag(item)`; otherwise taps select nothing. Give the sidebar a title with `.navigationTitle` inside the sidebar closure.

When the split needs parameters (a shared store), build it in the coordinator's `init`:

```swift
let split: SplitNavigator<Category>
init(saved: SavedStore) {
    split = SplitNavigator(selected: nil, columnVisibility: .all) { category in
        Navigator(root: CategoryCoordinator(category: category, saved: saved))
    }
}
```

To run on iPad: `TARGETED_DEVICE_FAMILY: "1,2"` and iPad orientations in Info.plist (`UISupportedInterfaceOrientations~ipad`).

## Multiple windows

One coordinator tree per window; share app-wide services.

```swift
@main struct ShopperApp: App {
    @State private var session = Session()
    var body: some Scene { WindowGroup { SceneRoot(session: session) } }
}

struct SceneRoot: View {
    let session: Session
    @State private var app: AppCoordinator?
    var body: some View {
        if let app {
            AppRootView(app: app).onOpenURL { app.open($0) }
        } else {
            Color.clear.onAppear { app = AppCoordinator(session: session) }
        }
    }
}
```

Enable with `UIApplicationSupportsMultipleScenes` in Info.plist.

# iPad

Split views, popovers, sheet sizing, sidebar-adaptable tabs and multiple windows.

## Split view

``SplitNavigator`` drives a `NavigationSplitView`: a sidebar selection, and a full detail flow (a ``Navigator`` with its own coordinator) built for each selection.

```swift
@MainActor
final class AlbumsCoordinator: FlowCoordinator {
    enum Route: Hashable { case library }

    let split = SplitNavigator<Album>(selected: .landscapes) { album in
        Navigator(root: AlbumCoordinator(album: album))
    }

    var initialRoute: Route { .library }

    func destination(for route: Route) -> some View {
        SplitHost(split) { split in
            List(Album.allCases, selection: split.selection) { album in
                Label(album.title, systemImage: album.icon)
            }
            .navigationTitle("Albums")
        } placeholder: {
            ContentUnavailableView("Pick an album", systemImage: "photo")
        }
    }

    override func didFinish() {
        split.tearDown()
    }
}

// Root it without a NavigationStack: a split view must not sit inside one.
let navigator = Navigator(root: AlbumsCoordinator(), embedsInNavigationStack: false)
```

How it behaves:

- **Each selection is a flow.** Changing the selection tears the old detail flow down, freeing its coordinators and view models, and builds a fresh one. Selecting the current item again keeps its flow; ``SplitNavigator/select(_:reset:)`` with `reset: true` resets it instead.
- **Compact width collapses it.** On iPhone, and in narrow iPad windows, the split view becomes one stack. Picking a row pushes its detail, and going back clears the selection, which frees the detail flow. (SwiftUI keeps the last popped detail's views until the next selection, as a `NavigationStack` does with its last popped screen. It's released then, and never piles up.)
- **The sidebar is yours.** Build any list bound to ``SplitNavigator/selection``. ``SplitNavigator/columnVisibility`` shows or hides the sidebar.
- **Deep links** select and then navigate: `split.select(.sky, reset: true)`, then `split.detailCoordinator(as: AlbumCoordinator.self)?.showPhoto(id)`.

Like ``TabHost``, ``SplitHost`` holds the split navigator weakly and renders nothing once it's torn down.

## Popovers

Mark the anchor view, and present with ``PresentationStyle/popover(from:arrowEdge:compactAdaptation:detents:embedsInNavigationStack:)``:

```swift
// The anchor, in the screen that presents
Button("Filters", systemImage: "line.3.horizontal.decrease") { viewModel.showFilters() }
    .popoverSource(id: "filters")

// The coordinator
present(.filters, as: .popover(from: "filters"))                                  // a sheet on iPhone
present(.tip, as: .popover(from: "tip", compactAdaptation: .popover))             // a popover everywhere
```

- On iPad it's a popover pointing at the anchor. In compact width it adapts as `compactAdaptation` says: a sheet by default (using `detents`), `.popover`, or `.fullScreenCover`.
- The anchor must be in the same stack as the presenting coordinator, and on screen. If it isn't, the popover is shown as a sheet, and a debug log says why.
- Everything else works as for sheets: ``Coordinator/dismissPresented()``, awaited results, ``Coordinator/presented``, and tap-outside dismissal tracked like a swipe-down.

## Sheet sizing

Sheets float as cards on iPad. Choose their size with ``SheetSizing``:

```swift
present(.settings, as: .sheet(sizing: .form))     // the standard form card
present(.article(id), as: .sheet(sizing: .page))  // a larger card for reading
present(.badge, as: .sheet(sizing: .fitted, embedsInNavigationStack: false))   // as big as the content wants
```

A fitted sheet takes its content's ideal size, so give the content one (`.frame(idealWidth: 420, idealHeight: 320)`), and turn the navigation stack off: a stack has no ideal size of its own.

Detents apply in compact width, where the sheet spans the screen, so you can combine both: `.sheet(detents: [.medium, .large], sizing: .form)`.

## Tabs that become a sidebar

``TabNavigator`` and ``TabHost`` work unchanged with any `TabView` style. Use `.sidebarAdaptable` for a tab bar on iPhone and a tab bar people can turn into a sidebar on iPad:

```swift
TabHost(tabs) { tabs in
    TabView(selection: tabs.selection) { … }
        .tabViewStyle(.sidebarAdaptable)
}
```

## Multiple windows

Each window needs its own coordinator tree; navigation state is per window. Create the app coordinator inside the window's view, not in the `App`. Share app-wide services (the session) across windows:

```swift
@main struct MyApp: App {
    @State private var session = Session()

    var body: some Scene {
        WindowGroup { SceneRoot(session: session) }
    }
}

struct SceneRoot: View {
    let session: Session
    @State private var coordinator: AppCoordinator?

    var body: some View {
        if let coordinator {
            AppRootView(app: coordinator)
                .onOpenURL { coordinator.open($0) }
        } else {
            Color.clear.onAppear { coordinator = AppCoordinator(session: session) }
        }
    }
}
```

Enable multiple windows with `UIApplicationSupportsMultipleScenes` in the Info.plist. Links opened with `onOpenURL` arrive in the window the system picks, which then navigates on its own.

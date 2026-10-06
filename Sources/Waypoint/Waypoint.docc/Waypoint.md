# ``Waypoint``

Coordinators for SwiftUI navigation: push, sheets with any detent, full-screen covers, popovers, zoom transitions, tabs, split views, root switching, deep links and results, with no leaks however the user leaves a screen.

## Overview

A coordinator decides where a flow goes next. Screens ask it to navigate; they never navigate themselves. Waypoint gives every coordinator a small, typed vocabulary:

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

What makes it different:

- **Navigation state owns coordinators.** A coordinator lives exactly as long as its screens. Pop, swipe back, swipe down, dismiss or switch root, and everything that flow created is freed. There's no child list to prune.
- **Results are awaited.** `await push { … }` returns the value, or `nil` if the user left another way. It resumes exactly once, after the screen has fully left the screen.
- **SwiftUI's sharp edges are handled.** Presentations queue behind dismissals, zoom namespaces are managed, and views hold state weakly so SwiftUI's retained trees can't keep your flows alive.
- **Everything is state**, so coordinators are unit-testable without SwiftUI.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Ownership>
- ``FlowCoordinator``
- ``Coordinator``
- ``Routing``
- ``NavigationHost``
- ``Navigator``

### Navigating

- <doc:PushingAndPresenting>
- <doc:SheetsAndDetents>
- <doc:ZoomTransitions>
- ``PresentationStyle``
- ``Presentation``
- ``ScreenTransition``

### Data and results

- <doc:PassingData>
- ``Callback``

### App structure

- <doc:Tabs>
- <doc:RootSwitching>
- <doc:DeepLinks>
- ``TabNavigator``
- ``TabHost``

### iPad

- <doc:iPad>
- ``SplitNavigator``
- ``SplitHost``
- ``SheetSizing``

### Alerts

- <doc:Alerts>
- ``AlertAction``
- ``AlertStyle``

### Testing and diagnostics

- <doc:Testing>
- <doc:Troubleshooting>
- ``LifetimeTracker``

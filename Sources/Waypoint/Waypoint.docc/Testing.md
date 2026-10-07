# Testing

Unit-test coordinators without SwiftUI, and catch leaks in UI tests.

## Coordinators are plain state

Create a navigator, drive the coordinator, and assert on routes. Nothing is rendered. The examples use the `LibraryCoordinator` from the overview, extended with a `.filters` route and a `showFilters()` method that presents it as a medium sheet:

```swift
import Testing
@testable import MyApp
import Waypoint

@MainActor
struct LibraryCoordinatorTests {
    @Test func openingABookPushesIt() {
        let library = LibraryCoordinator()
        let navigator = Navigator(root: library)

        library.open(Book(id: 42))

        #expect(library.routes == [.shelf, .book(42)])
        #expect(navigator.presentation == nil)
    }

    @Test func filtersOpenAsAMediumSheet() {
        let library = LibraryCoordinator()
        let navigator = Navigator(root: library)

        library.showFilters()

        #expect(library.presented?.route(as: LibraryCoordinator.Route.self) == .filters)
        #expect(library.presented?.selectedDetent == .medium)
        _ = navigator
    }
}
```

Keep the navigator in a local, as above. Coordinators hold it weakly, so without a strong reference it would be freed at once.

Useful readers:

- ``Routing/routes``: this coordinator's routes, bottom first.
- ``Navigator/topRoute(as:)`` and ``Navigator/depth``: the top of the stack.
- ``Coordinator/presented``, ``Presentation/route(as:)`` and ``Presentation/topRoute(as:)``: what's presented.
- ``Navigator/rootCoordinator(as:)``, ``Presentation/coordinator(as:)`` and ``TabNavigator/coordinator(for:as:)``: reach a child flow, including a presented one.
- ``LifetimeTracker/liveCount(of:)`` and ``LifetimeTracker/liveTypeNames(of:)``: what's still alive, by kind and by type name.

## Simulating the user

```swift
navigator.pop()                  // back button or swipe-back
navigator.dismissPresentation()  // swipe-down
navigator.tearDown()             // the tree is discarded
```

## Results

Start the awaiting call in a `Task`, let it reach the screen, then answer through the route's callback:

```swift
@Test func renameReturnsTheNewName() async throws {
    let library = LibraryCoordinator()
    let navigator = Navigator(root: library)
    let task = Task { await library.rename(Book(id: 1, title: "Old")) }
    await Task.yield()

    let route = try #require(library.presented?.route(as: LibraryCoordinator.Route.self))
    guard case .rename(_, let onSave) = route else { Issue.record("wrong route"); return }
    onSave("New")

    #expect(await task.value == "New")
    #expect(navigator.presentation == nil)
}
```

Without SwiftUI, nothing is ever "on screen", so awaits resume as soon as the screen is closed.

## Leaks, in UI tests

Unit tests prove the navigation state is right. Only real SwiftUI proves the objects are freed, because SwiftUI keeps some views longer than you'd think. Register view models with ``LifetimeTracker``, show ``LifetimeTracker/liveCount(of:)`` somewhere a UI test can read it, and assert the counts return to their starting values after each flow. The example app's overlay and UI tests do exactly this, for 40 flows, on iPhone and iPad.

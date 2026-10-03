# Getting Started

Put a first coordinator on screen, push a screen, and present a sheet.

## Add the package

```swift
.package(url: "https://github.com/dandreiolteanu/Waypoint.git", from: "1.0.0")
```

Waypoint needs iOS 17 (zoom transitions need iOS 18) and Swift 6. It has no dependencies.

## Write a coordinator

A coordinator is a class that subclasses ``FlowCoordinator`` and declares three things:

1. A `Route` enum: every screen the flow can show. Associated values carry each screen's input.
2. ``Routing/initialRoute``: the first screen.
3. ``Routing/destination(for:)``: how each route becomes a view.

```swift
import SwiftUI
import Waypoint

@MainActor
final class RecipesCoordinator: FlowCoordinator {
    enum Route: Hashable {
        case list
        case recipe(Recipe.ID)
        case filters
    }

    var initialRoute: Route { .list }

    func destination(for route: Route) -> some View {
        switch route {
        case .list:
            RecipeListView(viewModel: RecipeListViewModel(coordinator: self))
        case .recipe(let id):
            RecipeView(viewModel: RecipeViewModel(id: id))
        case .filters:
            FiltersView(onDone: { self.dismissPresented() })
        }
    }

    func showRecipe(_ id: Recipe.ID) {
        push(.recipe(id))
    }

    func showFilters() {
        present(.filters, as: .sheet(detents: [.medium, .large]))
    }
}
```

`destination(for:)` runs once per push or presentation, and the view it returns lives as long as the screen. That makes it the place to create each screen's view model: one screen, one view model, no recreation on re-render.

## Show it

```swift
@main
struct RecipesApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationHost(root: RecipesCoordinator())
        }
    }
}
```

``NavigationHost/init(root:)`` creates the ``Navigator`` once and keeps it. When something else needs the navigator (an app coordinator that switches roots, or a ``TabNavigator``), create it there and use ``NavigationHost/init(_:)`` instead.

## Navigate from a view model

View models hold their coordinator (or a protocol it conforms to) and call it:

```swift
@MainActor
protocol RecipeListNavigation: AnyObject {
    func showRecipe(_ id: Recipe.ID)
    func showFilters()
}

extension RecipesCoordinator: RecipeListNavigation {}

@MainActor @Observable
final class RecipeListViewModel {
    private let coordinator: RecipeListNavigation

    init(coordinator: RecipeListNavigation) {
        self.coordinator = coordinator
    }

    func didTap(_ recipe: Recipe) {
        coordinator.showRecipe(recipe.id)
    }
}
```

Holding the coordinator strongly is fine. Coordinators hold their navigator weakly, so this can't form a cycle. See <doc:Ownership>.

## Next steps

- <doc:PushingAndPresenting> covers every way in and out of a screen.
- <doc:PassingData> shows how screens send values back.
- <doc:Tabs> and <doc:RootSwitching> structure a whole app.

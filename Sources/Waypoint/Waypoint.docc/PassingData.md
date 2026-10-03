# Passing Data

Send data forward into a screen, share it across a flow, and get results back.

## Forward: put it in the route

A route's associated values are the screen's input:

```swift
enum Route: Hashable {
    case recipe(Recipe.ID)
    case cook(Recipe, servings: Int)
}

push(.cook(recipe, servings: 4))
```

A flow takes its input in its initializer: `pushFlow(CheckoutCoordinator(cart: cart))`.

## Across a flow: share a model

When several screens build up one result (onboarding, checkout), the flow's coordinator owns a single `@Observable` model and hands the same instance to every step:

```swift
@MainActor @Observable
final class SignUpDraft {
    var name = ""
    var plan: Plan = .free
}

final class SignUpCoordinator: FlowCoordinator {
    enum Route: Hashable { case name, plan, summary }

    private let draft = SignUpDraft()   // fine: the draft doesn't point back at the coordinator

    var initialRoute: Route { .name }

    func destination(for route: Route) -> some View {
        switch route {
        case .name: NameStep(draft: draft, onNext: { self.push(.plan) })
        case .plan: PlanStep(draft: draft, onNext: { self.push(.summary) })
        case .summary: SummaryStep(draft: draft, onFinish: { self.finishSignUp() })
        }
    }
}
```

## Back: await the result

A screen that returns a value takes a ``Callback`` in its route. The awaiting APIs create the callback for you, and give back the value, or `nil` if the user left another way:

```swift
enum Route: Hashable {
    case profile
    case editName(current: String, onSave: Callback<String>)
}

func editName() async {
    guard let name = await push({ .editName(current: user.name, onSave: $0) }) else {
        return   // the user went back
    }
    user.name = name
}
```

The screen calls the callback like a function:

```swift
struct EditNameView: View {
    @State var name: String
    let onSave: Callback<String>

    var body: some View {
        TextField("Name", text: $name)
            .toolbar { Button("Save") { onSave(name) } }
    }
}
```

Calling it closes the screen and returns the value. There are four variants:

```swift
let name = await push { .editName(current: user.name, onSave: $0) }
let color = await present(as: .sheet(detents: [.medium])) { .colorPicker(onPick: $0) }
let answers = await pushFlow { SurveyCoordinator(onFinish: $0) }
let user = await presentFlow(as: .fullScreenCover) { OnboardingCoordinator(onComplete: $0) }
```

Result types must be `Sendable` (value types usually are), because the value crosses from the screen back to the awaiting task.

The guarantees:

- **The await resumes exactly once.** It gets the value if the callback was called, or `nil` after a swipe-back, swipe-down, parent dismissal, or teardown. Calling the callback again, or after the screen left, does nothing.
- **It resumes after the screen is off screen**, including every screen the flow had pushed and any sheet it had presented. So you can present, push or switch roots on the next line without colliding with a transition still running.
- **It never hangs.** If a tree is discarded without a teardown, the await still returns `nil`.

Only the callback delivers a value. If the flow ends any other way, including its own ``Coordinator/finish()`` (a Cancel button), the await returns `nil`.

From a view model, start the await in a `Task`:

```swift
func editNameTapped() {
    Task { await coordinator.editName() }
}
```

## Back without waiting

When the parent doesn't need to wait (it just reacts to events), pass a ``Callback`` or plain closure in yourself, and close the screen when you like:

```swift
pushFlow(FiltersCoordinator(onChange: Callback { filters in self.apply(filters) }))
```

A ``Callback`` with no value is `Callback<Void>`, and is called as `onDone()`.

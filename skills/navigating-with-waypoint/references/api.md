# Waypoint API reference

## Contents
- Coordinators
- Navigating (routes, flows, results)
- Closing and reading
- Presentation styles
- Transitions and anchors
- Containers and hosts
- Alerts
- Diagnostics

## Coordinators

```swift
@MainActor open class Coordinator
    public init()
    open func didFinish()                          // once, when the flow's first screen leaves
    public private(set) weak var navigator: Navigator?
    public private(set) var isFinished: Bool        // finished flows ignore navigation calls

@MainActor public protocol Routing: Coordinator
    associatedtype Route: Hashable
    var initialRoute: Route { get }
    @ViewBuilder func destination(for route: Route) -> Destination   // called once per screen

public typealias FlowCoordinator = Coordinator & Routing     // subclass this
```

## Navigating

On any `Routing` coordinator:

```swift
push(_ route: Route, transition: ScreenTransition = .automatic)
push(_ routes: [Route])
setStack(_ routes: [Route])                      // replaces everything above this flow's first screen
present(_ route: Route, as: PresentationStyle = .sheet, transition: ScreenTransition = .automatic)
var routes: [Route]                              // this coordinator's routes in the stack, bottom first

// awaited, Value: Sendable, nil if the user leaves another way
await push(transition: = .automatic) { (Callback<Value>) -> Route }
await present(as: = .sheet, transition: = .automatic) { (Callback<Value>) -> Route }
```

On any `Coordinator`:

```swift
pushFlow(_ child: Child, transition: = .automatic, then: [Child.Route] = [])
presentFlow(_ child: Child, as: PresentationStyle = .sheet, transition: = .automatic)
await pushFlow(transition: = .automatic) { (Callback<Value>) -> Child }
await presentFlow(as: = .sheet, transition: = .automatic) { (Callback<Value>) -> Child }
```

## Closing and reading

```swift
finish()              // ends this flow: pushed → pops to whoever pushed it; presented → dismisses
pop()                 // top screen of the stack, whoever owns it
popToStart()          // back to this flow's first screen
popToRoot()           // back to the stack's root (ends a pushed flow)
dismissPresented()    // what this stack presents, plus anything on top
dismissAll()          // every presentation in this presentation tree
var presented: Presentation?             // what this stack presents
var enclosingPresentation: Presentation? // the sheet/cover this stack lives in

final class Presentation
    var selectedDetent: PresentationDetent          // two-way; set it to move the sheet
    var isInteractiveDismissDisabled: Bool
    var isSheet: Bool
    func route<R>(as: R.Type) -> R?                  // bottom route of the presented stack
    func coordinator<C>(as: C.Type) -> C?            // the presented flow's coordinator
    func topRoute<R>(as: R.Type) -> R?

final class Navigator
    init(root: some Routing, embedsInNavigationStack: Bool = true)   // false for a split-view root
    var presentation: Presentation?
    var depth: Int
    func topRoute<R>(as: R.Type) -> R?
    func rootCoordinator<C>(as: C.Type) -> C?
    func pop(count: Int = 1), popToRoot(), reset(), dismissPresentation(), dismissAll(), tearDown()
```

`reset()` dismisses sheets and alerts and pops to root. `tearDown()` ends the whole tree: awaits return nil, every `didFinish()` runs.

## Presentation styles

```swift
.sheet                                              // large
.sheet(detents: [PresentationDetent] = [.large],    // ordered; opens at the first
       initialDetent: PresentationDetent? = nil,    // must be one of detents
       dragIndicator: Visibility = .automatic,
       isInteractiveDismissDisabled: Bool = false,
       backgroundInteraction: PresentationBackgroundInteraction = .automatic,
       cornerRadius: CGFloat? = nil,
       sizing: SheetSizing = .automatic,            // .form / .page / .fitted on iPad (iOS 18)
       embedsInNavigationStack: Bool = true)
.fullScreenCover
.fullScreenCover(isInteractiveDismissDisabled: Bool = false, embedsInNavigationStack: Bool = true)
.popover(from sourceID: some Hashable,
         arrowEdge: Edge? = nil,
         compactAdaptation: PresentationAdaptation = .sheet,   // .popover keeps it a popover on iPhone
         detents: [PresentationDetent] = [.medium, .large],     // used when it adapts to a sheet
         embedsInNavigationStack: Bool = false)
```

Any detent works: `.medium`, `.large`, `.fraction(0.3)`, `.height(240)`, `.custom(MyDetent.self)`. Other presentation modifiers (`presentationBackground`, …) go on the presented screen's view.

A popover whose anchor isn't on screen shows as a sheet. `.fitted` sizing needs `embedsInNavigationStack: false` plus an ideal size on the content.

## Transitions and anchors

```swift
ScreenTransition.automatic
ScreenTransition.zoom(sourceID: some Hashable)   // iOS 18; falls back on iOS 17

view.transitionSource(id: some Hashable)         // zoom source, in the same stack as the navigating coordinator
view.popoverSource(id: some Hashable)            // popover anchor, same rule; works on toolbar buttons
```

## Containers and hosts

```swift
NavigationHost(root: MyCoordinator())            // owns its navigator; for app-lifetime roots
NavigationHost(navigator)                        // shows a navigator you own (held weakly)

TabNavigator(selected: .feed) { tab in Navigator(root: …) }           // Tab: CaseIterable, exhaustive switch
TabNavigator(selected: .feed, tabs: [.feed, .me]) { tab in … }        // any Hashable tab
    var selectedTab: Tab                        // read-only; change with select
    var selection: Binding<Tab>                 // for TabView(selection:)
    var popsToRootOnReselect: Bool              // default true
    subscript(tab) -> Navigator
    func coordinator<C>(for: Tab, as: C.Type) -> C?
    func select(_ tab: Tab, reset: Bool = false) // reset: dismiss every tab's sheets and alerts, pop tab to root
    func tearDown()

TabHost(tabs) { tabs in TabView(selection: tabs.selection) { Tab(…) { NavigationHost(tabs[.feed]) } } }

SplitNavigator<Selection>(selected: nil, columnVisibility: .automatic) { selection in Navigator(root: …) }
    var selected: Selection?, detail: Navigator?, columnVisibility
    var selection: Binding<Selection?>          // for List(selection:)
    func select(_:reset:), detailCoordinator(as:), tearDown()

SplitHost(split) { split in List(items, selection: split.selection) { … } } placeholder: { … }
```

## Alerts

```swift
await confirm(_ title: String, message: String? = nil, confirmTitle: String,
              role: ButtonRole? = nil, cancelTitle: String = "Cancel", style: AlertStyle = .alert) -> Bool
await alert<Value: Sendable>(_ title: String, message: String? = nil, style: AlertStyle = .alert,
              actions: [AlertAction<Value>]) -> Value?
AlertAction(_ title: String, role: ButtonRole? = nil, value: Value)
AlertStyle.alert / .confirmationDialog
```

Alerts show on the topmost presentation. Don't present a sheet while an alert from the same stack is up; await the alert first.

## Callback

```swift
struct Callback<Value>: Hashable          // equal only to itself
    init(_ action: @MainActor (Value) -> Void)
    func callAsFunction(_ value: Value)    // onSave(name)
    func callAsFunction()                  // Callback<Void>: onDone()
```

## Diagnostics

```swift
LifetimeTracker.track(self, kind: .viewModel)        // in view model init; no-op in release
LifetimeTracker.liveCount(of: .coordinator / .navigator / .entry / .viewModel) -> Int
LifetimeTracker.liveTypeNames(of: Kind? = nil) -> [String]
```

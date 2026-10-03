# Sheets and Detents

Configure sheets and covers, then control them while they're on screen.

## Choosing a style

``PresentationStyle`` describes how a route or flow is shown:

```swift
present(.info, as: .sheet)                                        // a large sheet
present(.filters, as: .sheet(detents: [.medium, .large]))         // opens at medium
present(.compose, as: .sheet(detents: [.large], isInteractiveDismissDisabled: true))
present(.paywall, as: .fullScreenCover)
present(.photo(id), as: .fullScreenCover(embedsInNavigationStack: false))   // chromeless
```

### Detents

`detents` is ordered, and the sheet opens at the first one. Any `PresentationDetent` works:

```swift
.sheet(detents: [.medium, .large])
.sheet(detents: [.fraction(0.3), .fraction(0.6)])
.sheet(detents: [.height(240)])
.sheet(detents: [.custom(CompactDetent.self), .large])
.sheet(detents: [.medium, .large], initialDetent: .large)   // open somewhere other than the first; must be in detents
```

A custom detent is a `CustomPresentationDetent`:

```swift
struct CompactDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        max(160, context.maxDetentValue * 0.2)
    }
}
```

### Other options

- `dragIndicator`: show or hide the grabber.
- `backgroundInteraction`: let people use the screen behind the sheet, for example `.enabled(upThrough: .medium)` for a map-style sheet.
- `cornerRadius`: override the sheet's corners.
- `isInteractiveDismissDisabled`: start with swipe-to-dismiss blocked.
- `embedsInNavigationStack`: on by default, which gives the content a navigation bar for its title and toolbar. Turn it off for content that draws its own chrome.

Any other presentation modifier (`presentationBackground`, `presentationContentInteraction`, `presentationCompactAdaptation`) goes on the presented screen's own view, as usual in SwiftUI.

## Controlling a sheet that's on screen

A ``Presentation`` is observable, and its detent and dismiss lock are writable:

```swift
// From the coordinator that presented it:
presented?.selectedDetent = .large
presented?.isInteractiveDismissDisabled = true

// From inside a presented flow, about the sheet it lives in:
enclosingPresentation?.isInteractiveDismissDisabled = hasUnsavedChanges
```

`selectedDetent` is two-way: it follows the user's drags, and setting it moves the sheet.

### Locking dismissal while editing

A common pattern: block swipe-to-dismiss while a form has changes, and ask before discarding.

```swift
// In the editor's view model
var text = "" {
    didSet { navigation.setDismissLocked(!text.isEmpty) }
}

// In the coordinator that presented the editor
func setDismissLocked(_ isLocked: Bool) {
    presented?.isInteractiveDismissDisabled = isLocked
}
```

## Stacking and replacing

- Sheets stack: a flow inside a sheet can present another flow.
- ``Coordinator/dismissPresented()`` closes what a stack is presenting, together with anything on top of it.
- ``Coordinator/dismissAll()`` clears every sheet and cover in the presentation tree.
- Presenting while something is already presented replaces it. The replacement waits until the first one has finished animating out.
- When a flow finishes, the sheets it presented go with it.

## Zoom

Sheets and covers can grow out of a tapped view. See <doc:ZoomTransitions>.

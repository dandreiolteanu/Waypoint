# Zoom Transitions

Grow a pushed or presented screen out of the view that was tapped, and shrink it back on the way out.

## Two halves, one id

Mark the source view with `transitionSource(id:)`, and navigate with ``ScreenTransition/zoom(sourceID:)`` using the same id:

```swift
// The view the user taps
PhotoThumbnail(photo)
    .transitionSource(id: photo.id)
    .onTapGesture { viewModel.open(photo) }

// The coordinator
func open(_ photo: Photo) {
    push(.photo(photo.id), transition: .zoom(sourceID: photo.id))
}
```

It works the same for sheets and covers:

```swift
present(.viewer(photo.id), as: .fullScreenCover(embedsInNavigationStack: false), transition: .zoom(sourceID: photo.id))
present(.card(card.id), as: .sheet, transition: .zoom(sourceID: card.id))
```

On the way back, the screen shrinks into its source. That includes interactive swipe-back, and the swipe-down that iOS adds to zoomed screens.

## Choosing ids

The id only has to match within one stack. When the same item appears in several places on one screen, give each place its own id, or the zoom can come from the wrong one:

```swift
enum ZoomSource: Hashable {
    case grid(Photo.ID)
    case related(parent: Photo.ID, photo: Photo.ID)
}

PhotoThumbnail(photo).transitionSource(id: ZoomSource.grid(photo.id))
push(.photo(photo.id), transition: .zoom(sourceID: ZoomSource.grid(photo.id)))
```

## How it works

Each ``NavigationHost`` provides a namespace to every screen in its stack. Waypoint applies the zoom to the pushed screen, or to the whole presented content (navigation stack included, which the system requires).

The source and the navigation must belong to the same host: the screen that marks the source must be in the same stack as the coordinator that pushes or presents. That's the natural setup, a screen's view model calling its own coordinator, with one exception. A screen shown with ``Routing/present(_:as:transition:)`` lives in the sheet's stack, but navigates through the presenter's coordinator, so a zoom from inside it can't find its source. Present a flow when the sheet needs to zoom.

## Availability

Zoom transitions need iOS 18. On iOS 17 and on macOS, ``ScreenTransition/zoom(sourceID:)`` falls back to the default animation, so you can use it unconditionally.

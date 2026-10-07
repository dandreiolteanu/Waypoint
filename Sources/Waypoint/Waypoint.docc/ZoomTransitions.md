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

An id only has to be unique on one screen. Waypoint scopes each source to the screen it's on and zooms from the top screen, so the same screen pushed twice (a photo, then a related photo, then the first photo again) can reuse its ids. When the same item appears in several places on one screen, give each place its own id, or the zoom can come from the wrong one:

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

## When it falls back

Waypoint uses the default animation instead of a zoom when the zoom couldn't run cleanly:

- No view on the top screen is marked with the id, or it's off screen.
- The top screen is still animating in, for example on a second fast tap. UIKit can't morph from a view that's leaving the window.
- This stack is covered by a sheet.

In debug builds, Waypoint logs why.

## Availability

Zoom transitions need iOS 18. On iOS 17 and on macOS, ``ScreenTransition/zoom(sourceID:)`` falls back to the default animation, so you can use it unconditionally.

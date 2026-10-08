# Working on Waypoint

Waypoint is a coordinator library for SwiftUI: Swift 6, iOS 18+ and macOS 15+, no dependencies. This file is for changing the library itself. To *use* Waypoint in an app, read the skill in `skills/navigating-with-waypoint/` instead.

## Layout

| Path | What's there |
| --- | --- |
| `Sources/Waypoint/Core` | `Coordinator`, `Navigator`, `StackEntry` (screens and tokens), `Presentation`, styles and transitions |
| `Sources/Waypoint/Views` | The SwiftUI side: `NavigationHost`, `TabHost`, zoom and popover sources, `PresentationCompletionProbe` |
| `Sources/Waypoint/Containers` | `TabNavigator`, `SplitNavigator` |
| `Sources/Waypoint/Results`, `Alerts`, `Diagnostics` | Awaited navigation and `Callback`, `confirm` / `alert`, `LifetimeTracker` |
| `Sources/Waypoint/Waypoint.docc` | DocC articles |
| `Tests/WaypointTests` | Swift Testing suites; `DocumentationExamplesTests` compiles the doc samples; `PerformanceTests` are XCTest benchmarks |
| `Example` | The example app (XcodeGen, `project.yml`) and its UI tests |
| `skills/navigating-with-waypoint` | The agent skill for apps that use Waypoint (symlinked into `.claude/skills`) |

## Commands

```bash
swift build
swift test --skip PerformanceTests   # fast loop, about a second
swift test                           # everything, including benchmarks and the linear-scaling check

# DocC, must stay at zero warnings
xcodebuild docbuild -scheme Waypoint -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/waypoint-docs

# UI tests (40+ flows, about 15 minutes per device)
xcodebuild test -project Example/WaypointExample.xcodeproj -scheme WaypointExample \
  -destination 'platform=iOS Simulator,id=<udid>'
```

- Get a udid from `xcrun simctl list devices available`; names can match several runtimes.
- Narrow UI runs with `-only-testing:WaypointExampleUITests/<Class>/<test>`.
- Run one `xcodebuild test` at a time. Parallel runs on the same machine time out.
- Run `xcodegen generate` in `Example/` only after editing `project.yml`.

## Invariants

Each of these fixes a real SwiftUI retention bug or race. Keep them when you change the code around them.

- **Strong references only point down the tree:** navigator → entries → screen views → coordinators and view models. Coordinators hold their navigator weakly, and views hold navigators and tab navigators weakly. `tearDown()` empties a tree.
- **SwiftUI's path holds `EntryToken`s, never views or coordinators.** `NavigationStack` keeps the last popped path element alive, so a removed screen drops its view on `onDisappear`, with a fallback timer.
- **Presentations are serialized.** A presentation that starts while another is dismissing waits for `onDismiss`. A presentation that starts from a sheet still animating in waits for that sheet's `viewDidAppear`, which `PresentationCompletionProbe` reports. Without this, SwiftUI drops the presentation silently.
- **Awaits resume exactly once**, after the whole closing group is off screen: removed screens plus the ending flow's sheets. Use one shared closing group per change; registering per entry was quadratic.
- **Zoom and popover source ids are scoped to their screen** (`ScopedSourceID`, set by `ScreenHost` through `\.screenScope`). A zoom runs only from a registered source on the top screen, once that screen has settled and no sheet covers the stack; otherwise it falls back to `.automatic`. Without this, a screen pushed twice crashes UIKit with "Cannot morph from a view that is not in the hierarchy".
- **`Navigator.hasUserInterface`** is false in unit tests, so the timing gates above are skipped there. Tests that cover the gates set it to `true` and reset it with `defer`.

## When you change something

- **Behavior:** add a unit test (GIVEN / WHEN / THEN comments, like the existing suites). If it involves timing, retention or the system UI, add or extend a UI test too. UI tests read the lifetime overlay before and after a flow and fail with the names of whatever is still alive.
- **Public API:** update its doc comment, the DocC article that covers it, the samples in `DocumentationExamplesTests`, the README cheat sheet, and the skill (`SKILL.md` plus `references/api.md`).
- **Something users can trip over:** add it to `Troubleshooting.md` and the skill's `references/troubleshooting.md`.
- **Example app:** add an `accessibilityIdentifier` to anything a UI test taps. The `LaunchOptions` switches are `-signedIn`, `-hideLifetimeOverlay` and `-simulateDoubleTap`.

Before you call a change done: `swift test` passes, DocC builds with no warnings, and the UI tests that touch the change pass on iOS 18, the latest iOS, and an iPad.

## Style

- Swift 6 strict concurrency. Navigation types are `@MainActor`, and result values are `Sendable`.
- `final` classes (except `Coordinator`, which apps subclass), explicit `private` on members (not `private extension`), and no force unwraps in library code.
- Comment only what a reader would otherwise get wrong. Public API gets a doc comment with a short example where it helps.
- Docs prose avoids em dashes and `--` as punctuation.
- Debug diagnostics go through `waypointLog`, inside `#if DEBUG`, and start with "Waypoint:".

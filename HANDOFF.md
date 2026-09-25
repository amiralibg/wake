You're continuing work on **Wake**, a macOS browser I'm building with you, one step at a time. Read this whole brief first, then look at the code before changing anything.

## Project
- Path: `/Users/amiralibg/Programming/Git/wake`; public repo at https://github.com/amiralibg/wake (branch `main`)
- Swift 6 (strict concurrency), SwiftUI plus AppKit where needed, WKWebView, SwiftData. Deployment target macOS 14; Liquid Glass (`glassEffect`) on macOS 26 through `glassSurface()`, with fallbacks. No Chromium or Electron.
- The project is generated with **XcodeGen** from `project.yml`; the `.xcodeproj` is gitignored. After adding files, run:
  `xcodegen generate && xcodebuild -project Wake.xcodeproj -scheme Wake -configuration Debug -derivedDataPath build/DerivedData build`
- Run it with `open build/DerivedData/Build/Products/Debug/Wake.app` (sandboxed; bundle id `app.wake.Wake`).
- Data: SwiftData store at `~/Library/Containers/app.wake.Wake/Data/Library/Application Support/default.store`; preferences in that container's `Library/Preferences/app.wake.Wake.plist`.
- Design reference (a Design artifact): https://claude.ai/artifact/Wbk49Hdb9wE5Xpw1ZgzZBR. Screens: Reading, Deck open, Developer mode, Settings, Moments. Read it with the Artifact tool (`read`, `path: project/<Name>.dc.html`).

## Code conventions
- One feature per folder under `Wake/Features/` (Appearance, Apps, Deck, Developer, Glass, History, Live, Moments, Palette, PopOut, Settings, Shell, Threads, Toolbar, Trail, Web, Zen), plus `Wake/App` and `Wake/Support`. Keep views small and files focused.
- `@MainActor @Observable` models. Settings are injected through the environment: `AppearanceSettings`, `DeckSettings`, and `DeveloperSettings.shared` / `BrowsingSettings.shared` (shared because page callbacks read them).
- Animations come from `Support/Motion.swift` (`.trail`, `.deck`, `.chrome`, `.hover`): quick, well-damped springs.
- Comments explain why, and every macOS/WebKit limitation is called out in a doc comment and reported to me, never worked around silently.
- Keep builds free of errors and warnings. Check UI changes on screen with computer-use, and fix what you see.

## Architecture in brief
- `BrowserModel` (one per window) owns the active `BrowserThread` (with its `TrailModel` of `BrowserPage` columns), up to 4 background threads kept alive, `PaletteModel`, `PinnedAppsModel`, and the overlay state: Deck open or peeking, palette, settings, Zen, app capsule.
- `BrowserPage` wraps a WKWebView: KVO state, link interception, popups, page state (media playing, unsaved input), developer mode, JSON viewer, scroll sync. `BrowserPage(devToolsFor:)` makes a DevTools column; `isEphemeral` columns aren't saved.
- Injected JavaScript runs in `WKContentWorld.defaultClient` (`Web/WebScripts.swift`): link interception, horizontal-scroll probe, page state, scroll sync. Developer hooks run in the `.page` world (`Developer/DevScripts.swift`) and are only added in developer mode.
- `ThreadStore.shared` handles SwiftData: `ThreadRecord`/`ColumnRecord`, `VisitRecord`, `PinnedAppRecord`, which window owns which thread, and debounced saves (flushed when the app quits).
- `TrailGeometry`: a lone column always fills the stage; with more, `columnsPerScreen` (Balanced = 2) share it and the rest scroll. Each column edge (`ColumnEdgeHandle` in `TrailView`) resizes only that column: its neighbours slide and the trail scrolls, and `TrailModel.restingOffset` keeps the trail where the resize left it until focus moves. A page with DevTools or a device preview beside it takes the rest of the stage. A focused page and its companions stay in view together.
- DevTools open at ~40% (min 480pt) and remember the last dragged width (`devtools.widthFraction`). Responsive previews are `DevicePreviewColumn`s: a `DeviceFrame` (preset from `DevicePreset`, rotation) laid out at the exact CSS size and scaled to fit with `pageZoom`; phones get a mobile user agent.
- Menu commands resolve the window through `BrowserModel.active` (key/main/front window) because `@FocusedValue` can be nil while a WKWebView is first responder. ⌘W → `BrowserModel.closeCommand()` (overlay → app → column → window).
- The Deck (`Deck/DeckLayer`) is hidden → peek (a content-sized glass island raised from the bottom edge) → open (⌘K: frosted page, search palette, fan, waterline island). Heat and sinking live in `DeckBuilder`; thumbnails in `ThumbnailStore`.
- `Support/WindowEdgeMonitor` detects the pointer at window edges from window-level mouse-moved events: the bottom raises the Deck, and in Zen the top shows the toolbar and the left shows the capsule. SwiftUI hover strips don't work there because macOS keeps the edge for its resize cursor.
- `Support/EscapeKeyMonitor` closes overlays on Esc even when a web view has focus.
- Moments (`Features/Moments`): `MomentRecord` (SwiftData, same store) + `MomentStore.shared`; `MomentScripts` capture/restore (restore finds the selection with `window.find` and highlights it with the CSS Custom Highlight API); `MomentWatcher` re-checks saved pages in an off-screen WKWebView every 12h while Wake runs and describes changes with `MomentDiff`; `MomentRules` handles resurfacing, fading (30 days) and auto-archive (45 days). UI: `SaveMomentIsland` (after ⌘D), `MomentsLibrary` (⌥⌘B, full-window, sidebar + grid/timeline + search), `ResolvedThreadDetail`. Snapshots live in `ThumbnailStore.moments`.
- Live chips (`Features/Live`): `LiveScripts` (Wake world, part of `WebScripts.baseScript`) reports media time, structured-data price, GitHub PR CI and "updated while unfocused" as `{type:'live'}` messages into `BrowserPage.live` (`LiveState`, plus main-frame HTTP status). `LiveChipProvider`s in `LiveChips.providers` (priority order) turn that into `LiveChip`s: status, CI, console errors, price (vs first seen, `PriceWatch`), unread (title), media, updated. Deck cards show one (`DeckItem.Chip.live`); trail chips get a dot. Sinking protection is `DeckItem.afloat` (playing/unsaved), independent of chips.
- Pop Out (`Features/PopOut`): ⌥⌘O or the toolbar button starts `PopOutScripts.picker` in the page (hover, ↑/↓ to widen/narrow, click, Esc). `PopOutController` opens a `PopOutPanel` (non-activating, floating, borderless NSPanel) whose `PopOut` model runs its own WKWebView of the page, laid out at the source's width and clipped to the element by `PopOutScripts.isolate` (hides fixed/sticky chrome, pins the element to the viewport top, reports size changes so the panel follows). Links open in the trail; pin = all Spaces + full-screen apps; ⌘W closes the key panel.

## Status
- Steps 1–9 are built:
  1. Shell, glass, toolbar, ⌘K
  2. Trail
  3. Threads + SwiftData
  4. Deck
  5. App capsule
  6. Settings, as an in-window panel with a live preview
  7. Developer mode: ports, environments, DevTools column, open-in-editor with source maps, Copy for AI, network replay/cURL/mock, responsive preview, component inspector, JSON viewer, git branch, HMR
  8. Moments (plus the step 6/7 feedback round: per-column resizing, ⌘W, shortcuts, slimmer capsule, wider DevTools, real device previews)
  9. Pop Out, live state chips, background change detection (Moments watcher + "Updated" chip)
- **Next:** I'm testing steps 8 and 9 and will send feedback. Every step in the original spec is now built.

## My design taste (from feedback so far)
- Resizing a column never resizes its neighbours: it grows or shrinks on its own and the trail scrolls, like windows side by side.
- ⌘W closes the column, never the window while there is one.
- Apple quality. Chrome floats as glass *islands*, never full-width bars with hard edges.
- No permanent chrome over the pages: things appear on demand (edges, hover, shortcuts).
- Pages are clean, headerless rounded cards, all the same size; focus shows through shadow only.
- The address bar sits in the true centre of the toolbar. Fast, smooth animations. Resizing should feel like a split view.
- When I say "window" about page content, I usually mean a trail column.

## Testing notes (computer-use)
- Background `app_*` clicks don't reach SwiftUI tap gestures or an inactive window; make controls real Buttons (then AXPress works) or use full-screen control. Setting "\n" through accessibility doesn't submit a field; click the row instead.
- The tool seems to reserve Esc, so Esc can't be tested with it.
- Pointer-hover and edge features need full-screen control and `mouse_move`; find the window's real edge first.
- The first screenshot after an action is often mid-animation; take another before judging.
- If Wake has no window after relaunch, use the Window menu or File → New Window; `AppDelegate` also opens one automatically.

Start by confirming the build works, then ask me for my step 6/7 feedback (or apply it if I've included it below).

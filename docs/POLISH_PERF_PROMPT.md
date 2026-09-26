# Review, polish and performance pass

Paste everything below the line into a new Claude Code session opened on this repo.

---

You're doing a review, polish and performance pass on **Wake**, my native macOS browser (SwiftUI + AppKit + WKWebView, Swift 6 strict concurrency, macOS 14 target). The goal is an app that feels finished and is as light as a browser can be, **especially in memory**. Read `HANDOFF.md` first, then `docs/QA_PROMPT.md` (a list of unverified areas and known bugs, which this pass also covers). Read the code for each area before changing it.

Build and run:

```bash
xcodegen generate && xcodebuild -project Wake.xcodeproj -scheme Wake -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Wake.app
```

Measure in **Release** (`-configuration Release`); Debug numbers mislead. Test page: `python3 -m http.server 8765 -d Scripts/devtools-test-site`.

## Rules

- **Measure before and after** every performance change: the same scenario, the same numbers, in a table. Don't claim a win you didn't measure.
- **Report before large refactors.** Anything that changes architecture (how threads, columns or web views are owned, or suspended) needs my go-ahead. Show me the numbers and the plan first.
- **Report every macOS/WebKit limitation** in a doc comment and to me. Never work around one silently.
- Keep builds free of errors and warnings.
- Check UI in the running app with computer use (full-screen control for menus, typing and hover). Take a second screenshot before judging anything that animates.
- JavaScript inside non-raw Swift strings goes through Swift's escapes. Use raw `#"""` strings and `node --check` injected scripts.
- Render shader changes offline to a PNG and check brightness before showing me.
- **Design taste:** Apple quality; glass islands, no permanent chrome; fast, well-damped springs from `Support/Motion.swift`; one accent colour; restrained.
- Don't commit. At the end, show me the diff summary and ask.

## 1. Memory and CPU: measure first

Build a repeatable benchmark and record a baseline. Numbers come from Activity Monitor (Memory, Energy Impact, GPU), `footprint`, `vmmap --summary`, `heap`, `leaks`, and Instruments (Allocations, Leaks, Time Profiler, Animation Hitches).

Remember that WebKit runs pages in separate `com.apple.WebKit.WebContent` processes, so **sum Wake plus all its WebContent and Networking processes**. Report a per-process breakdown (for example, `ps -axo pid,rss,command | grep -i webkit`).

Scenarios:
1. **Cold launch:** measure 10 s after launch with one blank thread.
2. **Browsing:** one thread with 6 columns of real sites (Wikipedia, GitHub, YouTube with a paused video, a Google Doc or Notion page, a news site, `localhost:8765`).
3. **Many threads:** 6 threads of 4 columns each, switching between them via ⌘K.
4. **After closing:** close everything back to one column and wait 30 s. Does memory come back down? It should; anything that stays is a leak.
5. **Idle:** the window in the background for 2 minutes. CPU and energy should be near zero.
6. **Deck and Moments:** open the Deck 10 times, open Moments, History (⌘Y) with 20k+ imported pages, and scroll.
7. **DevTools:** open on the test page, cycle through all panes, close. Repeat 5 times and check memory returns each time.
8. **Onboarding shader:** GPU% and energy while the tour is showing.

## 2. Memory: likely wins (verify each with numbers)

- **Background threads:** `BrowserModel.maxBackgroundThreads = 4` keeps every column's WKWebView alive for up to four other threads. Measure what each costs. Options, from least to most invasive:
  - Pause media and timers in hidden pages.
  - Lower the cap.
  - Unload a hidden thread's web views after a delay, keeping its URL, scroll position and a thumbnail, and reload them on return. That's a Safari-style tab discard; it's an architecture change, so ask me first.
- **Offscreen trail columns:** columns scrolled out of view keep running at full speed. Look at WebKit's options (for example, occluding the view and letting WebKit throttle it, or pausing media), and report what WebKit does and doesn't allow.
- **Memory pressure:** nothing listens today. Add a `DispatchSource.makeMemoryPressureSource` handler that:
  - clears `ThumbnailStore`'s decoded cache and `FaviconCache`;
  - drops hidden threads' web views, if you've added discarding;
  - releases DevTools session data for closed columns.
- **`ThumbnailStore`:** its decoded `cache` is an unbounded `[UUID: NSImage]`. Bound it (`NSCache` with a cost limit, keyed by pixel bytes), decode at display size, and check how often captures run and what each one costs.
- **Retain cycles:** closures capturing `self` or a page in `BrowserPage` callbacks (`onDidFinish`, `onRestored`, `didCreatePage`, script message handlers; `WKUserContentController` retains its handlers), `DevToolsSession`, `PopOut`, `MomentWatcher`, `LocalStorageWriter`, and `Task`s that outlive their view. Confirm with Instruments Leaks and by checking that `BrowserPage`/`WKWebView` deinit after a column closes (add a temporary `deinit` log).
- **Offscreen web views:** `MomentWatcher` (every 12 h), `PopOut` panels and the importer's `LocalStorageWriter` each create a WKWebView. Make sure each one is torn down when done, and that the watcher uses one view at a time.
- **SwiftData:** `HistoryStore.visits(matching:)` fetches up to 5,000 records to filter addresses in memory. Check the cost with 25k+ pages, and page it or add an indexed host/URL-string field if needed. `visitCount` and `searchCount` run a `fetchCount` on every History redraw, so cache them.
- **DevTools:** the Network log, console entries and resource arrays grow without bound on long-lived pages. Cap them (a ring buffer, e.g. the last 1,000) and say so in the UI.

## 3. CPU, GPU and smoothness

- **SwiftUI invalidation:** in `TrailView`, `DeckLayer`, the toolbar and `ThreadIsland`, use Instruments' SwiftUI template or `Self._printChanges()` temporarily. Find views that re-render on every scroll, progress or title tick, and narrow what they observe.
- **Animation hitches:** check column resizing (it should track the pointer every frame), trail scrolling, the Deck opening, and Zen reveals.
- **Onboarding shader:** it's capped at 60 fps and drawn at 1×. Measure its GPU cost, and pause it when the window is occluded or the tour isn't visible.
- **Timers and polling:**
  - The dev-server port scanner backs off to 30 s when inactive, so confirm that.
  - `NetworkPane` polls resources every second while visible; make sure it stops when hidden.
  - Check the Performance pane's FPS sampling, live chips and `MomentWatcher`.
  - Nothing should wake the CPU while the app is idle and in the background.
- **Launch time:** measure time to first window, and move work off the main thread or defer it (SwiftData open, history repair, Sparkle start, favicon loads).

## 4. Review and polish

- **Code review:** go through the round-10 and round-11 code with fresh eyes: `Features/Developer`, `History`, `Import`, `Updates`, `Onboarding`, `Toolbar`, `Threads/ThreadIsland`. Look for correctness bugs, main-thread blocking (file and SQLite I/O, `JSONSerialization` of big payloads), error paths that fail silently, and duplicated code worth consolidating.
- **UI polish at every window size:** from very narrow (~700 pt) to full screen on a large display.
  - Check the toolbar islands, DevTools tabs and panes, Settings, History, the Import sheet, the Deck, and Moments.
  - Nothing may overlap, clip or truncate badly.
  - Check light and dark mode, each accent colour, and Reduce Motion / Reduce Transparency.
- **Known polish items:**
  - Engine favicons are slow (Ecosia falls back to its monogram): bundle small icons.
  - The Network waterfall squashes page-load requests when a much later request exists.
  - Sources pretty-print leaves the view scrolled sideways, and its formatter output is rough.
  - After Edit as HTML, the new element should be selected.
- **Accessibility:** VoiceOver labels on icon-only buttons, keyboard reachability of every control, and focus rings.
- Work through the unchecked items in `docs/QA_PROMPT.md` as part of this pass.

## Report

End with:
1. **The benchmark table:** baseline vs after, for every scenario, including total memory across Wake and its WebKit processes.
2. **Each fix:** what you changed, with its measured effect.
3. **Proposed larger changes** (for example, tab discarding) with expected savings, for me to approve.
4. **Every WebKit/macOS limitation** you hit.
5. **The diff summary.**

Then ask before committing.

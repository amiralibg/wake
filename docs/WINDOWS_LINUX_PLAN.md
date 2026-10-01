# Wake for Windows and Linux: plan

Status: Phase 1 done (2026-09-28). Phase 0 next. Branch `windows-linux` (local only for now).

Read `HANDOFF.md` first for how the macOS app is built. This plan covers a second app for Windows and Linux that shares Wake's design, data model and page-side JavaScript with the Mac app. The macOS app stays Swift and keeps shipping from `main`.

## Why a second app, not a port

The Mac app is ~20k lines of Swift on Apple-only frameworks: SwiftUI (79 files), AppKit (33), WebKit (19), SwiftData, Metal, Sparkle, Keychain. Swift compiles on Windows and Linux, but none of those frameworks do. What carries over:

- The injected JavaScript (`Wake/Features/*/*Scripts.swift`, `WebScripts.swift`, `LiveScripts.swift`): link interception, page state, scroll sync, Moments capture/restore, Pop Out picker and isolation, live chips, developer hooks, the DevTools page library, overlays and the JSON viewer.
- Pure logic, rewritten in the new language: `TrailGeometry`, `DeckBuilder`/`DeckLayout`, `MomentRules`, `MomentDiff`, `URLInput`, `SearchEngine`/`SearchQuery`, `LiveChipProvider`s, `ColumnMode` key handling.
- The data model (`ThreadRecord`, `ColumnRecord`, `VisitRecord`, `SearchRecord`, `PinnedAppRecord`, `MomentRecord`).
- The design (see the Design artifact linked in `HANDOFF.md`).

## Decisions

| Area | Choice | Why |
|---|---|---|
| Host language | Rust | One codebase for both OSes, small binaries, first-class bindings to both web engines. |
| Web engine, Linux | WebKitGTK (6.0 API, GTK4) | Same engine family as the Mac app: the injected JS runs nearly unchanged, and Web Inspector is the same one. |
| Web engine, Windows | WebView2 (Evergreen runtime) | Ships with Windows 10/11. It is Chromium, not Electron; nothing else is embeddable in production. |
| Webview layer | `wry` + `tao` (Tauri's crates), or Tauri 2 with the `unstable` multiwebview flag | Decided by the Phase 0 spike. |
| Chrome UI | TypeScript + React (Vite) rendered in webviews | Toolbar islands, Deck, palette, settings, libraries, onboarding. |
| Storage | SQLite via `rusqlite` | Same tables as the SwiftData models, so sync between platforms stays possible. |
| Updates | Tauri updater or WinSparkle on Windows; AppImage (+ AppImageUpdate) and Flatpak on Linux | WinSparkle reads Sparkle's appcast format. |
| Window material | Mica/Acrylic on Windows 11 (`window-vibrancy`); plain translucent surfaces on Linux | No reliable blur behind windows on Linux. |

Not chosen: Electron and Qt WebEngine (both bundle Chromium), Swift on Windows (Arc's route, years of tooling work), separate native apps per OS (three codebases).

## Target layout

```
Wake/                 macOS app (unchanged, Swift)
shared/
  scripts/            page-side JS used by all three apps
  schema/             data model spec + SQL migrations
desktop/
  host/               Rust: windows, webviews, storage, IPC, updater
  ui/                 TypeScript/React chrome, loaded into chrome webviews
```

## Phases

Each phase ends with something that runs. Don't start the next one until the gate passes.

### Phase 0: spike (decides the webview layer)

Throwaway prototype in `desktop/spike/`. On Linux first, then Windows:

- One window, three page webviews side by side, scrolled sideways as a trail, each resizable on its own edge (neighbours slide, they don't squeeze; see `TrailGeometry`).
- A transparent chrome webview floating over the pages (the toolbar island), with clicks passing through where it's transparent.
- ⇧ + mouse wheel over a page moves between columns (the page webview gets the event first, so this needs injected JS that posts back to the host).
- A snapshot of a page webview to a PNG (for Deck thumbnails).
- Memory with 10 columns open, and hiding off-stage columns to see if the engine throttles them (the Mac app does this with `webView.isHidden`).

**Gate:** smooth scrolling and resizing at 60 fps on both OSes, the overlay works, and a snapshot is possible. Write down the result and the chosen layer (wry directly vs Tauri) at the bottom of this file.

Known risks: Tauri's multiwebview is still behind `unstable` with open positioning/resizing bugs (tauri-apps/tauri#10420, #11376). If the overlay doesn't work, put the Deck and palette in separate transparent borderless windows above the main one.

### Phase 1: share what already exists (in this repo, Mac app included)

- Move every injected script out of Swift strings into `shared/scripts/*.js`. The Mac app loads them from its bundle (add them as resources in `project.yml`) and fills parameters (handler names, limits) through a small prelude object instead of Swift string interpolation. This also ends the `\n` escaping problem with non-raw strings.
- Add a bridge shim so the scripts don't call `window.webkit.messageHandlers.X.postMessage` directly: `__wake.post(channel, message)`. It maps to `window.webkit.messageHandlers` on WebKit (macOS and WebKitGTK) and to `window.chrome.webview.postMessage` with a channel field on WebView2.
- Write `shared/schema/`: the tables and fields of each SwiftData model, as SQL, with the Mac field names.
- Syntax-check every script in CI (`node --check`).

**Gate:** the Mac app builds without warnings and behaves as before (links, scroll sync, Moments, Pop Out, live chips, DevTools); no JS left in Swift strings except tiny one-liners.

**Done (2026-09-28).** 23 scripts in `shared/scripts`, loaded by `Wake/Support/SharedScript.swift`; format in `shared/README.md`. The prelude became function parameters rather than a global: each file is a function body of `(wake, params)`, so page-world scripts don't add a `__wake` global to the page. `Scripts/script-tests/run.sh` runs all of them in a WKWebView through `SharedScript` and checks what they post and return (35 checks; scroll-sync's report is skipped when the test window isn't visible, since WebKit pauses requestAnimationFrame). `moment-restore.js` gained a text-walk fallback for engines without `window.find` (Chromium). Not yet checked by hand in the running app with computer use.

Note: WebKit content worlds. The Mac app runs Wake's scripts in `WKContentWorld.defaultClient` and developer hooks in `.page`. WebKitGTK has script worlds (`webkit_user_script_new_for_world`). WebView2 has no isolated worlds for injected scripts, so on Windows Wake's scripts share the page's world: keep their globals namespaced under `__wake` and don't trust page-set values.

### Phase 2: MVP browser

- `desktop/host`: window, trail of page webviews, navigation, popups and new-window requests, per-column state (URL, title, favicon, loading, can go back/forward).
- `desktop/ui`: address capsule, trail strip, ⌘K/Ctrl+K palette with search engines and history suggestions, settings (General, Search, Appearance).
- Threads: several threads per window, saved and restored with column widths and focus.
- History and searches (`SearchQuery` recognition of results-page URLs).
- Shortcuts: Ctrl in place of ⌘ on both OSes; column mode (the Mac's ⌃W would become Ctrl+W, which means close on Windows and Linux, so pick another key and keep it configurable).
- Packaging: MSI/NSIS for Windows, AppImage for Linux, built in GitHub Actions on push (like `build.yml`).

**Gate:** daily-drivable for simple browsing on both OSes.

### Phase 3: the Wake features

In this order, each one behind its own PR into this branch:

1. The Deck: live cards, heat and sinking (`DeckBuilder`), thumbnails via `CapturePreviewAsync` (WebView2) and `webkit_web_view_get_snapshot` (WebKitGTK).
2. Moments: ⌘D/Ctrl+D capture, restore, library, resurfacing and fading, the background watcher (an offscreen webview every 12 h).
3. Live chips: media, price, CI, unread, HTTP status, updated.
4. Pop Out: an always-on-top borderless window with its own webview, clipped by `isolate`.
5. Pinned apps capsule with unread badges.
6. Zen mode and edge-reveal (pointer at window edges).
7. Onboarding: port the Metal water shader to WebGL/GLSL in the UI.

### Phase 4: developer mode

- The DevTools column reuses `shared/scripts` (the DevTools page library and dev hooks).
- On Windows, consider the Chrome DevTools Protocol (`CallDevToolsProtocolMethod`) for Network and Performance instead of in-page hooks: real timings, headers and bodies.
- "Open the full inspector": `OpenDevToolsWindow` on WebView2, `webkit_web_inspector_show` on WebKitGTK.
- Dev server scanning, open-in-editor with source maps, device previews, git branch, HMR status.

### Phase 5: import and updates

- Import from other browsers. Profile paths differ per OS. Chromium cookies: DPAPI + AES-GCM on Windows, but Chrome 127+ uses app-bound encryption, which blocks reading its cookies from another app (import history and searches only, and say why). On Linux, the key comes from libsecret/KWallet, or the "peanuts" fallback. Firefox is the same SQLite everywhere.
- Auto-update signed with a key of its own; releases on the same `vX.Y.Z` tags, with one workflow per OS.
- Code signing on Windows (SmartScreen warns about unsigned installers), Flatpak on Flathub.

## Open questions

- README wording: "No Chromium, no Electron" becomes "no Electron" on Windows. Say it plainly on the download page.
- Minimum versions: Windows 10 or 11 only? Which WebKitGTK (distros ship 2.4x; Flatpak's GNOME runtime pins one)?
- Keyboard: ⌘ becomes Ctrl, so check every Mac shortcut for clashes with Windows/Linux conventions (Ctrl+W, Ctrl+D, Ctrl+K in some layouts).
- Sync between the Mac and desktop apps, later: the shared schema keeps it possible, but it isn't in scope.

## Progress

- [x] Host: window, shell webview, page webviews, IPC, SQLite, settings
- [x] UI: trail + geometry + resizing, page cards, snapshot cover
- [x] Toolbar, palette, search engines, suggestions
- [x] Threads + persistence, history + searches
- [x] Settings panel (all sections)
- [x] Deck, Moments (+ watcher), live chips
- [x] Pinned apps, Zen + edge reveal, column mode
- [x] Developer mode + DevTools column
- [x] Updates (host side; needs a signing key and release assets)
- [x] Pop Out window
- [x] Onboarding (WebGL water)
- [x] Import from other browsers (Chromium + Firefox families)
- [x] Packaging + CI (AppImage verified on a clean system; NSIS installer compiles)
- [x] Docs: desktop/README.md, shared/README.md, HANDOFF.md
- [ ] Run on real Windows (only cross-compiled so far) and on a Linux desktop with a GPU
- [x] First release: minisign key (secret + variable), then a tag (v0.3.0)
- [x] .deb and .rpm packages beside the AppImage

## Spike results

Phase 0 was folded into the real host instead of a throwaway spike (2026-09-28):

- **Layer: wry + tao directly**, not Tauri. wry 0.57 already has what Tauri's multiwebview would add (child webviews, popups with `window.opener` through `NewWindowResponse::Create`, back/forward, cookies, page-load events), and the native handles (`WebViewExtUnix::webview`, `WebViewExtWindows::controller`) cover the rest: script worlds, snapshots, key interception, progress.
- **Linux uses WebKitGTK 4.1 (GTK3)**, not 6.0: that is the API wry is built on.
- **No transparent overlay over pages.** The chrome is one full-window "shell" webview *under* the page webviews. When something must draw over pages (Deck, palette, menus, Zen toolbar), the covered pages are snapshotted and hidden, and the shell draws the snapshots in their place. WebView2 in windowed mode can't show a sibling webview through its transparent pixels, so a floating transparent chrome webview isn't portable.
- **App logic lives in the UI (TypeScript)**; the host is a thin service layer (webviews, storage, OS). See `desktop/README.md`.

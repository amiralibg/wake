# QA pass: find and fix bugs in Wake

Paste everything below the line into a new Claude Code session opened on this repo.

---

You're doing a QA pass on **Wake**, my native macOS browser (SwiftUI + AppKit + WKWebView, Swift 6 strict concurrency, macOS 14 target). Read `HANDOFF.md` first for the architecture and conventions, then read the code for each area before you test it.

Build and run:

```bash
xcodegen generate && xcodebuild -project Wake.xcodeproj -scheme Wake -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Wake.app
```

Test page for DevTools (developer mode turns on by itself for localhost):

```bash
python3 -m http.server 8765 -d Scripts/devtools-test-site
```

## How to work

- Test in the running app with computer use; don't assume. Background `app_*` tools can't open SwiftUI menus or send real keys, so ask for full-screen control. Take a second screenshot before judging anything that animates.
- For each area: read the code, test it, and fix every bug you find. Rebuild, then confirm the fix on screen.
- Keep builds free of errors and warnings.
- Report every macOS/WebKit limitation you hit in a doc comment and to me. Never work around one silently.
- JavaScript inside non-raw Swift strings goes through Swift's escapes (`\n` becomes a real newline). Use raw `#"""` strings, and syntax-check injected scripts after unescaping (`node --check`).
- Render shader changes offline to a PNG and check the brightness before showing me.
- Don't commit. At the end, show me the diff summary and ask.

## Already verified (spot-check only)

Console: Tab completion, ↑/↓ history, evaluation, level and text filters, Copy for AI, stack traces without Wake's frames. Elements: keyboard navigation, search, inline style, attributes, Edit as HTML (selects the new element), ⌫ removes a node (selects the next sibling), Computed filter and colour swatches (rgb and hex), Layout for inline elements, breadcrumbs. Sources: Pretty (no sideways scroll, cleaner formatter), inline scripts and styles numbered. Network: filter chips, search, mock, replay, cURL, HAR export, waterfall with idle gaps shortened. Performance: Web Vitals, FPS, page weight, audits on apple.com. Web Inspector (⌥⇧⌘I) stays docked while the column edge is dragged. ⌥⌘U, ⌥⌘P. Storage and the Tools menu. Custom search template (⌘K and Searches show "Custom"); engine cards at narrow widths. History with 25k+ pages: address and title search across all of it, context menu, empty state. Import sheet (Safari notice only without Full Disk Access). Toolbar from ~730 pt to full screen, with and without the dev island. Onboarding in a small window. Off-stage columns throttled; closed columns and discarded threads free their web views.

## Not verified yet

1. Open in Editor from Sources and Console (needs a linked folder and an editor).
2. Inspect Components on a React or Vue dev server.
3. Import cookies from Chrome, Dia or Helium: macOS asks for the "… Safe Storage" keychain item; only the user can answer. Then confirm a signed-in site stays signed in.
4. Import from Safari with Full Disk Access (history and cookies), and site storage imported twice without duplicates.
5. Browsers not installed here (Arc, Brave, Edge, Vivaldi, Opera): read `BrowserCatalog` against their real profile paths.
6. Updates: install v0.1.0, release v0.1.1, check Wake offers and installs it (ad-hoc signing, container access prompt).
7. Onboarding with Reduce Motion on; light mode, each accent colour and Reduce Transparency across the main screens.
8. A thread discarded after 10 minutes in real use: comes back with its columns and scroll positions.
9. The first click after typing: twice a button needed a second click right after editing a text field (the Mock sheet's Save, and a Search engine card after clearing the custom template). Not reproducible elsewhere.

## Report

End with a table (area · result · what you fixed · what's left), the list of limitations you hit, and the diff summary. Then ask before committing.

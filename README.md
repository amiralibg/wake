<p align="center"><img src="docs/icon.png" width="128" alt="Wake icon"></p>

<h1 align="center">Wake</h1>

<p align="center">A macOS browser where pages are columns in a trail, not tabs in a bar.</p>

Wake is a native macOS browser built with SwiftUI, AppKit and WebKit. No Chromium, no Electron.

## What's in it

- **The trail.** Links open as columns to the right, Niri-style. One column fills the window, two share it, more scroll. Each column resizes on its own edges without squeezing its neighbours.
- **Threads and the Deck.** Each window works on a thread of pages. ⌘K raises the Deck: every thread as a live card that floats by how recently you used it and sinks when you don't. Cards show one live chip each (a failing CI run, a price drop, media time, unread count, an HTTP error).
- **Moments.** ⌘D saves where you were on a page: scroll position, your selection and why you saved it. Opening a moment scrolls back and re-highlights. Moments resurface by date or when you're on their site. Wake checks saved pages in the background and tells you what changed. Moments you never open fade and archive themselves.
- **Pop Out.** Pick any part of a page and float it, live, in its own small always-on-top panel.
- **Apps.** Pin web apps to a slim capsule with unread badges.
- **Developer mode.** Turns on automatically for localhost: local dev servers found on common ports, and a DevTools column with Elements (live DOM tree, picker, styles, computed values, box model, attribute and HTML editing), Console (with a JavaScript prompt, `$0`, history and completion), Network (every resource with a waterfall, headers, payloads, timing, replay, cURL, mocks and HAR export), Sources, Storage (local and session storage, cookies, IndexedDB, caches, service workers) and Performance (Web Vitals, frame rate, page weight and an audit). One click opens WebKit's full Web Inspector, the one Safari uses, for the debugger and Timelines. Also: open-in-editor through source maps, device previews at real iPhone and iPad sizes, emulation (appearance, user agent, JavaScript and styles off), a component inspector, a JSON viewer, git branch and HMR status.
- **History and searches.** ⌘Y shows every page you visited, grouped by day; ⌥⌘Y shows what you searched for, from ⌘K or from any search engine's own box.
- **Bring your data.** File ▸ Import from Another Browser copies history, searches, cookies (so you stay signed in) and site storage from Chrome, Arc, Dia, Brave, Edge, Vivaldi, Opera, Helium, Firefox, Zen and Safari.
- **Search your way.** DuckDuckGo by default; Google, Brave, Bing, Ecosia, Startpage, Kagi, Perplexity, Yahoo or any URL with `%s`.
- **Welcome tour.** A first-launch tour over live water (a Metal shader with a paper boat and its wake) that sets your look and search engine. Settings ▸ General shows it again.
- **Zen, glass and settings.** Chrome floats as Liquid Glass islands on macOS 26 and appears only when you need it.

## Building

Requirements: macOS 14 or later to run; Xcode 26 or later (the macOS 26 SDK, for Liquid Glass) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
xcodebuild -project Wake.xcodeproj -scheme Wake -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Wake.app
```

The Xcode project is generated from `project.yml` and isn't checked in.

The app icon (a page leaving a wake of itself) is drawn in code; to regenerate it, run `swift Scripts/make-icon.swift`.

## Installing

Wake is in **beta** (every 0.x release): expect rough edges, and please report what you find in [Issues](https://github.com/amiralibg/wake/issues).

Download the latest `.dmg` from [Releases](https://github.com/amiralibg/wake/releases/latest). Wake checks for updates once a day (Wake ▸ Check for Updates… or Settings ▸ General) and installs them when you say so.

Until releases are signed with a Developer ID, macOS asks before opening a downloaded copy the first time: open **System Settings ▸ Privacy & Security** and choose **Open Anyway**.

## Releasing

Releases are built by `.github/workflows/release.yml` and published to GitHub Releases with a [Sparkle](https://sparkle-project.org) appcast, which installed copies read to update themselves.

One-time setup: add the update signing key as a repository secret named `SPARKLE_PRIVATE_KEY`. Its public half is `SPARKLE_PUBLIC_ED_KEY` in `project.yml`; a release signed with any other key is refused by installed copies, so keep the private key safe.

```bash
gh secret set SPARKLE_PRIVATE_KEY < ~/.wake-release/sparkle_private_key
```

To release, tag the commit and push the tag (or run the workflow from the Actions tab with a version):

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The workflow builds a Release app with that version, signs it, packages a `.zip` (for updates) and a `.dmg` (for downloads), signs the zip for Sparkle, writes release notes from the commits, and attaches `appcast.xml` to the release.

To sign with a Developer ID and notarize, also add `DEVELOPER_ID_CERTIFICATE` (a base64 `.p12`), `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID` and `APPLE_APP_PASSWORD`. Without them the app is signed ad hoc, which works but makes macOS ask before first launch.

## Layout

One feature per folder under `Wake/Features` (Trail, Deck, Threads, Moments, PopOut, Live, Developer, Apps, Settings, …), with app wiring in `Wake/App` and shared helpers in `Wake/Support`. `HANDOFF.md` describes the architecture in more detail.

## License

MIT. See [LICENSE](LICENSE).

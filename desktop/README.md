# Wake for Windows and Linux

The same browser as the macOS app (`Wake/`), with every feature: the trail, threads, the Deck, Moments, pinned apps, Zen, column mode, developer mode with the DevTools column, Pop Out, History and Searches, import from other browsers, onboarding, and self-updates. The plan and its progress are in `docs/WINDOWS_LINUX_PLAN.md`.

```
desktop/
  host/        Rust: windows, webviews, storage, the OS (wry + tao)
  ui/          TypeScript + React + MobX: the whole app (Vite)
  packaging/   icons, the Linux AppImage script, the Windows NSIS installer
  docker/      a Linux dev container: build, run under Xvfb, screenshot
shared/        page scripts and the data model, shared with the macOS app
```

## How it fits together

**The host is thin; the app is the UI.** The Swift models (`BrowserModel`, `TrailModel`, `ThreadStore`, `DeckBuilder`, `MomentStore`…) are ported to TypeScript classes in `ui/src/model`, observable with MobX. The host (`host/src`) does only what a web page can't: native windows and webviews, SQLite, files, HTTP without CORS, cookies, the clipboard, dialogs, reading other browsers' profiles, and updates.

**One shell webview per window, pages beside it.** Each window is borderless and filled by a *shell* webview that loads the UI from `wake://` (`http://wake.localhost` on WebView2, where custom schemes are served that way). Every column of the trail is a separate native webview, a child of the window, placed at the rectangle the UI computes (`layout`). On Linux the window's content is a `GtkOverlay`: the shell is its main child, and the pages live in a `GtkFixed` overlay above it that passes clicks through where there's no page.

**Nothing draws over a page.** A native webview can't be drawn over by another webview on either platform (WebView2 in windowed mode ignores transparency between siblings). When the UI needs to cover pages (the Deck, the palette, Settings, menus, the Zen toolbar, islands, onboarding), `BrowserModel.coversPages` turns true: the UI asks each visible page for a snapshot, hides the webviews, and draws the snapshots in their place. The page cards in `ui/src/ui/stage` are the same in both states, so the swap isn't visible.

**Page scripts** are the files in `shared/scripts` (see `shared/README.md`), embedded in the host. Wake's own scripts run in the WebKitGTK script world "wake", developer hooks in the page's world; WebView2 has no isolated worlds, so everything shares the page's world there.

## The protocol

The shell talks to the host with JSON through `window.ipc.postMessage` (`ui/src/host/host.ts`):

- **Commands** `{ cmd, req?, ...args }`. With a `req`, the host answers `window.__wakeHost.reply(req, ok, value)`, and `host.call()` resolves or rejects with it; without one (`host.send()`), nothing comes back.
- **Events** `window.__wakeHost.event(name, payload)`, received with `host.on(name, handler)`.

Commands (`host/src/commands.rs`):

| Group | Commands |
|---|---|
| Start | `ready` (window id, platform, version, settings, thread claims, folders) |
| Pages | `page.create`, `load`, `nav` (back/forward/reload/stop), `close`, `focus`, `exec`, `eval`, `run` (a shared script with params), `snapshot`, `zoom`, `userAgent`, `devHooks`, `javascript`, `inspector`, `devtools`, `devtoolsRun`, `cookies`, `setCookie`, `deleteCookie`, `clearSiteData`, `colorScheme`, `print`, `copySnapshot`, `loadAsOrigin` |
| Layout | `layout` (every visible page's frame; pages left out are hidden), `shell.focus` |
| Storage | `db.query`, `db.exec`, `db.batch` (SQLite, schema in `shared/schema`), `settings.set`, `file.write` / `read` / `copy` / `remove` / `exists` (inside the data folder) |
| Threads | `threads.claim`, `release`, `focusOwner`, `changed` (one thread is live in one window at a time), `broadcast` |
| Windows | `window.minimize`, `toggleMaximize`, `fullscreen`, `drag`, `resize`, `title`, `close`, `new`, `setSize`, `pin`, `focusID`, `emit`; `app.quit`; `keys.set` |
| OS | `open.external`, `open.reveal`, `clipboard.write` / `read`, `http.fetch`, `dialog.folder`, `dialog.save`, `git.branch`, `fs.exists`, `hash.sha256` |
| Data | `data.clearCache`, `data.clearAll` |
| Updates | `update.info`, `update.check`, `update.install` |
| Import | `import.profiles`, `import.read` (reports `import.progress`), `cookies.add` |

Events: `page.state`, `page.load`, `page.message` (what page scripts post), `page.popup`, `page.download`, `page.external`, `key` (a shortcut pressed while a page had focus), `window.state`, `window.focus`, `window.closeRequested` (the UI saves, then closes), `settings.changed`, `threads.changed`, `threads.claims`, `import.progress`.

**Keyboard.** While a page has focus, the host takes the accelerators the UI listed with `keys.set` before the page sees them (WebKitGTK `key-press-event`, WebView2 `AcceleratorKeyPressed`) and sends them as `key` events. The Mac's ⌘ is Ctrl here; its ⌥⌘ shortcuts are Ctrl+Shift, because Ctrl+Alt is AltGr on many keyboard layouts (`ui/src/model/keys.ts`).

**Getting values out of pages.** `page.eval` and `page.run` wrap the script so it posts its result on a reply channel (`wakeReply`, or `wakePageReply` from the page's world); the host matches it to the command's `req`.

## Building

The UI first (the host embeds `ui/dist`):

```bash
cd desktop/ui && npm ci && npm run build
```

Linux needs WebKitGTK 4.1 (2.40 or later) and GTK 3:

```bash
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libsoup-3.0-dev
```

```bash
cargo run --manifest-path desktop/host/Cargo.toml
```

Windows needs the Rust MSVC toolchain and WebView2 (built into Windows 11). `cargo run` there too.

Environment: `WAKE_DATA_DIR` moves the data folder (default: `~/.local/share/Wake`, `%APPDATA%\Wake`); `WAKE_DEBUG=1` logs every command; `WAKE_NO_GPU=1` turns off WebKitGTK's compositing (VMs, containers).

### The dev container (from a Mac)

`docker/linux-dev.Dockerfile` has WebKitGTK, Xvfb, xdotool, ImageMagick and the MinGW cross-compiler:

```bash
docker build -t wake-linux-dev -f desktop/docker/linux-dev.Dockerfile desktop/docker
```

- `docker/run.sh "<command>"` runs a command in it (the repo at `/wake`, the Cargo target in a volume).
- `docker/test.sh` rebuilds the host and starts Wake in the `wake-test` container on a virtual display; `docker/restart.sh` restarts it without building. `WAKE_FIXTURE=1` first creates a small fake Firefox profile (`docker/firefox-fixture.sh`) for testing Import.
- `docker/shot.sh <name>` saves a screenshot to `desktop/.shots/<name>.png`; drive the app with `docker exec -e DISPLAY=:99 wake-test xdotool …`.
- `cargo build --target x86_64-pc-windows-gnu` in the container checks that the Windows code compiles.

## Packaging and releases

- **Linux:** `packaging/linux/build-appimage.sh` turns a release build into `Wake-<version>-linux-<arch>.AppImage` with linuxdeploy and its GTK plugin. WebKitGTK's helper processes are bundled, and the bundled `libwebkit2gtk` is patched (byte for byte, same length) to find them relative to `$APPDIR/usr`, where a start hook changes directory. GL and EGL come from the system, as in every AppImage.
- **Linux packages:** `packaging/linux/build-packages.sh` makes `Wake-<version>-linux-<arch>.deb` and `.rpm` with [nfpm](https://nfpm.goreleaser.com) (`packaging/linux/nfpm.yaml`). They install `/usr/bin/wake` and depend on the distribution's WebKitGTK 4.1 (2.40+).
- **Windows:** `packaging/windows/wake.nsi` builds `Wake-<version>-windows-x64-setup.exe`, a per-user installer (no admin prompt) into `%LOCALAPPDATA%\Programs\Wake`. It runs Microsoft's WebView2 bootstrapper when WebView2 is missing. `host/build.rs` gives the .exe its icon.
- **CI:** `.github/workflows/desktop.yml` builds both on every push and fails on warnings. `desktop-release.yml` runs on the same `vX.Y.Z` tags as the macOS release: it builds the installer, the AppImages and the .deb and .rpm packages (x86_64 and aarch64, on Ubuntu 22.04 for an old glibc), signs them with minisign, waits for `release.yml` to publish the release, and attaches them.
- **Updates** (`host/src/updater.rs`): the app checks `releases/latest` for its platform's asset, downloads it and its `.minisig`, and verifies it against the public key built in from `WAKE_UPDATE_PUBLIC_KEY`. The installer then runs silently, or the AppImage is swapped in place. A .deb or .rpm install (detected through dpkg or rpm) gets the new package saved to Downloads and opened in the system's software installer, since replacing system files needs the user's password. Builds without a key, and copies built from source, don't offer updates.

## Differences from the macOS app

Each of these comes from the platform, not a missing port:

- **Snapshots stand in for covered pages.** While an overlay is up, covered pages show a still picture (see above). A video or animation behind the Deck pauses visually until the overlay closes.
- **Web Inspector:** F12 opens WebKitGTK's inspector or Edge DevTools in their own window, as on the Mac.
- **Forcing a page's color scheme** (DevTools ▸ Tools) works on Windows (through the DevTools protocol). WebKitGTK 4.1 has no API for it, so on Linux it says so.
- **Chromium cookies:** on Windows, cookies that Chrome 127+ protects with app-bound encryption ("v20") can only be read by Chrome itself, so Import skips them and says how many. On Linux, Wake reads the keyring password with `secret-tool` (from libsecret); without it, only cookies stored with the fallback key come over.
- **Safari** isn't there to import from.
- **The Brave Search API key** is kept in `settings.json`, not a system keychain.
- **Hiding at the window edge** (Zen, the capsule) needs a pointer at the edge of the window, so it works best with the window maximized or full screen.

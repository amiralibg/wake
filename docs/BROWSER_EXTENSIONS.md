# Browser extensions in Wake: research

Researched 2026-11-11. Question: can Wake run Chrome and/or Firefox extensions (WebExtensions)?

Sources are primary: Apple, Microsoft, MDN, Chrome and Electron documentation, the WebKit, wry, Epiphany and WebView2Feedback repositories, and first-party release notes. Claims about Wake cite repo paths. Anything not confirmed from a primary source is tagged **[unverified]** or **[inference]**, and collected under [Not verified](#not-verified).

## Status (2026-11-15)

macOS is built (`Wake/Features/Extensions`, macOS 15.4+): `WKWebExtension` runtime with tabs and windows, toolbar buttons with badges and popups, permission prompts, install from the Chrome Web Store, Edge Add-ons and Firefox Add-ons (an "Add to Wake" button in the store's own page, `shared/scripts/extension-stores.js`), import from Chrome, Arc, Dia, Brave, Edge, Vivaldi, Opera, Helium, Firefox, Zen and Waterfox profiles, `.crx` / `.xpi` / `.zip` / folder installs, automatic updates from the stores (SHA-256 checked; updates that ask for more access wait for a yes), keyboard `commands`, and context-menu items. Test fixture: `Scripts/extension-test`. Windows and Linux are as described below.

Also built: per-site access ("When you click it" / "On this site" / "On all sites", in the extensions menu), and columns showing an extension's own page are restored after relaunch (they wait for the extension to load).

WebKit behaviour found in testing (macOS 27), each called out in the code:

- **ITP clears extension origins.** Intelligent Tracking Prevention treats `webkit-extension://<id>` like a website; an origin it never saw "user interaction" with has its website data removed repeatedly, which unregisters the extension's background service worker. Popups then get `undefined` from `runtime.sendMessage` (Dark Reader stuck on "Loading, please wait"). Wake logs a user interaction for each extension origin through the SPI `_logUserInteraction:completionHandler:` (`ExtensionTrackingExemption`). No public API exists.
- **Packages are unpacked by Wake** (`ZipExtractor`), not handed to WebKit as ZIPs, which WebKit re-extracts to a new temporary folder at every launch.
- **Revoking host access.** Setting a broad grant (`<all_urls>`) back to `.unknown` leaves its content scripts running; only an explicit denial removes them, and WebKit remembers grants across launches. Limited site access therefore denies broadly and grants chosen sites explicitly.
- **No badge colour** (`action.setBadgeBackgroundColor`): `WKWebExtension.Action` has no colour, public or SPI (checked with the Objective-C runtime).
- **Extensions that don't run:** uBlock Origin's Firefox build calls `browser.runtime.getURL` detached from its object (`vAPI.getURL = browser.runtime.getURL`), which returns `undefined` in WebKit; uBlock Origin Lite is the build to use. Tampermonkey adds `tabs.onUpdated` after startup, which WebKit refuses for non-persistent backgrounds.

## Verdict

| Platform | Engine | Verdict | Rough effort |
|---|---|---|---|
| macOS | WKWebView | **Feasible, partially.** Apple ships a WebExtensions runtime for third-party WebKit browsers (`WKWebExtension*`) from macOS 15.4. Chrome-style MV2/MV3 extensions load, including `.crx` and zip/`.xpi` archives. Wake supplies the tab/window model, toolbar UI, permission prompts and install flow. Extensions that need blocking `webRequest`, or APIs WebKit lacks, will not work. Not available on macOS 14 to 15.3, which Wake still supports. | 2 to 4 weeks for sideloaded extensions with a toolbar button and popup; store install and updates on top of that. |
| Windows | WebView2 | **Partially, with a hard ceiling.** WebView2 can load unpacked Chromium extensions into a profile, and Chromium runs them with its full API. The host gets only add / list / enable / remove. There is no documented API for the toolbar action, popups, or mapping `chrome.tabs` ids to Wake's columns. Content-script-only extensions (ad blockers through declarativeNetRequest, dark mode, userscript managers' injected parts) are realistic; anything driven from a toolbar popup is not, short of undocumented workarounds. | About 1 week for "load unpacked, no UI". Open-ended beyond that. |
| Linux | WebKitGTK 4.1 (GTK 3) | **Not feasible today.** WebKit's extension runtime is compiled out of the GTK 3 / 4.1 API build that Wake uses, is off by default even on GTK 4, and almost every extension API is still marked Cocoa-only in WebKit's source. The alternative is writing the runtime in Wake, as GNOME Web did. | Months, for a subset. |

Firefox extensions: no non-Gecko engine runs Firefox's own runtime. A Firefox add-on works where it sticks to the cross-browser WebExtensions subset, which most do. Firefox-only APIs (`sidebarAction`, `contextualIdentities`, blocking `webRequest`, Firefox's `proxy` design) will not work on any of Wake's engines.

Recommended order: macOS first, behind `#available(macOS 15.4, *)`. Ship a built-in content blocker and userscripts on all three platforms as the cross-platform baseline. Treat Windows as "headless extensions only". Leave Linux until WebKitGTK ships the runtime.

## What Wake is today

### macOS

- Engine: `WKWebView`. Every page is a `BrowserPage` that creates one in `init` ([Wake/Features/Web/BrowserPage.swift:103-104](../Wake/Features/Web/BrowserPage.swift)).
- Deployment target: macOS 14.0 ([project.yml:5, 14, 52](../project.yml)). CI builds on `macos-26` with the latest stable Xcode ([.github/workflows/build.yml](../.github/workflows/build.yml)).
- Sandboxed, ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`), hardened runtime on ([project.yml:59, 97, 99](../project.yml)).
- One configuration factory for all normal pages: `WKWebViewConfiguration.wake()` sets the default persistent data store, a Safari-like user agent suffix, and installs Wake's scripts ([Wake/Features/Web/WebConfiguration.swift:5-18](../Wake/Features/Web/WebConfiguration.swift)). Popups reuse the configuration WebKit hands over ([Wake/Features/Trail/TrailModel.swift](../Wake/Features/Trail/TrailModel.swift), `openPopup(configuration:from:)`). Separate bare configurations exist for the Moments watcher, Pop Out, the local-storage importer, and closed-page placeholders ([MomentWatcher.swift:91](../Wake/Features/Moments/MomentWatcher.swift), [PopOut.swift:53](../Wake/Features/PopOut/PopOut.swift), [LocalStorageImport.swift:109](../Wake/Features/Import/LocalStorageImport.swift), [BrowserPage.swift:220-224](../Wake/Features/Web/BrowserPage.swift)).
- Injected JavaScript: one `WKUserScript` at document start, main frame only, in `WKContentWorld.defaultClient`, plus three message handlers ([Wake/Features/Web/WebScripts.swift:8-31](../Wake/Features/Web/WebScripts.swift)). Developer hooks go into the `.page` world only in developer mode ([Wake/Features/Developer/DevScripts.swift:13](../Wake/Features/Developer/DevScripts.swift)). The script sources live in [shared/scripts](../shared/scripts).
- No content blocker, no userscript feature, no extension code: `WKContentRuleList` and `WKWebExtension` do not appear anywhere under `Wake/`.
- Tab and window model: one `BrowserModel` per window owns the active `BrowserThread` and up to four loaded background threads ([Wake/App/BrowserModel.swift:10-11, 59](../Wake/App/BrowserModel.swift), [HANDOFF.md](../HANDOFF.md)). A thread owns a `TrailModel`, an ordered list of `BrowserPage` columns with one focused ([Wake/Features/Trail/TrailModel.swift:8-10](../Wake/Features/Trail/TrailModel.swift)). Pinned apps, DevTools columns and device previews are also `BrowserPage`s; the last two are marked `isEphemeral`.

### Windows and Linux (`desktop/`)

- Host: Rust on `wry` 0.57 and `tao` 0.37 ([desktop/host/Cargo.toml:12-13](../desktop/host/Cargo.toml)). Not Tauri, not Electron, not CEF.
- Windows engine: WebView2, through `webview2-com` 0.39 ([Cargo.toml:44](../desktop/host/Cargo.toml)). The installer runs Microsoft's bootstrapper when the Evergreen runtime is missing ([desktop/README.md](../desktop/README.md)).
- Linux engine: WebKitGTK **4.1 API on GTK 3**, 2.40 or later: `webkit2gtk = "=2.0.2"` with `v2_40`, `gtk = "0.18"` ([Cargo.toml:36-37](../desktop/host/Cargo.toml)); packages depend on `libwebkit2gtk-4.1-0 (>= 2.40)` ([desktop/packaging/linux/nfpm.yaml:40-42](../desktop/packaging/linux/nfpm.yaml)). The plan document said "WebKitGTK (6.0 API, GTK4)" ([docs/WINDOWS_LINUX_PLAN.md:21](WINDOWS_LINUX_PLAN.md)); the code did not go that way, and it matters below.
- Two web contexts with separate data folders: `webdata` for pages, `uidata` for the shell UI ([desktop/host/src/main.rs:115-116](../desktop/host/src/main.rs)).
- Each window is one shell webview running the React UI, with every column a separate native child webview placed by the UI ([desktop/README.md](../desktop/README.md), [desktop/host/src/page.rs:64-201](../desktop/host/src/page.rs)). Pages live in a flat `HashMap<String, Page>` keyed by an id the UI chose ([main.rs:65](../desktop/host/src/main.rs)); the tab model (threads, trail) is TypeScript in `desktop/ui/src/model`.
- Injected JavaScript: on Linux, a `UserScript` in the script world `"wake"` ([desktop/host/src/platform/linux.rs:19, 41-60](../desktop/host/src/platform/linux.rs)); on Windows, a wry initialization script in the page's own world, because WebView2 has no isolated worlds ([page.rs:95-108](../desktop/host/src/page.rs)).
- Nothing can draw over a page webview on either OS, so overlays swap pages for snapshots ([desktop/README.md](../desktop/README.md), "Nothing draws over a page"). An extension popup would need the same treatment or its own window.
- No extension code: wry's `with_browser_extensions_enabled` and `with_extensions_path` are not called anywhere in `desktop/host/src`.

## macOS: WKWebExtension

### What Apple ships

- `WKWebExtension`, `WKWebExtensionContext` and `WKWebExtensionController` are public API from **macOS 15.4, iOS 18.4, visionOS 2.4** ([Apple: WKWebExtension](https://developer.apple.com/documentation/webkit/wkwebextension); availability macros in [WKWebExtension.h](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtension.h)). WebKit announced them as the way to bring web extensions "into WebKit-based browsers" ([WebKit blog, Safari 18.4](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/)).
- macOS 27 and Safari 27 shipped on 2026-09-14. The Safari 26.0 and 27.0 release notes list extension API additions and fixes but no change to the embedding API ([Safari 27 release notes](https://developer.apple.com/documentation/safari-release-notes/safari-27-release-notes), [Safari 26 release notes](https://developer.apple.com/documentation/safari-release-notes/safari-26-release-notes)).
- A web view takes part by setting `WKWebViewConfiguration.webExtensionController` ([Apple](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller)).

### Loading

- `WKWebExtension(resourceBaseURL:)` takes a file URL to a directory or a ZIP archive that contains `manifest.json` ([Apple](https://developer.apple.com/documentation/webkit/wkwebextension/init(resourcebaseurl:))). `init(appExtensionBundle:)` loads a Safari-style app extension.
- WebKit's source also accepts a Chrome `.crx`: it looks for the `Cr24` signature, skips to the ZIP header, and extracts ([WebExtensionCocoa.mm, `convertChromeExtensionToTemporaryZipFile`](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/Extensions/Cocoa/WebExtensionCocoa.mm)). This is WebKit `main`; whether it is in the WebKit that shipped with macOS 15.4 is **[unverified]**. Wake can strip the header itself if not.
- A Firefox `.xpi` is a ZIP, so the ZIP path applies. **[inference]**; Apple's page does not name `.xpi`.
- Manifest V2 and V3 are both supported (Safari 15.4 and later, per [Apple's compatibility guide](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility)). The API exposes `manifestVersion` and `supportsManifestVersion(_:)`.
- Background content: service workers and background pages/scripts both work; Safari picks `background.scripts` when both are present unless the manifest prefers the service worker ([MDN: background](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/background)). Persistent background pages are allowed on macOS only ([Apple: hasPersistentBackgroundContent](https://developer.apple.com/documentation/webkit/wkwebextension/haspersistentbackgroundcontent)).
- Both `chrome.*` and `browser.*` namespaces, callbacks and promises, are supported ([Apple's compatibility guide](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility)).

### API coverage

The top-level namespace in WebKit's source lists what an extension can see ([WebExtensionAPINamespace.idl](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WebProcess/Extensions/Interfaces/WebExtensionAPINamespace.idl)):

`action`, `browserAction`, `pageAction`, `alarms`, `commands`, `contextMenus`, `menus`, `cookies`, `declarativeNetRequest`, `devtools`, `dom`, `extension`, `i18n`, `notifications`, `offscreen`, `permissions`, `runtime`, `scripting`, `storage`, `tabs`, `windows`, `webNavigation`, `webRequest`.

Behind flags that are off in WebKit `main`: `bookmarks`, `sidebarAction`, `sidePanel` ([PlatformEnableCocoa.h](https://github.com/WebKit/WebKit/blob/main/Source/WTF/wtf/PlatformEnableCocoa.h), `ENABLE_WK_WEB_EXTENSIONS_BOOKMARKS` and `_SIDEBAR` are `0 &&`). Which flags were on in each shipped OS is **[unverified]**.

Not in the list at all: `downloads`, `history`, `identity`, `management`, `proxy`, `topSites`, `browsingData`, `debugger`, `contextualIdentities`.

Known gaps Apple documents:

- `webRequest` is observe-only: "Blocking requests not supported", `BlockingResponse` not supported ([Apple's compatibility guide](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility)). Request blocking goes through `declarativeNetRequest`, which is supported (permission constants in [WKWebExtension.Permission](https://developer.apple.com/documentation/webkit/wkwebextension/permission)). uBlock Origin's MV2 build depends on blocking `webRequest`; its declarativeNetRequest-based "Lite" variant is the one that fits. **[inference]** from the API requirement, not tested.
- Safari ignores file-URL schemes in manifest permissions (same guide).
- For per-API detail Apple points to MDN's table ([Browser support for JavaScript APIs](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Browser_support_for_JavaScript_APIs)).

Native messaging: `runtime.sendNativeMessage` and `connectNative` exist ([WebExtensionAPIRuntime.idl](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WebProcess/Extensions/Interfaces/WebExtensionAPIRuntime.idl)), but they are routed to the host app's delegate: `webExtensionController(_:sendMessage:toApplicationWithIdentifier:for:replyHandler:)` and `...connectUsing:for:...`. Without an implementation, and without an app extension bundle, "no action is performed" ([Apple](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate/webextensioncontroller(_:sendmessage:toapplicationwithidentifier:for:replyhandler:))). Chrome-style native messaging hosts (a JSON manifest naming an executable that speaks stdio) are therefore Wake's to implement, and Wake's App Sandbox ([project.yml:59](../project.yml)) would block launching arbitrary helper binaries. **[inference]** on the sandbox point. Password-manager extensions that depend on a desktop companion are the main casualty.

### What Wake must build

All of this is from the delegate and protocol listings ([WKWebExtensionControllerDelegate](https://developer.apple.com/documentation/webkit/wkwebextensioncontrollerdelegate), [WKWebExtensionTab](https://developer.apple.com/documentation/webkit/wkwebextensiontab), [WKWebExtensionWindow](https://developer.apple.com/documentation/webkit/wkwebextensionwindow), [WKWebExtensionContext](https://developer.apple.com/documentation/webkit/wkwebextensioncontext)).

1. **Controller wiring.** Create one `WKWebExtensionController`, set it on the configuration in `WKWebViewConfiguration.wake()`. `WKWebExtensionTab.webView(for:)` says a tab whose web view lacks the matching controller loses "content injection or modification" ([Apple](https://developer.apple.com/documentation/webkit/wkwebextensiontab/webview(for:))). Popups inherit the opener's configuration, so they are covered.
2. **Tabs and windows.** Conform `BrowserPage` to `WKWebExtensionTab` (url, title, index, selected, pinned, muted, loading, zoom, snapshot, load, reload, back/forward, close, duplicate, parent tab) and a window object to `WKWebExtensionWindow` (tabs, active tab, frame, state, type, private, focus, close). Report every change through `didOpenTab`, `didCloseTab`, `didActivateTab`, `didMoveTab`, `didChangeTabProperties`, `didOpenWindow`, `didFocusWindow` and the rest. The delegate also answers `openWindowsFor`, `focusedWindowFor`, `openNewTabUsing`, `openNewWindowUsing`.
3. **Extension pages in tabs.** Web views that show an extension's own pages must be created from `WKWebExtensionContext.webViewConfiguration`, and the app "must also swap web views in tabs when navigating to and from web extension URLs" ([Apple](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/webviewconfiguration)). `BrowserPage.webView` is already replaceable (`private(set) var`, swapped in `close()`), but KVO observers and delegates would need re-attaching on swap.
4. **Toolbar UI.** `WKWebExtension.Action` gives icon, label, badge text, enabled state, and a ready-made `popupPopover` / `popupViewController` / `popupWebView` ([Apple](https://developer.apple.com/documentation/webkit/wkwebextension/action)). Wake draws the buttons and presents the popup from `presentActionPopup`. Context-menu entries come from `menuItems(for:)`; keyboard commands from `commands` / `performCommand`.
5. **Permissions.** Three prompt callbacks (`promptForPermissions`, `promptForPermissionMatchPatterns`, `promptForPermissionToAccess` URLs), plus storing grants with `setPermissionStatus(_:for:expirationDate:)`. Tabs can opt into `shouldGrantPermissionsOnUserGesture` (activeTab behaviour).
6. **Options page and new-tab override.** `openOptionsPageFor`, `optionsPageURL`, `overrideNewTabPageURL`.
7. **Install, storage, updates, removal.** Not provided. Wake unpacks or keeps the archive, remembers which extensions are enabled, calls `load(_:)` at launch, and clears data with `removeData(ofTypes:from:)`. Auto-update (Chrome's `update_url`, AMO's update service) is Wake's to write.
8. **Opting out of APIs.** `WKWebExtensionContext.unsupportedAPIs` makes named APIs `undefined` so extensions feature-detect, for parts Wake does not implement, e.g. `browser.windows.create` ([Apple](https://developer.apple.com/documentation/webkit/wkwebextensioncontext/unsupportedapis)).

### Fit with Wake's model

- A thread's trail maps cleanly to a window's tab list: ordered, one active. **[inference]** The open design choice is what `tabs.query({})` returns: only the active thread's columns, or background threads too (as extra "windows"?). Discarded threads have no web views, so they can only be reported as unloaded tabs or omitted.
- DevTools columns, device previews, pinned apps, Pop Out and the Moments watcher should not be reported as tabs; leaving the controller off their configurations keeps content scripts out of them. Pop Out and the watcher already use their own configurations.
- Wake's own scripts run in `defaultClient`; WebKit runs extension content scripts in separate worlds. No collision expected. **[inference]**
- macOS 14 to 15.3 users get no extensions. Either gate with `#available(macOS 15.4, *)` or raise the deployment target.
- Whether the API needs any entitlement or misbehaves in an ad-hoc-signed, sandboxed app is **[unverified]**; Apple's pages list none. Test early.

## Chrome Web Store and Firefox AMO packages

- **Format.** `.crx` (CRX3) is a signed header followed by a ZIP ([Chromium: crx3.proto](https://chromium.googlesource.com/chromium/src/+/main/components/crx_file/crx3.proto)); WebKit `main` unwraps it (above). `.xpi` is a ZIP.
- **Chrome Web Store terms** (updated 2025-01-27, [terms](https://ssl.gstatic.com/chrome/webstore/intl/en/gallery_tos.html)): section 1.2 offers Products "for use in connection with Google Chrome"; section 3.3 forbids accessing the store other than through Google's interface and forbids automated access; section 3.5 forbids reproducing or copying Products. The terms do not mention other browsers by name. Fetching `.crx` files from Google's update endpoint in a non-Chromium browser sits badly with 1.2 and 3.3. This is a reading of the text, not legal advice. The download endpoint itself is not a documented public API **[unverified]**.
- **Firefox AMO.** Release Firefox only installs Mozilla-signed add-ons ([Extension Workshop](https://extensionworkshop.com/documentation/publish/signing-and-distribution-overview/)); that check is Firefox's and does not bind another browser. AMO has a documented public API with add-on and file metadata ([addons-server API](https://mozilla.github.io/addons-server/topics/api/addons.html)). I did not read AMO's terms of service for third-party clients **[unverified]**. Each add-on also carries its own licence.
- **Orion (Kagi), the closest precedent.** Kagi's docs say Orion installs from both the Chrome and Firefox stores with one click, after enabling it in Settings ▸ Advanced, and also supports Safari web extensions; API coverage is "about 70%", support "is still in beta", and "it is enough that one API is not supported for the extension to not work" ([Orion: macOS extensions](https://help.kagi.com/orion/browser-extensions/macos-extensions.html)). They describe porting APIs to WebKit one by one, with their own implementation; the goal is "100% of APIs on Desktop" ([Orion: Web Extensions API support](https://help.kagi.com/orion/misc/technical.html)). Kagi's docs do not say whether Orion now uses `WKWebExtension` **[unverified]**. Orion predates that API, so its 70% figure is not a measure of what `WKWebExtension` gives Wake.

Safest install paths, in order: "Load unpacked folder / choose a .zip, .crx or .xpi file" (no store terms involved); AMO via its public API; Chrome Web Store last, and only after deciding the terms question.

## Windows: WebView2

### What exists

- `ICoreWebView2Profile7::AddBrowserExtension` loads an **unpacked** extension folder into a profile; `GetBrowserExtensions` lists them; `ICoreWebView2BrowserExtension` exposes `Id`, `Name`, `IsEnabled`, `Enable`, `Remove`. Available since SDK 1.0.2210.55 ([Profile7](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2profile7), [BrowserExtension](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2browserextension)).
- Off by default. `AreBrowserExtensionsEnabled` must be set on the environment options, and an environment with a different value cannot share a running browser process ([EnvironmentOptions6](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2environmentoptions6)).
- The extension's files are not copied into the user data folder, changing them removes the extension, and the install persists in the profile ([AddBrowserExtensionAsync remarks](https://learn.microsoft.com/en-us/dotnet/api/microsoft.web.webview2.core.corewebview2profile.addbrowserextensionasync)). So Wake must unpack `.crx` files itself into a stable folder it owns.
- wry already wraps this: `WebViewBuilderExtWindows::with_browser_extensions_enabled(true)` and `with_extensions_path(dir)`, which calls `AddBrowserExtension` for each subfolder ([wry 0.57 `src/lib.rs`](https://github.com/tauri-apps/wry/blob/wry-v0.57.0/src/lib.rs), [`src/webview2/mod.rs`](https://github.com/tauri-apps/wry/blob/wry-v0.57.0/src/webview2/mod.rs)). wry notes that web views with different extension settings need different data directories; Wake's `webdata` / `uidata` split ([main.rs:115-116](../desktop/host/src/main.rs)) already gives that, and keeps extensions out of the shell UI.

### The ceiling

The documented host surface ends at add / list / enable / remove. The gaps are tracked, still open, in Microsoft's own feedback repository, filed by a team building a browser on WebView2:

- No way to map the tab ids `chrome.tabs.query` returns to WebView2 instances ([#3854](https://github.com/MicrosoftEdge/WebView2Feedback/issues/3854)).
- No supported way for the host to replace or back extension APIs such as `chrome.tabs.*` ([#3853](https://github.com/MicrosoftEdge/WebView2Feedback/issues/3853)).
- No host-to-extension messaging; the reported workaround is attaching a DevTools Protocol session to the extension target ([#3851](https://github.com/MicrosoftEdge/WebView2Feedback/issues/3851)).
- No extension metadata beyond id and name ([#3856](https://github.com/MicrosoftEdge/WebView2Feedback/issues/3856)).

Consequences for Wake:

- No API hands Wake an action icon, badge, or popup. Loading `chrome-extension://<id>/popup.html` in a Wake-created WebView2 might work as a stand-in **[unverified]**; Wake would read `manifest.json` itself for the icon and popup path.
- Chromium, not Wake, decides what a "tab" and "window" are. Each Wake column is a separate WebView2; how `chrome.tabs` / `chrome.windows` report them is undocumented **[unverified]**. `tabs.create` and `windows.create` requests presumably arrive as `NewWindowRequested`, which Wake already handles as a popup ([page.rs:212-244](../desktop/host/src/page.rs)) **[unverified]**.
- Chrome Web Store install inside WebView2 is not a documented feature **[unverified]**; plan on download-and-unpack by Wake.
- What does work without host help: content scripts, background service workers, `storage`, `declarativeNetRequest`, `webRequest`, since those run entirely inside Chromium. **[inference]** from the API design; the docs list no per-API support table.

### Alternatives if the ceiling is unacceptable

- **Electron**: "supports a subset of the Chrome Extensions API", "does not support arbitrary Chrome extensions from the store", unpacked only, and full compatibility "is a non-goal" ([Electron docs](https://www.electronjs.org/docs/latest/api/extensions)). No better than WebView2 for this, and it means bundling Chromium, which the plan rejected ([WINDOWS_LINUX_PLAN.md](WINDOWS_LINUX_PLAN.md), "Not chosen").
- **CEF**: the maintainer closed the Alloy-runtime extension issue as wontfix in 2020, stating "Extensions will be fully supported with the Chrome runtime" ([cef#1947](https://github.com/chromiumembedded/cef/issues/1947)). Chrome-runtime CEF is effectively Chrome's own browser UI and tab model, which conflicts with Wake drawing its own trail. Current state of CEF's Chrome-style extension support was not checked further **[unverified]**.
- **Tauri**: uses wry, so it is the same WebView2 surface Wake already has.

## Linux: WebKitGTK

- WebKit's cross-platform extension runtime has a GLib port in progress: `Source/WebKit/UIProcess/Extensions/glib`, `gtk`, `wpe`, and public headers `WebKitWebExtension`, `WebKitWebExtensionContext`, `WebKitWebExtensionMatchPattern` documented "Since: 2.52" ([UIProcess/API/glib](https://github.com/WebKit/WebKit/tree/main/Source/WebKit/UIProcess/API/glib), [UIProcess/Extensions](https://github.com/WebKit/WebKit/tree/main/Source/WebKit/UIProcess/Extensions)). There is no controller, tab or window API in that directory yet.
- It is compiled out of Wake's configuration. In [OptionsGTK.cmake](https://github.com/WebKit/WebKit/blob/main/Source/cmake/OptionsGTK.cmake), `ENABLE_WK_WEB_EXTENSIONS` defaults to `ENABLE_EXPERIMENTAL_FEATURES` (off in release builds), and the GTK 3 branch, which is the 4.1 API Wake links ([Cargo.toml:36](../desktop/host/Cargo.toml)), sets `ENABLE_WK_WEB_EXTENSIONS OFF` outright. The headers are also guarded by `ENABLE(2022_GLIB_API)`, the 6.0 API.
- Even where it is built, the JavaScript side is nearly empty: in [WebExtensionAPINamespace.idl](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WebProcess/Extensions/Interfaces/WebExtensionAPINamespace.idl) every API except `alarms`, `extensionTypes` and `test` is tagged `Platform=COCOA`.
- Latest stable WebKitGTK is 2.54.2 ([releases](https://webkitgtk.org/releases/)). Whether any distribution ships a build with the option on is **[unverified]**, and unlikely given the default.
- Do not confuse this with wry's Linux `with_extensions_path`: it calls `set_web_extensions_directory`, which loads WebKit *web process extensions* (native `.so` plugins), not browser extensions ([wry `src/webkitgtk/mod.rs`](https://github.com/tauri-apps/wry/blob/wry-v0.57.0/src/webkitgtk/mod.rs)).
- Precedent for doing it in the app: GNOME Web implements WebExtensions itself, on top of WebKitGTK. Its README calls it "experimental ... insecure, incomplete, and full of issues", loads `.xpi` and unpacked folders, and covers `alarms`, `browserAction`, `pageAction`, `commands`, `cookies`, `downloads`, `menus`, `notifications`, `runtime`, `storage`, `tabs`, `windows` in part ([Epiphany README](https://gitlab.gnome.org/GNOME/epiphany/-/blob/main/src/webextension/README.md)).

A path would be: move to the 6.0 API (GTK 4), then wait for WebKitGTK to finish and enable the runtime. The GTK 4 move is a rewrite of the Linux windowing in `desktop/host` (the `GtkOverlay` / `GtkFixed` layout, `webkit2gtk` crate, `rfd` gtk3 feature) and whether wry supports GTK 4 was not checked **[unverified]**.

## Firefox extensions specifically

- Namespaces are no longer the divide. Per MDN, `browser.*` is supported by Chrome from 148 (152 for `devtools_page` extensions), and Chrome returns promises in MV3; for older targets there is Mozilla's [webextension-polyfill](https://github.com/mozilla/webextension-polyfill) ([MDN: Chrome incompatibilities](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Chrome_incompatibilities)). WebKit supports both namespaces and both calling styles.
- Background: Firefox does not support `background.service_worker`; Chrome MV3 supports only service workers; Safari supports both ([MDN: background](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/background)). So a Firefox MV3 add-on with `background.scripts` loads in WebKit (macOS) but not in Chromium (WebView2) unless it also declares a service worker.
- Differences that do not port (same MDN page): Firefox's `sidebar_action` vs Chrome's `side_panel`; incompatible `proxy` API designs; Firefox's promise-based blocking `webRequest`; structured clone vs JSON for message data; relative URLs in content-script requests and injected CSS resolve differently; native messaging manifests use `allowed_extensions` vs `allowed_origins`; `browser_specific_settings.gecko.id` vs Chrome's `key`.
- A standard is in progress at the W3C ([WebExtensions Community Group](https://www.w3.org/community/webextensions/), [draft specification](https://w3c.github.io/webextensions/specification/), and a [Working Group](https://www.w3.org/groups/wg/webextensions/)). It narrows differences over time; it does not make Gecko-only APIs appear elsewhere.
- Can a non-Gecko engine run Firefox extensions? Only by implementing the APIs itself: Orion does on WebKit, GNOME Web does in part. Gecko has no supported desktop embedding to borrow the runtime from **[unverified]**; not researched further because it would mean replacing Wake's engines.

Practical rule for Wake: accept `.xpi` wherever `.crx` is accepted, feed it to the platform runtime, and show the manifest's unsupported keys/APIs at install time.

## Fallbacks that work on all three platforms

These cover the most common reasons people install extensions, without an extension runtime.

- **Content blocking.**
  - macOS: [`WKContentRuleList`](https://developer.apple.com/documentation/webkit/wkcontentrulelist) compiled from JSON rules and added to the user content controller in `WebScripts.install` / `WKWebViewConfiguration.wake()`.
  - Linux: [`WebKitUserContentFilterStore`](https://webkitgtk.org/reference/webkit2gtk/stable/class.UserContentFilterStore.html) takes the same JSON rule format and attaches through the `UserContentManager` Wake already uses ([linux.rs:74](../desktop/host/src/platform/linux.rs)). Present in the 4.1 API.
  - Windows: no declarative rule list in WebView2. Options are the [`WebResourceRequested`](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2#add_webresourcerequested) event with a filter list matched in Rust, or loading a declarativeNetRequest-based blocker as an unpacked extension (the "headless extension" case WebView2 handles).
  - One rule source, e.g. converted EasyList, could feed all three. Conversion tooling was not researched **[unverified]**.
- **Userscripts.** [`WKUserScript`](https://developer.apple.com/documentation/webkit/wkuserscript) with a per-script `WKContentWorld` on macOS; `UserScript::for_world` with allow/block URL lists on Linux ([linux.rs:43-50](../desktop/host/src/platform/linux.rs) shows the call; the last two arguments are the allow and block lists, see [UserContentManager](https://webkitgtk.org/reference/webkit2gtk/stable/class.UserContentManager.html)); `AddScriptToExecuteOnDocumentCreated` on Windows ([windows.rs:327](../desktop/host/src/platform/windows.rs)), where there is no isolated world, so scripts share the page's globals. `@match` filtering, `GM_*` functions and cross-origin `GM_xmlhttpRequest` (the host already has `http.fetch`, [desktop/README.md](../desktop/README.md)) are Wake's to write. Scripts can live in `shared/` like the existing page scripts.
- **A small built-in WebExtension subset** (content scripts + `storage` + `runtime.sendMessage` + a background page, driven by a parsed `manifest.json`). This is what GNOME Web built. It is the only route to parity on Linux today, and it is a large, security-sensitive project. Not recommended ahead of the two items above.

## Recommended path

**Phase 0: spike, macOS (2 to 3 days).** In a branch, set a `WKWebExtensionController` on `WKWebViewConfiguration.wake()` under `#available(macOS 15.4, *)`, load one unpacked extension from disk, stub the tab/window protocols on `BrowserPage` and `BrowserModel`. Confirm in the sandboxed, ad-hoc-signed build that content scripts inject, the background worker runs, and `action.popupPopover` shows. Try a `.crx` and an `.xpi` through `init(resourceBaseURL:)`. This settles the entitlement, signing and archive questions.

**Phase 1: cross-platform baseline (1 to 2 weeks).** Built-in content blocker (rule list on macOS and Linux; `WebResourceRequested` or a bundled DNR extension on Windows) and userscripts. Useful on every platform regardless of what follows.

**Phase 2: macOS extensions, sideloaded (2 to 4 weeks).** Full `WKWebExtensionTab` / `WKWebExtensionWindow` conformance and change notifications; toolbar buttons with badge and popup; permission prompts; options page; context menus and commands; an Extensions section in Settings with "Add from folder or file", enable/disable, remove. Decide how threads map to windows. Use `unsupportedAPIs` for what is skipped.

**Phase 3: stores and updates (1 to 2 weeks, after a terms decision).** AMO through its public API first. Chrome Web Store only if the terms reading is acceptable. Update checks for installed extensions.

**Phase 4: Windows, headless extensions (about 1 week).** Turn on `with_browser_extensions_enabled` for the page context only, unpack into a Wake-owned folder, list/enable/remove in Settings. Label it as limited: extensions without a toolbar popup. Spike the `chrome-extension://…/popup.html` idea before promising more.

**Linux:** content blocker and userscripts only. Revisit when WebKitGTK enables `ENABLE_WK_WEB_EXTENSIONS` in release builds and exposes a controller API, which also requires Wake's move to the 6.0 API.

## Open questions

1. Raise the macOS deployment target to 15.4, or keep 14.0 and gate extensions at runtime?
2. What does an extension see as "tabs" and "windows": the active thread only, or all loaded threads? Are discarded threads reported?
3. Are DevTools columns, device previews and pinned apps visible to extensions? (Proposed: no.)
4. Where do extension buttons go in a toolbar built from islands and a Zen mode that hides it?
5. Is installing from the Chrome Web Store acceptable given sections 1.2 and 3.3 of its terms, or is it file/AMO only?
6. Native messaging: skip, or leave the sandbox for it?
7. Is the Windows "no popup, no tab mapping" tier worth shipping, or does it create support load for extensions that half work?
8. Is a GTK 4 / WebKitGTK 6.0 migration on the roadmap for other reasons? It is the precondition for engine-level extensions on Linux.

## Not verified

- Whether WebKit's `.crx` unwrapping is in the system WebKit of macOS 15.4, 26 and 27, or only newer builds. Source checked is WebKit `main`.
- Which optional extension APIs (`sidebarAction`, `sidePanel`, `bookmarks`) are enabled in each shipped macOS. Source checked is WebKit `main`, where they are off.
- Whether `WKWebExtension` needs an entitlement or a Developer ID signature in practice. Apple's reference pages list none; not tested.
- Whether Orion today uses `WKWebExtension` or only its own implementation. Kagi's docs describe their own.
- Chrome Web Store: the `.crx` download endpoint is not a documented public API; the terms reading above is mine.
- AMO terms of use for third-party clients were not read.
- WebView2: how `chrome.tabs` / `chrome.windows` represent multiple WebView2 controls; whether an extension popup page can be hosted in an app-created WebView2; whether in-WebView2 Chrome Web Store installs work. Microsoft's docs are silent; the open feedback issues are the evidence for the gaps.
- WebView2: no per-API support table exists in Microsoft's docs; "content scripts, DNR, storage work" is inference from Chromium running the extension.
- CEF's current Chrome-style extension support, and Gecko embedding, were only checked as far as cited.
- Whether wry or the `webkit2gtk` crate family supports the WebKitGTK 6.0 API.
- Compatibility of any specific extension (uBlock Origin Lite, Bitwarden, Dark Reader, etc.) with any of these runtimes. Nothing was run.

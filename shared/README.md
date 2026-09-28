# Shared code for all Wake apps

`scripts/` holds the page JavaScript; `schema/` the data model. This file covers the scripts; `schema/README.md` the data.

## Page scripts

The JavaScript Wake runs inside web pages, shared by the macOS app (WebKit), the Linux app (WebKitGTK) and the Windows app (WebView2).

### The format

Every file except `bridge.js` is the **body of a function** with two names in scope:

- `wake`: the bridge. `wake.post(channel, message)` sends `message` to the host.
- `params`: a plain object of values the host fills in (channel names, limits, the text to find). A script never gets values spliced into its source.

The host wraps a file like this before running it:

```js
(function (wake, params) {
  /* file body */
})(/* bridge.js, called */, /* params as JSON */);
```

A body can `return` a value; that is what evaluating the script gives back. Files whose names start with `async-` are the bodies of *async* functions: they may `await`, and the host runs them with `callAsyncJavaScript` (WebKit) or its equivalent.

`bridge.js` is a function body too, with no parameters, and returns the bridge object. On WebKit (macOS and WebKitGTK) it posts to `window.webkit.messageHandlers[channel]`; on WebView2 it posts `{ channel, message }` through `window.chrome.webview`.

### Worlds

On WebKit, Wake's own scripts run in an isolated content world (`WKContentWorld.defaultClient`, or a WebKitGTK script world), which pages can't see. Developer hooks and the DevTools library run in the page's world because they wrap or read the page's own globals. WebView2 has no isolated world for injected scripts, so there everything shares the page's world: keep globals under `__wake`, `__wakeDev`, `__wakeDT` and don't trust values a page could have set.

| File | World | Channel |
|---|---|---|
| `link-interceptor.js`, `scroll-probe.js`, `page-state.js`, `scroll-sync.js`, `live.js` | Wake | `wake` |
| `moment-capture.js`, `moment-restore.js`, `visible-text.js`, `favicon.js` | Wake | — |
| `popout-picker.js` | Wake | `wake` |
| `popout-isolate.js` | Wake (the Pop Out's own page) | `wakePopOut` |
| `json-viewer.js` | Wake | — |
| `dev-hooks.js`, `component-inspector.js` | page | `wakeDev` |
| `devtools.js`, `async-devtools-*.js` | page | `wakeDT` |
| `async-fetch-source.js`, `async-local-storage-write.js` | Wake | — |

### Checking

`node shared/check-scripts.mjs` wraps each file the way a host does and compiles it (without running it). CI runs it on every push.

## Data

`schema/001_initial.sql` is the data model as SQLite: one table per SwiftData model of the macOS app (`ThreadRecord`, `ColumnRecord`, `VisitRecord`, `SearchRecord`, `PinnedAppRecord`, `MomentRecord`), with the Mac field names. The desktop apps create their database from it; later migrations go in `002_….sql` and so on, each ending with `PRAGMA user_version = N`. The macOS app keeps its SwiftData store: the fields are the same, the file isn't.

`schema/settings.json` lists every preference key the macOS app keeps in `UserDefaults`, with its type and default. The desktop apps use the same keys.

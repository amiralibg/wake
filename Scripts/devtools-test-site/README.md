# DevTools test site

A small page that exercises every DevTools pane: local and session storage, cookies,
IndexedDB, Cache Storage, a service worker, fetch and XHR, console levels, a shorthand
`font` rule, and a request 8 seconds after load (for the Network waterfall).

```bash
python3 -m http.server 8765 -d Scripts/devtools-test-site
```

Then open `localhost:8765` in Wake; developer mode turns on by itself for localhost.

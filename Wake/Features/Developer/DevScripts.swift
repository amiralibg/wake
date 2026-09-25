import WebKit

/// JavaScript for developer mode.
///
/// The hooks must run in the page's own world (`.page`), because they wrap the page's
/// `console`, `fetch`, `XMLHttpRequest` and `WebSocket`; an isolated world has its own
/// copies of those. They're only added to pages in developer mode.
@MainActor
enum DevScripts {
    static let handlerName = "wakeDev"

    static var hooks: WKUserScript {
        WKUserScript(source: hooksSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page)
    }

    /// Console, errors, fetch/XHR (with mocking) and HMR sockets, reported to Wake.
    static let hooksSource = """
    (() => {
      if (window.__wakeDev) return;
      window.__wakeDev = { mocks: {} };
      const post = (m) => { try { window.webkit.messageHandlers.\(handlerName).postMessage(m); } catch {} };
      const show = (a) => {
        // WebKit's error.stack is only the frames, so lead with name and message.
        if (a instanceof Error) return `${a.name}: ${a.message}`;
        if (a && typeof a === 'object') { try { return JSON.stringify(a); } catch { return String(a); } }
        return String(a);
      };

      ['log', 'info', 'debug', 'warn', 'error'].forEach((level) => {
        const original = console[level];
        console[level] = function (...args) {
          try {
            const error = args.find(a => a instanceof Error);
            const stack = (error && error.stack) || (level === 'error' ? new Error().stack : null);
            post({ type: 'console', level, message: args.map(show).join(' ').slice(0, 4000), stack });
          } catch {}
          return original.apply(this, args);
        };
      });
      window.addEventListener('error', (e) => post({ type: 'console', level: 'error', message: e.message,
        stack: (e.error && e.error.stack) || `at ${e.filename}:${e.lineno}:${e.colno}` }));
      window.addEventListener('unhandledrejection', (e) => post({ type: 'console', level: 'error',
        message: 'Unhandled rejection: ' + show(e.reason), stack: e.reason && e.reason.stack }));

      let nextId = 1;
      const absolute = (url) => { try { return new URL(url, location.href).href; } catch { return String(url); } };
      const mockFor = (url) => { try { return window.__wakeDev.mocks[new URL(url, location.href).pathname]; } catch { return undefined; } };

      const originalFetch = window.fetch;
      window.fetch = async function (input, init = {}) {
        const id = nextId++;
        const request = input instanceof Request ? input : null;
        const url = absolute(request ? request.url : input);
        const method = (init.method || (request && request.method) || 'GET').toUpperCase();
        const headers = {};
        try { new Headers(init.headers || (request && request.headers) || {}).forEach((v, k) => headers[k] = v); } catch {}
        const body = typeof init.body === 'string' ? init.body.slice(0, 20000) : null;
        const start = performance.now();
        post({ type: 'request', id, method, url, headers, body });
        const mock = mockFor(url);
        if (mock !== undefined) {
          post({ type: 'response', id, status: 200, ms: 0, mocked: true, preview: mock.slice(0, 4000) });
          return new Response(mock, { status: 200, headers: { 'Content-Type': 'application/json' } });
        }
        try {
          const response = await originalFetch.apply(this, arguments);
          let preview = null;
          try {
            const type = response.headers.get('content-type') || '';
            if (type.includes('json') || type.includes('text')) preview = (await response.clone().text()).slice(0, 4000);
          } catch {}
          post({ type: 'response', id, status: response.status, ms: performance.now() - start, preview });
          return response;
        } catch (error) {
          post({ type: 'response', id, status: 0, ms: performance.now() - start, error: String(error) });
          throw error;
        }
      };

      const open = XMLHttpRequest.prototype.open;
      const send = XMLHttpRequest.prototype.send;
      const setHeader = XMLHttpRequest.prototype.setRequestHeader;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__wake = { id: nextId++, method: String(method).toUpperCase(), url: absolute(url), headers: {} };
        return open.apply(this, arguments);
      };
      XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
        if (this.__wake) this.__wake.headers[name] = value;
        return setHeader.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function (body) {
        const w = this.__wake;
        if (w) {
          const start = performance.now();
          post({ type: 'request', id: w.id, method: w.method, url: w.url, headers: w.headers,
                 body: typeof body === 'string' ? body.slice(0, 20000) : null });
          this.addEventListener('loadend', () => post({ type: 'response', id: w.id, status: this.status,
            ms: performance.now() - start,
            preview: (this.responseType === '' || this.responseType === 'text') ? String(this.responseText).slice(0, 4000) : null }));
        }
        return send.apply(this, arguments);
      };

      const NativeSocket = window.WebSocket;
      const WakeSocket = function (url, protocols) {
        const socket = protocols === undefined ? new NativeSocket(url) : new NativeSocket(url, protocols);
        const u = String(url), p = String(protocols || '');
        const kind = p.includes('vite') ? 'Vite'
          : u.includes('webpack-hmr') ? 'Next.js'
          : (u.includes('sockjs') || /\\/ws\\/?$/.test(u)) ? 'webpack' : null;
        if (kind) {
          socket.addEventListener('open', () => post({ type: 'hmr', state: 'connected', kind }));
          socket.addEventListener('close', () => post({ type: 'hmr', state: 'disconnected', kind }));
          socket.addEventListener('message', (e) => {
            try {
              const data = JSON.parse(e.data);
              if (['update', 'full-reload', 'built', 'sync', 'serverComponentChanges'].includes(data.type || data.action)) {
                post({ type: 'hmr', state: 'updated', kind });
              }
            } catch {}
          });
        }
        return socket;
      };
      WakeSocket.prototype = NativeSocket.prototype;
      Object.assign(WakeSocket, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });
      window.WebSocket = WakeSocket;
    })();
    """

    /// Pushes the mocked routes into the page.
    static func setMocks(_ mocks: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: mocks)) ?? Data("{}".utf8)
        return "window.__wakeDev && (window.__wakeDev.mocks = \(String(decoding: data, as: UTF8.self)));"
    }

    /// Re-sends a captured request from the page, so cookies and origin match.
    static func replay(_ entry: NetworkEntry) -> String {
        var options: [String: Any] = ["method": entry.method, "headers": entry.requestHeaders]
        if let body = entry.requestBody { options["body"] = body }
        let optionsJSON = String(decoding: (try? JSONSerialization.data(withJSONObject: options)) ?? Data("{}".utf8), as: UTF8.self)
        let url = String(decoding: (try? JSONSerialization.data(withJSONObject: [entry.url.absoluteString])) ?? Data("[]".utf8), as: UTF8.self)
        return "fetch(\(url)[0], \(optionsJSON)).catch(() => {});"
    }
}

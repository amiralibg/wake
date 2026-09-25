import WebKit

/// JavaScript Wake injects into pages. Runs in `WKContentWorld.defaultClient`, isolated
/// from the page's own scripts: pages can't read or overwrite `__wake`, but it still
/// sees the DOM and its events.
@MainActor
enum WebScripts {
    static let world = WKContentWorld.defaultClient
    static let handlerName = "wake"

    static func install(in controller: WKUserContentController) {
        controller.addUserScript(baseScript)
        controller.add(PageScriptBridge(), contentWorld: world, name: handlerName)
        // Developer-mode hooks run in the page world and report here. The handler is
        // always registered; the hooks themselves are only added in developer mode.
        controller.add(PageScriptBridge(isDeveloper: true), contentWorld: .page, name: DevScripts.handlerName)
    }

    /// Link interception, the scroll probe, page state, scroll sync and live-chip
    /// reporters, in Wake's world.
    static var baseScript: WKUserScript {
        WKUserScript(
            source: linkInterceptor + scrollProbe + pageState + scrollSync + LiveScripts.source(handler: handlerName),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        )
    }

    /// Link clicks open a new trail column instead of navigating in place.
    /// Capture phase on `window` runs before any page handler, which matters because
    /// single-page apps (React Router, Next, Turbo…) otherwise swallow the click and
    /// pushState, and WebKit never sees a navigation.
    /// ⌥-click navigates in place; ⌘-click opens the column without focusing it.
    private static let linkInterceptor = """
    (() => {
      window.__wake = window.__wake || {};
      window.addEventListener('click', (event) => {
        // The Pop Out picker is choosing an element: the click is its, not a link's.
        if (window.__wakePick) return;
        if (event.button !== 0 || event.altKey || event.ctrlKey) return;
        const anchor = event.composedPath().find(n => n instanceof HTMLAnchorElement || n instanceof SVGAElement);
        if (!anchor || anchor.hasAttribute('download')) return;
        const role = (anchor.getAttribute('role') || '').toLowerCase();
        if (['button', 'tab', 'menuitem', 'option'].includes(role) || anchor.hasAttribute('aria-controls')) return;
        const target = (anchor.getAttribute('target') || '').toLowerCase();
        if (target && target !== '_self' && target !== '_top') return; // _blank is a popup; WebKit asks us natively.
        const raw = anchor instanceof SVGAElement ? anchor.href.baseVal : anchor.getAttribute('href');
        if (!raw || raw.startsWith('#') || raw.startsWith('javascript:')) return;
        let url;
        try { url = new URL(raw, location.href); } catch { return; }
        if (url.protocol !== 'http:' && url.protocol !== 'https:') return;
        const here = new URL(location.href);
        if (url.origin === here.origin && url.pathname === here.pathname && url.search === here.search) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        window.webkit.messageHandlers.\(handlerName).postMessage({ type: 'openLink', href: url.href, background: event.metaKey });
      }, true);
    })();
    """

    /// Answers "would a horizontal scroll at (x, y) move something in the page?"
    /// so trackpad swipes go to the trail only when the page wouldn't use them.
    private static let scrollProbe = """
    (() => {
      window.__wake = window.__wake || {};
      const scrollable = (el, dir) => {
        const room = dir > 0 ? el.scrollWidth - el.clientWidth - el.scrollLeft : el.scrollLeft;
        return room > 1;
      };
      window.__wake.canScrollX = (x, y, dir) => {
        let el = document.elementFromPoint(x, y);
        while (el && el !== document.body && el !== document.documentElement) {
          const style = getComputedStyle(el);
          if (/(auto|scroll)/.test(style.overflowX) && el.scrollWidth > el.clientWidth + 1 && scrollable(el, dir)) return true;
          el = el.parentElement;
        }
        const root = document.scrollingElement;
        return !!root && root.scrollWidth > root.clientWidth + 1 && scrollable(root, dir);
      };
    })();
    """
}

extension WebScripts {
    /// Reports whether media is playing and whether a form has unsaved input, so the
    /// Deck never sinks a tab you'd lose something in.
    fileprivate static let pageState = """
    (() => {
      let unsaved = false;
      const playing = () => [...document.querySelectorAll('video, audio')]
        .some(m => !m.paused && !m.ended && m.readyState > 2);
      const report = () => window.webkit.messageHandlers.\(handlerName).postMessage({ type: 'state', playing: playing(), unsaved });
      ['play', 'playing', 'pause', 'ended'].forEach(name => document.addEventListener(name, report, true));
      document.addEventListener('input', (event) => {
        const t = event.target;
        const editable = t && (t.form || t.isContentEditable || t.tagName === 'TEXTAREA');
        if (editable && !unsaved) { unsaved = true; report(); }
      }, true);
      document.addEventListener('submit', () => { unsaved = false; report(); }, true);
    })();
    """
}

extension WebScripts {
    /// Reports scroll position (as a fraction) when a responsive preview is linked to
    /// this page, and can be told to scroll to one. `applying` stops echo loops.
    fileprivate static let scrollSync = """
    (() => {
      window.__wake = window.__wake || {};
      window.__wake.syncScroll = false;
      let pending = false;
      window.addEventListener('scroll', () => {
        if (!window.__wake.syncScroll || window.__wake.applying || pending) return;
        pending = true;
        requestAnimationFrame(() => {
          pending = false;
          const max = document.scrollingElement.scrollHeight - innerHeight;
          window.webkit.messageHandlers.\(handlerName).postMessage({ type: 'scroll', fraction: max > 0 ? scrollY / max : 0 });
        });
      }, { passive: true });
      window.__wake.scrollToFraction = (fraction) => {
        window.__wake.applying = true;
        scrollTo(0, fraction * (document.scrollingElement.scrollHeight - innerHeight));
        setTimeout(() => { window.__wake.applying = false; }, 80);
      };
    })();
    """
}

/// Routes script messages to the page that sent them. Stateless, so sharing one
/// user-content controller between an opener and its popup is fine.
private final class PageScriptBridge: NSObject, WKScriptMessageHandler {
    let isDeveloper: Bool

    init(isDeveloper: Bool = false) {
        self.isDeveloper = isDeveloper
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let page = message.webView?.navigationDelegate as? BrowserPage else { return }
            isDeveloper ? page.receiveDeveloperMessage(message.body) : page.receive(message.body)
        }
    }
}

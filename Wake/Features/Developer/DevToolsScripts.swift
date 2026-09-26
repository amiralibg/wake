import WebKit

/// The page-side half of Wake's DevTools: DOM tree, element details and highlight,
/// the element picker, storage, performance metrics, audits, resource timing and
/// console evaluation.
///
/// It runs in the page's own world (`.page`) so the console sees the page's globals
/// and `$0` is the element selected in Elements. Nothing is injected until a DevTools
/// pane asks for it: every call carries the installer, which returns at once when
/// `__wakeDT` is already there (a new document simply gets it again).
@MainActor
enum DevToolsScripts {
    static let handlerName = "wakeDT"

    /// Wraps `expression` so the library is installed before it runs.
    static func call(_ expression: String) -> String {
        "(() => { \(library) return (\(expression)); })()"
    }

    /// For `callAsyncJavaScript`: a function body that may `await`.
    static func asyncBody(_ body: String) -> String {
        "\(library)\n\(body)"
    }

    /// `text` as a JavaScript string literal.
    static func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    private static let library = #"""
    if (!window.__wakeDT) (() => {
      const post = (m) => { try { window.webkit.messageHandlers.wakeDT.postMessage(m); } catch {} };
      const OVERLAY = '__wakeDTOverlay';
      let nextId = 1;
      const ids = new WeakMap();
      const nodes = new Map();
      const idOf = (n) => {
        let id = ids.get(n);
        if (!id) { id = nextId++; ids.set(n, id); nodes.set(id, new WeakRef(n)); }
        return id;
      };
      const nodeOf = (id) => {
        const ref = nodes.get(id);
        const node = ref && ref.deref();
        if (!node) nodes.delete(id);
        return node || null;
      };
      const inlineText = (n) => {
        if (n.shadowRoot || n.childNodes.length !== 1) return null;
        const c = n.firstChild;
        return c.nodeType === 3 && c.nodeValue.trim().length <= 80 ? c.nodeValue.trim() : null;
      };
      const childrenOf = (n) => {
        const kids = [];
        if (n.shadowRoot) kids.push(n.shadowRoot);
        const list = n.localName === 'template' ? n.content.childNodes : n.childNodes;
        for (const c of list) {
          if (c.nodeType === 3 && !c.nodeValue.trim()) continue;
          if (c.nodeType === 1 && (c.id === OVERLAY || c.hasAttribute('data-wake-overlay'))) continue;
          kids.push(c);
        }
        return kids;
      };
      const describe = (n) => {
        const d = { id: idOf(n), type: n.nodeType };
        if (n.nodeType === 1) {
          d.tag = n.localName;
          d.attrs = Array.from(n.attributes).slice(0, 40).map(a => [a.name, a.value.slice(0, 400)]);
          const text = inlineText(n);
          if (text !== null && text !== '') { d.text = text; d.childCount = 0; } else d.childCount = childrenOf(n).length;
        } else if (n.nodeType === 3) d.text = n.nodeValue.trim().slice(0, 600);
        else if (n.nodeType === 8) d.text = n.nodeValue.trim().slice(0, 300);
        else if (n.nodeType === 10) d.text = n.name;
        else if (n.nodeType === 11) { d.tag = '#shadow-root'; d.text = n.mode; d.childCount = childrenOf(n).length; }
        return d;
      };
      const parentOf = (n) => n.parentNode || n.host || null;
      const pathTo = (n) => {
        const path = [];
        for (let c = n; c && c !== document; c = parentOf(c)) path.unshift(idOf(c));
        return path;
      };
      const selectorFor = (el) => {
        if (!(el instanceof Element)) return '';
        const parts = [];
        for (let c = el; c && c.nodeType === 1 && parts.length < 6; c = c.parentElement) {
          if (c.id && /^[A-Za-z][\w-]*$/.test(c.id)) { parts.unshift('#' + c.id); break; }
          let part = c.localName;
          const classes = Array.from(c.classList).filter(k => /^[A-Za-z_-][\w-]*$/.test(k)).slice(0, 2);
          if (classes.length) part += '.' + classes.join('.');
          const parent = c.parentElement;
          if (parent) {
            const same = Array.from(parent.children).filter(s => s.localName === c.localName);
            if (same.length > 1) part += `:nth-of-type(${same.indexOf(c) + 1})`;
          }
          parts.unshift(part);
        }
        return parts.join(' > ');
      };
      const px = (v) => parseFloat(v) || 0;

      // WebKit's CSSOM hands back a rule's shorthands (`font`, `margin`, …) as every
      // longhand they set. Fold them back: for each shorthand the rule can serialise,
      // a probe declaration tells which longhands it covers. Broadest shorthands first.
      const SHORTHANDS = ['font', 'background', 'border', 'border-block', 'border-inline', 'border-top', 'border-right', 'border-bottom',
        'border-left', 'border-width', 'border-style', 'border-color', 'border-radius', 'border-image', 'margin', 'margin-block', 'margin-inline',
        'padding', 'padding-block', 'padding-inline', 'inset', 'inset-block', 'inset-inline', 'outline', 'list-style', 'flex', 'flex-flow',
        'grid', 'grid-template', 'grid-area', 'grid-row', 'grid-column', 'gap', 'place-items', 'place-content', 'place-self', 'overflow',
        'overscroll-behavior', 'transition', 'animation', 'text-decoration', 'text-emphasis', 'columns', 'column-rule', 'mask', 'font-variant',
        'font-synthesis', 'white-space', 'container', 'scroll-margin', 'scroll-padding', 'background-position', 'offset'];
      const probe = document.createElement('div').style;
      const coverage = new Map();
      const covers = (shorthand, value) => {
        const key = shorthand + '\u0000' + value;
        if (!coverage.has(key)) {
          probe.cssText = '';
          probe.setProperty(shorthand, value);
          coverage.set(key, Array.from(probe));
        }
        return coverage.get(key);
      };
      const declarations = (style) => {
        const names = Array.from(style);
        const present = new Set(names);
        const owner = new Map();
        for (const shorthand of SHORTHANDS) {
          const value = style.getPropertyValue(shorthand);
          if (!value) continue;
          const longhands = covers(shorthand, value);
          if (longhands.length < 2 || !longhands.every(l => present.has(l) && !owner.has(l))) continue;
          const decl = [shorthand, value + (style.getPropertyPriority(shorthand) ? ' !important' : '')];
          for (const l of longhands) owner.set(l, decl);
        }
        const out = [];
        const emitted = new Set();
        for (const name of names) {
          const decl = owner.get(name);
          if (decl) { if (!emitted.has(decl)) { emitted.add(decl); out.push(decl); } continue; }
          out.push([name, style.getPropertyValue(name) + (style.getPropertyPriority(name) ? ' !important' : '')]);
        }
        return out;
      };

      // Highlight: margin, border, padding and content boxes, like Safari's.
      let overlay = null;
      const ensureOverlay = () => {
        if (overlay && overlay.isConnected) return overlay;
        overlay = document.createElement('div');
        overlay.id = OVERLAY;
        overlay.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483647;';
        overlay.innerHTML = ['m', 'b', 'p', 'c'].map(k => `<div data-k="${k}" style="position:fixed;box-sizing:border-box;"></div>`).join('') +
          '<div data-k="l" style="position:fixed;font:600 11px -apple-system,system-ui;color:#fff;background:#1d1d1f;padding:3px 7px;border-radius:5px;white-space:nowrap;box-shadow:0 2px 8px rgba(0,0,0,.3)"></div>';
        (document.body || document.documentElement).appendChild(overlay);
        return overlay;
      };
      const place = (box, x, y, w, h, color) => {
        box.style.left = x + 'px'; box.style.top = y + 'px';
        box.style.width = Math.max(0, w) + 'px'; box.style.height = Math.max(0, h) + 'px';
        box.style.background = color;
      };
      const highlight = (n) => {
        const el = n && n.nodeType === 3 ? n.parentElement : n;
        if (!(el instanceof Element)) { unhighlight(); return; }
        const o = ensureOverlay();
        o.style.display = 'block';
        const r = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        const m = [px(s.marginTop), px(s.marginRight), px(s.marginBottom), px(s.marginLeft)];
        const b = [px(s.borderTopWidth), px(s.borderRightWidth), px(s.borderBottomWidth), px(s.borderLeftWidth)];
        const p = [px(s.paddingTop), px(s.paddingRight), px(s.paddingBottom), px(s.paddingLeft)];
        const q = (k) => o.querySelector(`[data-k="${k}"]`);
        place(q('m'), r.left - m[3], r.top - m[0], r.width + m[1] + m[3], r.height + m[0] + m[2], 'rgba(246,178,107,.42)');
        place(q('b'), r.left, r.top, r.width, r.height, 'rgba(255,229,153,.55)');
        place(q('p'), r.left + b[3], r.top + b[0], r.width - b[1] - b[3], r.height - b[0] - b[2], 'rgba(147,196,125,.5)');
        place(q('c'), r.left + b[3] + p[3], r.top + b[0] + p[0], r.width - b[1] - b[3] - p[1] - p[3], r.height - b[0] - b[2] - p[0] - p[2], 'rgba(111,168,220,.55)');
        const label = q('l');
        const cls = Array.from(el.classList).slice(0, 3).map(c => '.' + c).join('');
        label.textContent = `${el.localName}${el.id ? '#' + el.id : ''}${cls}  ${Math.round(r.width)} × ${Math.round(r.height)}`;
        const top = r.top - m[0] - 26;
        label.style.left = Math.max(4, Math.min(r.left, innerWidth - 240)) + 'px';
        label.style.top = (top > 4 ? top : Math.min(innerHeight - 26, r.bottom + m[2] + 6)) + 'px';
      };
      const unhighlight = () => { if (overlay) overlay.style.display = 'none'; };

      // Picker: hover highlights, click selects, Esc cancels.
      let picking = null;
      const stopPicking = () => {
        if (!picking) return;
        window.removeEventListener('mousemove', picking.move, true);
        window.removeEventListener('click', picking.click, true);
        window.removeEventListener('mousedown', picking.swallow, true);
        window.removeEventListener('mouseup', picking.swallow, true);
        window.removeEventListener('keydown', picking.key, true);
        picking = null;
        window.__wakePick = false;
      };
      const pick = (on) => {
        stopPicking();
        if (!on) { unhighlight(); return; }
        const move = (e) => { const t = document.elementFromPoint(e.clientX, e.clientY); if (t && t.id !== OVERLAY) highlight(t); };
        const swallow = (e) => { e.preventDefault(); e.stopImmediatePropagation(); };
        const click = (e) => {
          swallow(e);
          const t = document.elementFromPoint(e.clientX, e.clientY);
          stopPicking();
          if (t) { window.__wakeDT.selected = t; post({ type: 'picked', id: idOf(t), path: pathTo(t) }); }
          // Show what was picked for a moment, then get out of the way.
          setTimeout(unhighlight, 900);
        };
        const key = (e) => { if (e.key === 'Escape') { swallow(e); stopPicking(); unhighlight(); post({ type: 'pickEnd' }); } };
        picking = { move, click, swallow, key };
        window.__wakePick = true;
        window.addEventListener('mousemove', move, true);
        window.addEventListener('click', click, true);
        window.addEventListener('mousedown', swallow, true);
        window.addEventListener('mouseup', swallow, true);
        window.addEventListener('keydown', key, true);
      };

      // Console values, previewed the way Safari's console shows them.
      const preview = (v, depth = 0, seen = new Set()) => {
        const t = typeof v;
        if (v === null) return 'null';
        if (v === undefined) return 'undefined';
        if (t === 'string') return depth ? JSON.stringify(v.length > 200 ? v.slice(0, 200) + '…' : v) : v;
        if (t === 'number' || t === 'boolean' || t === 'bigint') return String(v) + (t === 'bigint' ? 'n' : '');
        if (t === 'symbol') return v.toString();
        if (t === 'function') return `ƒ ${v.name || '(anonymous)'}()`;
        if (seen.has(v)) return '[Circular]';
        if (v instanceof Error) {
          const head = `${v.name}: ${v.message}`;
          if (depth || !v.stack) return head;
          // WebKit's stack is frames only; V8's starts with the message again.
          return v.stack.startsWith(head) ? v.stack : head + '\n' + v.stack;
        }
        if (v instanceof Element) {
          const cls = Array.from(v.classList).slice(0, 3).map(c => '.' + c).join('');
          return `<${v.localName}${v.id ? '#' + v.id : ''}${cls}>`;
        }
        if (v instanceof Node) return v.nodeName;
        if (v instanceof Date) return v.toISOString();
        if (v instanceof RegExp) return String(v);
        if (v instanceof Promise) return 'Promise';
        if (depth > 2) return Array.isArray(v) ? `Array(${v.length})` : (v.constructor && v.constructor.name) || 'Object';
        seen.add(v);
        try {
          if (Array.isArray(v) || ArrayBuffer.isView(v)) {
            const items = Array.from(v).slice(0, 100).map(x => preview(x, depth + 1, seen));
            return `[${items.join(', ')}${v.length > 100 ? ', …' : ''}]`;
          }
          if (v instanceof Map) return `Map(${v.size}) {${Array.from(v).slice(0, 30).map(([k, x]) => `${preview(k, depth + 1, seen)} => ${preview(x, depth + 1, seen)}`).join(', ')}}`;
          if (v instanceof Set) return `Set(${v.size}) {${Array.from(v).slice(0, 30).map(x => preview(x, depth + 1, seen)).join(', ')}}`;
          const keys = Object.keys(v);
          const name = v.constructor && v.constructor !== Object ? v.constructor.name + ' ' : '';
          const body = keys.slice(0, 40).map(k => `${k}: ${preview(v[k], depth + 1, seen)}`).join(', ');
          return `${name}{${body}${keys.length > 40 ? ', …' : ''}}`;
        } finally { seen.delete(v); }
      };
      const kindOf = (v) => v === null ? 'null' : v instanceof Error ? 'error' : v instanceof Element ? 'node' : Array.isArray(v) ? 'array' : typeof v;

      const vitals = { lcp: null, cls: 0, inp: null, fcp: null };
      const observe = (type, fn) => {
        try {
          if (!(PerformanceObserver.supportedEntryTypes || []).includes(type)) return false;
          new PerformanceObserver((list) => list.getEntries().forEach(fn)).observe({ type, buffered: true });
          return true;
        } catch { return false; }
      };
      const support = {
        lcp: observe('largest-contentful-paint', (e) => { vitals.lcp = e.startTime; }),
        cls: observe('layout-shift', (e) => { if (!e.hadRecentInput) vitals.cls += e.value; }),
        inp: observe('event', (e) => { if (e.interactionId) vitals.inp = Math.max(vitals.inp || 0, e.duration); }),
        fcp: observe('paint', (e) => { if (e.name === 'first-contentful-paint') vitals.fcp = e.startTime; }),
      };
      try { performance.setResourceTimingBufferSize(3000); } catch {}

      let frames = null;
      const fpsTick = () => { if (!frames) return; frames.count++; requestAnimationFrame(fpsTick); };

      let outlineStyle = null;
      const storageOf = (k) => k === 'session' ? sessionStorage : localStorage;
      const resourceEntry = (e) => ({
        url: e.name, type: e.initiatorType || 'navigation', start: e.startTime, duration: e.duration,
        transfer: e.transferSize || 0, encoded: e.encodedBodySize || 0, decoded: e.decodedBodySize || 0,
        protocol: e.nextHopProtocol || '', status: e.responseStatus || 0,
        blocked: Math.max(0, (e.domainLookupStart || e.startTime) - e.startTime),
        dns: Math.max(0, e.domainLookupEnd - e.domainLookupStart),
        connect: Math.max(0, e.connectEnd - e.connectStart),
        tls: e.secureConnectionStart > 0 ? Math.max(0, e.connectEnd - e.secureConnectionStart) : 0,
        wait: Math.max(0, e.responseStart - e.requestStart),
        download: Math.max(0, e.responseEnd - e.responseStart),
      });

      const api = {
        selected: null,
        document() {
          return { url: location.href, title: document.title, nodes: childrenOf(document).map(describe) };
        },
        children(id) {
          const n = nodeOf(id);
          return n ? childrenOf(n).slice(0, 1000).map(describe) : [];
        },
        select(id) { const n = nodeOf(id); this.selected = n; return !!n; },
        current() { const n = this.selected; return n && n.isConnected ? { id: idOf(n), path: pathTo(n) } : null; },
        details(id) {
          const n = nodeOf(id);
          if (!n) return null;
          this.selected = n;
          const el = n.nodeType === 1 ? n : null;
          const d = { id, path: pathTo(n), node: describe(n), selector: el ? selectorFor(el) : '' };
          if (!el) return d;
          const r = el.getBoundingClientRect();
          const s = getComputedStyle(el);
          d.box = {
            x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height,
            margin: [s.marginTop, s.marginRight, s.marginBottom, s.marginLeft].map(px),
            border: [s.borderTopWidth, s.borderRightWidth, s.borderBottomWidth, s.borderLeftWidth].map(px),
            padding: [s.paddingTop, s.paddingRight, s.paddingBottom, s.paddingLeft].map(px),
            position: s.position, display: s.display, boxSizing: s.boxSizing,
          };
          const computed = [];
          for (let i = 0; i < s.length; i++) { const k = s[i]; computed.push([k, s.getPropertyValue(k)]); }
          computed.sort((a, b) => a[0].localeCompare(b[0]));
          d.computed = computed;
          d.inline = el.getAttribute('style') || '';
          d.hidden = el.style.visibility === 'hidden';
          d.rules = [];
          for (const sheet of Array.from(document.styleSheets)) {
            let rules;
            try { rules = sheet.cssRules; } catch { continue; }
            const walk = (list, media) => {
              for (const rule of Array.from(list)) {
                if (d.rules.length >= 60) return;
                if (rule.selectorText) {
                  try {
                    if (el.matches(rule.selectorText)) d.rules.push({ selector: rule.selectorText, decls: declarations(rule.style), source: (sheet.href || 'inline <style>').split('/').pop(), media });
                  } catch {}
                } else if (rule.cssRules) walk(rule.cssRules, rule.conditionText || rule.media && rule.media.mediaText || media);
              }
            };
            walk(rules, null);
          }
          d.rules.reverse();
          d.html = el.outerHTML.length;
          return d;
        },
        path(id) { const n = nodeOf(id); return n ? pathTo(n) : []; },
        highlight(id) { highlight(nodeOf(id)); return true; },
        unhighlight() { unhighlight(); return true; },
        pick(on) { pick(on); return true; },
        scrollTo(id) { const n = nodeOf(id); const el = n && (n.nodeType === 1 ? n : n.parentElement); if (el) { el.scrollIntoView({ block: 'center', behavior: 'smooth' }); setTimeout(() => highlight(el), 350); } return !!el; },
        setAttribute(id, name, value) { const n = nodeOf(id); if (n && n.setAttribute) n.setAttribute(name, value); return !!n; },
        removeAttribute(id, name) { const n = nodeOf(id); if (n && n.removeAttribute) n.removeAttribute(name); return !!n; },
        setStyle(id, css) { const n = nodeOf(id); if (n && n.setAttribute) n.setAttribute('style', css); return !!n; },
        setText(id, text) { const n = nodeOf(id); if (n) n.textContent = text; return !!n; },
        remove(id) { const n = nodeOf(id); if (n && n.remove) { n.remove(); unhighlight(); } return !!n; },
        toggleHidden(id) { const n = nodeOf(id); if (n && n.style) n.style.visibility = n.style.visibility === 'hidden' ? '' : 'hidden'; return !!n; },
        outerHTML(id) { const n = nodeOf(id); return n ? (n.outerHTML || n.textContent || '') : ''; },
        setOuterHTML(id, html) {
          const n = nodeOf(id);
          if (!n || n.outerHTML === undefined || !n.parentNode) return null;
          const parent = n.parentNode, before = n.previousSibling, after = n.nextSibling;
          n.outerHTML = html;
          // What took its place: the first element among the new nodes, else the first node.
          let first = null;
          for (let c = before ? before.nextSibling : parent.firstChild; c && c !== after; c = c.nextSibling) {
            if (!first) first = c;
            if (c.nodeType === 1) { first = c; break; }
          }
          return first ? { id: idOf(first), path: pathTo(first) } : { id: idOf(parent), path: pathTo(parent) };
        },
        duplicate(id) { const n = nodeOf(id); if (n && n.cloneNode && n.parentNode) n.parentNode.insertBefore(n.cloneNode(true), n.nextSibling); return !!n; },
        search(query) {
          const out = [];
          let list = [];
          try { list = Array.from(document.querySelectorAll(query)); } catch {}
          // Not a selector, or one that matches nothing ("footer" text, "short"): search markup and text.
          if (!list.length) {
            const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_ELEMENT);
            const q = query.toLowerCase();
            for (let n = walker.currentNode; n && list.length < 200; n = walker.nextNode()) {
              const open = '<' + n.localName + Array.from(n.attributes).map(a => ` ${a.name}="${a.value}"`).join('') + '>';
              if (open.toLowerCase().includes(q) || (inlineText(n) || '').toLowerCase().includes(q)) list.push(n);
            }
          }
          for (const n of list.slice(0, 200)) if (n.id !== OVERLAY) out.push({ id: idOf(n), path: pathTo(n), selector: selectorFor(n) });
          return out;
        },

        preview, kindOf,

        storage(kind) {
          const s = storageOf(kind);
          const out = [];
          for (let i = 0; i < s.length; i++) { const k = s.key(i); const v = s.getItem(k) || ''; out.push([k, v.length > 4000 ? v.slice(0, 4000) + '…' : v, v.length]); }
          return out.sort((a, b) => a[0].localeCompare(b[0]));
        },
        storageSet(kind, k, v) { storageOf(kind).setItem(k, v); return true; },
        storageRemove(kind, k) { storageOf(kind).removeItem(k); return true; },
        storageClear(kind) { storageOf(kind).clear(); return true; },

        metrics() {
          const nav = performance.getEntriesByType('navigation')[0];
          const resources = performance.getEntriesByType('resource');
          const byType = {};
          let transfer = 0, decoded = 0;
          for (const e of resources) {
            const t = e.initiatorType || 'other';
            byType[t] = byType[t] || { count: 0, transfer: 0, decoded: 0 };
            byType[t].count++; byType[t].transfer += e.transferSize || 0; byType[t].decoded += e.decodedBodySize || 0;
            transfer += e.transferSize || 0; decoded += e.decodedBodySize || 0;
          }
          let depth = 0;
          const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_ELEMENT);
          for (let n = walker.currentNode, i = 0; n && i < 5000; n = walker.nextNode(), i++) {
            let d = 0; for (let c = n; c; c = c.parentElement) d++;
            if (d > depth) depth = d;
          }
          return {
            ttfb: nav ? nav.responseStart - nav.startTime : null,
            domInteractive: nav ? nav.domInteractive : null,
            dcl: nav ? nav.domContentLoadedEventEnd : null,
            load: nav && nav.loadEventEnd > 0 ? nav.loadEventEnd : null,
            docTransfer: nav ? nav.transferSize : 0,
            protocol: nav ? nav.nextHopProtocol : '',
            navType: nav ? nav.type : '',
            fcp: vitals.fcp, lcp: vitals.lcp, cls: support.cls ? vitals.cls : null, inp: vitals.inp,
            support,
            requests: resources.length + 1, transfer: transfer + (nav ? nav.transferSize : 0), decoded,
            byType,
            domNodes: document.getElementsByTagName('*').length, domDepth: depth,
            scripts: document.scripts.length, styleSheets: document.styleSheets.length,
            images: document.images.length, iframes: document.getElementsByTagName('iframe').length,
            dpr: devicePixelRatio, viewport: `${innerWidth} × ${innerHeight}`,
          };
        },
        fps() {
          const now = performance.now();
          if (!frames) { frames = { count: 0, since: now }; requestAnimationFrame(fpsTick); return null; }
          const value = frames.count * 1000 / Math.max(1, now - frames.since);
          frames.count = 0; frames.since = now;
          return value;
        },
        fpsStop() { frames = null; return true; },
        resources(since) {
          const list = performance.getEntriesByType('resource');
          const out = list.slice(since).map(resourceEntry);
          if (since === 0) { const nav = performance.getEntriesByType('navigation')[0]; if (nav) out.unshift(resourceEntry(nav)); }
          return { total: list.length, entries: out };
        },
        audits() {
          const out = [];
          const add = (id, title, state, detail, count) => out.push({ id, title, state, detail: detail || '', count: count || 0 });
          const qs = (s) => Array.from(document.querySelectorAll(s));
          add('title', 'Document has a title', document.title.trim() ? 'pass' : 'fail', document.title.trim() ? document.title : 'Add a <title> element.');
          const lang = document.documentElement.getAttribute('lang');
          add('lang', '<html> has a lang attribute', lang ? 'pass' : 'fail', lang ? `lang="${lang}"` : 'Screen readers need it to pick a voice.');
          const viewport = document.querySelector('meta[name="viewport"]');
          add('viewport', 'Has a viewport meta tag', viewport ? 'pass' : 'fail', viewport ? viewport.content : 'Without it, phones render at desktop width.');
          const desc = document.querySelector('meta[name="description"]');
          add('description', 'Has a meta description', desc && desc.content.trim() ? 'pass' : 'warn', desc ? desc.content.slice(0, 140) : 'Search engines show it under the title.');
          const icon = document.querySelector("link[rel~='icon'], link[rel='apple-touch-icon']");
          add('favicon', 'Declares a favicon', icon ? 'pass' : 'warn', icon ? icon.href : 'Falls back to /favicon.ico.');
          const h1 = qs('h1').length;
          add('h1', 'Has one top-level heading', h1 === 1 ? 'pass' : 'warn', `${h1} <h1> element${h1 === 1 ? '' : 's'}.`);
          const noAlt = qs('img:not([alt])');
          add('alt', 'Images have alt text', noAlt.length ? 'fail' : 'pass', noAlt.length ? noAlt.slice(0, 3).map(i => i.currentSrc || i.src).join('\n') : `${document.images.length} images checked.`, noAlt.length);
          const unsized = qs('img:not([width]):not([height])').filter(i => !i.style.width && !i.style.aspectRatio && getComputedStyle(i).aspectRatio === 'auto');
          add('sized', 'Images reserve their space', unsized.length ? 'warn' : 'pass', unsized.length ? 'Images without width and height shift the layout when they load.' : 'No unsized images.', unsized.length);
          const oversized = Array.from(document.images).filter(i => i.complete && i.clientWidth > 0 && i.naturalWidth > i.clientWidth * devicePixelRatio * 1.5 && i.naturalWidth > 400);
          add('oversized', 'Images are sized for display', oversized.length ? 'warn' : 'pass', oversized.length ? oversized.slice(0, 3).map(i => `${i.naturalWidth}px shown at ${i.clientWidth}px: ${(i.currentSrc || i.src).split('/').pop()}`).join('\n') : 'No oversized images.', oversized.length);
          const lazy = Array.from(document.images).filter(i => i.getBoundingClientRect().top > innerHeight * 2 && i.loading !== 'lazy');
          add('lazy', 'Offscreen images load lazily', lazy.length > 3 ? 'warn' : 'pass', lazy.length ? `${lazy.length} images far below the fold load eagerly; add loading="lazy".` : 'Nothing to defer.', lazy.length);
          const blocking = qs('head script[src]:not([async]):not([defer]):not([type="module"])');
          add('blocking', 'No render-blocking scripts', blocking.length ? 'warn' : 'pass', blocking.length ? blocking.slice(0, 4).map(s => s.src.split('/').pop()).join('\n') : 'Scripts in <head> are async, deferred or modules.', blocking.length);
          const resources = performance.getEntriesByType('resource');
          if (location.protocol === 'https:') {
            const mixed = resources.filter(e => e.name.startsWith('http:'));
            add('mixed', 'No mixed content', mixed.length ? 'fail' : 'pass', mixed.length ? mixed.slice(0, 3).map(e => e.name).join('\n') : 'Everything loads over HTTPS.', mixed.length);
          }
          const uncompressed = resources.filter(e => ['script', 'link', 'css'].includes(e.initiatorType) && e.encodedBodySize > 20000 && e.encodedBodySize >= e.decodedBodySize * 0.95);
          add('compression', 'Text is compressed', uncompressed.length ? 'warn' : 'pass', uncompressed.length ? uncompressed.slice(0, 3).map(e => e.name.split('/').pop()).join('\n') : 'Scripts and styles are served compressed (where the server reports sizes).', uncompressed.length);
          const js = resources.filter(e => e.initiatorType === 'script').reduce((a, e) => a + (e.decodedBodySize || 0), 0);
          add('jsweight', 'JavaScript weight', js > 2e6 ? 'fail' : js > 8e5 ? 'warn' : 'pass', `${(js / 1024).toFixed(0)} KB of script (uncompressed).`);
          const old = resources.filter(e => e.nextHopProtocol === 'http/1.1');
          add('http2', 'Resources use HTTP/2 or later', old.length > 5 ? 'warn' : 'pass', old.length ? `${old.length} requests over HTTP/1.1.` : 'Multiplexed connections.', old.length);
          const size = document.getElementsByTagName('*').length;
          add('domsize', 'DOM size', size > 3000 ? 'fail' : size > 1500 ? 'warn' : 'pass', `${size} elements.`);
          const unlabeled = qs('input:not([type=hidden]):not([type=submit]):not([type=button]), select, textarea').filter(i => !i.labels?.length && !i.getAttribute('aria-label') && !i.getAttribute('aria-labelledby') && !i.title);
          add('labels', 'Form fields have labels', unlabeled.length ? 'fail' : 'pass', unlabeled.length ? `${unlabeled.length} fields without a label.` : 'Every field is labelled.', unlabeled.length);
          const nameless = qs('button, a[href]').filter(b => !(b.textContent || '').trim() && !b.getAttribute('aria-label') && !b.title && !b.querySelector('img[alt]:not([alt=""]), svg title'));
          add('names', 'Buttons and links have names', nameless.length ? 'fail' : 'pass', nameless.length ? `${nameless.length} without text or aria-label.` : 'All named.', nameless.length);
          const tiny = qs('a[href], button').filter(b => { const r = b.getBoundingClientRect(); return r.width > 0 && r.height > 0 && (r.width < 24 || r.height < 24); });
          add('targets', 'Tap targets are at least 24px', tiny.length > 5 ? 'warn' : 'pass', `${tiny.length} small targets.`, tiny.length);
          return out;
        },

        outlines(on) {
          if (on && !outlineStyle) {
            outlineStyle = document.createElement('style');
            outlineStyle.dataset.wakeOverlay = '';
            outlineStyle.textContent = '*:not(#__wakeDTOverlay):not(#__wakeDTOverlay *){outline:1px solid rgba(255,59,48,.45)!important;outline-offset:-1px}';
            document.documentElement.appendChild(outlineStyle);
          } else if (!on && outlineStyle) { outlineStyle.remove(); outlineStyle = null; }
          return on;
        },
        styles(disabled) { for (const s of Array.from(document.styleSheets)) { try { s.disabled = disabled; } catch {} } return disabled; },
        designMode(on) { document.designMode = on ? 'on' : 'off'; return on; },
        sources() {
          const scripts = Array.from(document.scripts).map((s, i) => s.src ? { url: s.src, kind: 'script', index: i, module: s.type === 'module' } : { url: null, kind: 'script', index: i, module: s.type === 'module', size: s.textContent.length });
          const styles = Array.from(document.styleSheets).map((s, i) => s.href ? { url: s.href, kind: 'style', index: i } : { url: null, kind: 'style', index: i, size: s.ownerNode ? s.ownerNode.textContent.length : 0 });
          const seen = new Set([...scripts, ...styles].map(s => s.url).filter(Boolean));
          const extra = performance.getEntriesByType('resource').filter(e => ['script', 'css', 'link'].includes(e.initiatorType) && !seen.has(e.name) && /\.(m?js|css)(\?|$)/.test(e.name))
            .map(e => ({ url: e.name, kind: e.name.includes('.css') ? 'style' : 'script', index: -1 }));
          return [...scripts, ...styles, ...extra];
        },
        inlineSource(kind, index) {
          if (kind === 'script') { const s = document.scripts[index]; return s ? s.textContent : ''; }
          const sheet = document.styleSheets[index];
          return sheet && sheet.ownerNode ? sheet.ownerNode.textContent : '';
        },
      };
      Object.defineProperty(window, '__wakeDT', { value: api, enumerable: false, configurable: true });
      // Console helpers, only where the page hasn't defined its own. Assigning one
      // (a page loading jQuery later) replaces the helper with the page's value.
      const define = (name, get) => {
        if (name in window) return;
        Object.defineProperty(window, name, { get, configurable: true, enumerable: false,
          set(value) { Object.defineProperty(window, name, { value, writable: true, configurable: true, enumerable: true }); } });
      };
      define('$0', () => api.selected);
      define('$$', () => (s, root) => Array.from((root || document).querySelectorAll(s)));
      define('$', () => (s, root) => (root || document).querySelector(s));
    })();
    """#

    /// Evaluates console input in the page. Declarations stay global (indirect eval),
    /// promises are awaited, and `await` works at the top level.
    static let evaluate = asyncBody(#"""
    let value;
    try {
      if (/\bawait\b/.test(code)) {
        try { value = await (0, eval)(`(async () => (${code}\n))()`); }
        catch (e) { if (!(e instanceof SyntaxError)) throw e; value = await (0, eval)(`(async () => {${code}\n})()`); }
      } else {
        value = (0, eval)(code);
        if (value instanceof Promise) value = await value;
      }
      if (value instanceof Element) window.__wakeDT.selected = value;
      return { ok: true, text: window.__wakeDT.preview(value), kind: window.__wakeDT.kindOf(value) };
    } catch (error) {
      return { ok: false, text: window.__wakeDT.preview(error), kind: 'error' };
    }
    """#)

    /// Suggestions for the console prompt: properties of the object before the last dot.
    static let completions = asyncBody(#"""
    const match = /([\w$.\[\]'"]*?)\.?([\w$]*)$/.exec(code);
    let target = window, prefix = code;
    if (match && code.includes('.')) {
      prefix = match[2];
      try { target = (0, eval)(match[1]); } catch { return []; }
    }
    if (target === null || target === undefined) return [];
    const names = new Set();
    for (let o = Object(target), i = 0; o && i < 4; o = Object.getPrototypeOf(o), i++) Object.getOwnPropertyNames(o).forEach(n => names.add(n));
    return Array.from(names).filter(n => n.startsWith(prefix) && /^[A-Za-z_$][\w$]*$/.test(n)).sort().slice(0, 12);
    """#)

    /// Storage the page can list only asynchronously.
    static let asyncStorage = asyncBody(#"""
    const out = { databases: [], caches: [], workers: [] };
    try { if (indexedDB.databases) out.databases = (await indexedDB.databases()).map(d => ({ name: d.name, version: d.version })); } catch {}
    try { if (window.caches) for (const name of await caches.keys()) { const c = await caches.open(name); out.caches.push({ name, count: (await c.keys()).length }); } } catch {}
    try { if (navigator.serviceWorker) out.workers = (await navigator.serviceWorker.getRegistrations()).map(r => ({ scope: r.scope, script: (r.active || r.waiting || r.installing || {}).scriptURL || '', state: (r.active || r.waiting || r.installing || {}).state || '' })); } catch {}
    return out;
    """#)

    /// "deleted", "blocked" (the page still has it open; the delete waits), or "error".
    static let deleteDatabase = asyncBody(#"""
    return await new Promise((resolve) => {
      const r = indexedDB.deleteDatabase(name);
      r.onsuccess = () => resolve('deleted');
      r.onerror = () => resolve('error');
      r.onblocked = () => resolve('blocked');
    });
    """#)

    static let deleteCache = asyncBody("return await caches.delete(name);")

    static let unregisterWorker = asyncBody(#"""
    for (const r of await navigator.serviceWorker.getRegistrations()) if (r.scope === name) await r.unregister();
    return true;
    """#)

    /// Fetches a script or stylesheet with the page's cookies. Runs in Wake's isolated
    /// world, whose `fetch` isn't the one developer mode wraps, so DevTools' own
    /// requests don't show up in Network.
    static let fetchSource = #"""
    const response = await fetch(url, { credentials: 'include', cache: 'force-cache' });
    return await response.text();
    """#
}

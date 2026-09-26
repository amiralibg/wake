import Foundation

/// Scripts run on demand: the component inspector and the JSON viewer.
enum DevOverlayScripts {
    /// Hover to see the component under the pointer (React, Vue, Svelte), its size and
    /// source file; click to open it in the editor; Esc to stop. Runs in the page world,
    /// because framework internals (`__reactFiber$…`, `__vueParentComponent`) live there.
    ///
    /// Limitation: React only records source files in development builds, and React 19
    /// dropped `_debugSource`, so there it shows the component name without a file.
    static let inspector = """
    (() => {
      if (window.__wakeInspect) return;
      const post = (m) => { try { window.webkit.messageHandlers.wakeDev.postMessage(m); } catch {} };
      let box, label, active = false, current = null, priorCursor = null;
      const describe = (el) => {
        const key = Object.keys(el).find(k => k.startsWith('__reactFiber$') || k.startsWith('__reactInternalInstance$'));
        if (key) {
          for (let f = el[key]; f; f = f.return) {
            const t = f.type;
            const fn = typeof t === 'function' ? t : (t && (t.render || t.type));
            const name = t && (t.displayName || (fn && (fn.displayName || fn.name)));
            if (typeof fn === 'function' && name) {
              const src = f._debugSource;
              return { framework: 'React', name, file: src && src.fileName, line: src && src.lineNumber };
            }
          }
        }
        for (let n = el; n; n = n.parentElement) {
          const c = n.__vueParentComponent;
          if (c) { const t = c.type || {}; return { framework: 'Vue', name: t.name || t.__name || (t.__file || '').split('/').pop(), file: t.__file }; }
        }
        for (let n = el; n; n = n.parentElement) {
          const meta = n.__svelte_meta;
          if (meta && meta.loc) return { framework: 'Svelte', name: (meta.loc.file || '').split('/').pop().replace('.svelte', ''), file: meta.loc.file, line: meta.loc.line + 1 };
        }
        return null;
      };
      const ensure = () => {
        if (box) return;
        box = document.createElement('div');
        label = document.createElement('div');
        Object.assign(box.style, { position: 'fixed', pointerEvents: 'none', zIndex: 2147483647, border: '1.5px solid #0A84FF',
          background: 'rgba(10,132,255,0.12)', borderRadius: '4px', transition: 'all 60ms ease-out' });
        Object.assign(label.style, { position: 'fixed', pointerEvents: 'none', zIndex: 2147483647, font: '600 11px -apple-system, system-ui',
          color: '#fff', background: '#0A84FF', padding: '3px 7px', borderRadius: '6px', whiteSpace: 'nowrap', boxShadow: '0 2px 8px rgba(0,0,0,.25)' });
        // Tagged so the DevTools element tree leaves Wake's own overlay out.
        box.dataset.wakeOverlay = ''; label.dataset.wakeOverlay = '';
        document.documentElement.append(box, label);
      };
      const move = (e) => {
        const el = e.target;
        if (!(el instanceof Element) || el === box || el === label) return;
        current = el;
        const r = el.getBoundingClientRect();
        const info = describe(el);
        Object.assign(box.style, { left: r.left + 'px', top: r.top + 'px', width: r.width + 'px', height: r.height + 'px', display: 'block' });
        const size = `${Math.round(r.width)}×${Math.round(r.height)}`;
        const file = info && info.file ? ` · ${info.file.split('/').slice(-2).join('/')}${info.line ? ':' + info.line : ''}` : '';
        label.textContent = info ? `<${info.name}> ${size}${file}` : `${el.tagName.toLowerCase()} ${size}`;
        Object.assign(label.style, { left: Math.max(4, r.left) + 'px', top: (r.top > 26 ? r.top - 24 : r.bottom + 4) + 'px', display: 'block' });
      };
      const click = (e) => {
        e.preventDefault(); e.stopPropagation();
        const info = current && describe(current);
        post({ type: 'inspect', framework: info && info.framework, name: info && info.name, file: info && info.file, line: info && info.line });
      };
      const key = (e) => { if (e.key === 'Escape') { stop(); post({ type: 'inspectEnd' }); } };
      const start = () => {
        if (active) return;
        active = true; ensure();
        document.addEventListener('mousemove', move, true);
        document.addEventListener('click', click, true);
        document.addEventListener('keydown', key, true);
        const root = document.documentElement;
        priorCursor = root.hasAttribute('style') ? root.style.cursor : null;
        root.style.cursor = 'crosshair';
      };
      const stop = () => {
        active = false;
        document.removeEventListener('mousemove', move, true);
        document.removeEventListener('click', click, true);
        document.removeEventListener('keydown', key, true);
        // Leave the page's DOM as it was: no overlay nodes, no empty style attribute.
        if (box) { box.remove(); label.remove(); box = null; label = null; }
        const root = document.documentElement;
        if (priorCursor === null) { root.style.removeProperty('cursor'); if (!root.getAttribute('style')) root.removeAttribute('style'); }
        else root.style.cursor = priorCursor;
      };
      window.__wakeInspect = { start, stop };
    })();
    """

    /// Replaces a raw JSON document with a formatted, collapsible tree.
    /// Returns true if the page was JSON.
    static let jsonViewer = """
    (() => {
      let data;
      try { data = JSON.parse(document.body ? document.body.innerText : ''); } catch { return false; }
      const esc = (s) => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
      const leaf = (v) => {
        if (v === null) return '<span class="n">null</span>';
        if (typeof v === 'string') return /^https?:\\/\\//.test(v) ? `<a class="s" href="${esc(v)}">"${esc(v)}"</a>` : `<span class="s">"${esc(v)}"</span>`;
        if (typeof v === 'number') return `<span class="d">${v}</span>`;
        if (typeof v === 'boolean') return `<span class="b">${v}</span>`;
        return esc(v);
      };
      const node = (v, key, depth) => {
        const name = key === undefined ? '' : `<span class="k">${esc(key)}</span>: `;
        if (v === null || typeof v !== 'object') return `<div class="row">${name}${leaf(v)}</div>`;
        const isArray = Array.isArray(v);
        const entries = isArray ? v.map((x, i) => [i, x]) : Object.entries(v);
        const summary = isArray ? `Array(${entries.length})` : `{${entries.length}}`;
        const children = entries.map(([k, x]) => node(x, k, depth + 1)).join('');
        return `<details ${depth < 2 ? 'open' : ''}><summary>${name}<span class="t">${summary}</span></summary><div class="kids">${children}</div></details>`;
      };
      document.head.innerHTML = `<meta name="color-scheme" content="light dark"><style>
        body { font: 12.5px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; margin: 0; padding: 18px 22px; }
        summary { cursor: pointer; list-style: none; } summary::-webkit-details-marker { display: none; }
        summary::before { content: '▸'; display: inline-block; width: 14px; color: #8e8e93; transition: transform .12s; }
        details[open] > summary::before { transform: rotate(90deg); }
        .kids { padding-left: 16px; border-left: 1px solid rgba(128,128,128,.2); margin-left: 5px; }
        .row { padding-left: 14px; } .k { color: #b04ad8; } .s { color: #c4411a; } .d { color: #1c63d4; }
        .b { color: #0f8a6c; } .n { color: #8e8e93; } .t { color: #8e8e93; } a.s { text-decoration: none; }
        @media (prefers-color-scheme: dark) { .k { color: #d38cf5; } .s { color: #ff9f6b; } .d { color: #74b3ff; } .b { color: #5ed4b0; } }
      </style>`;
      document.body.innerHTML = node(data, undefined, 0);
      document.title = document.title || location.pathname;
      return true;
    })()
    """
}

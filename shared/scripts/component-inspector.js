// Hover to see the component under the pointer (React, Vue, Svelte), its size and
// source file; click to open it in the editor; Esc to stop. Runs in the page world,
// because framework internals (`__reactFiber$…`, `__vueParentComponent`) live there.
// Installs `window.__wakeInspect = { start, stop }`.
//
// Limitation: React only records source files in development builds, and React 19
// dropped `_debugSource`, so there it shows the component name without a file.
// params: { channel }
if (window.__wakeInspect) return;
const post = (m) => wake.post(params.channel, m);
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

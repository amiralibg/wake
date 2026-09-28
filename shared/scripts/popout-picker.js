// Pop Out's element picker. Hover to outline an element, ↑/↓ to widen or narrow
// the choice, click to pick, Esc to cancel. Posts `popOutPick` with a CSS selector
// and the element's rect in document coordinates (CSS pixels).
// params: { channel }
if (window.__wakePick) window.__wakePick.stop();
const post = (data) => wake.post(params.channel, data);
const box = document.createElement('div');
const label = document.createElement('div');
Object.assign(box.style, { position: 'fixed', zIndex: 2147483647, pointerEvents: 'none', display: 'none',
  border: '2px solid #0A84FF', background: 'rgba(10,132,255,0.10)', borderRadius: '6px',
  boxShadow: '0 0 0 9999px rgba(0,0,0,0.18)', transition: 'all 70ms ease-out' });
Object.assign(label.style, { position: 'fixed', zIndex: 2147483647, pointerEvents: 'none', display: 'none',
  font: '600 11px -apple-system, system-ui, sans-serif', color: '#fff', background: '#0A84FF',
  padding: '3px 8px', borderRadius: '6px', whiteSpace: 'nowrap' });
box.dataset.wakeOverlay = ''; label.dataset.wakeOverlay = '';
document.documentElement.append(box, label);

const big = (el) => { const r = el.getBoundingClientRect(); return r.width >= 40 && r.height >= 20; };
const pickable = (el) => { while (el && el !== document.body && el !== document.documentElement) { if (big(el)) return el; el = el.parentElement; } return null; };
// What a person would call it: alt text, a label, a heading. Empty if none.
const nameOf = (el) => {
  const text = el.getAttribute('aria-label') || (el.tagName === 'IMG' ? el.getAttribute('alt') : '')
    || ((el.querySelector('h1, h2, h3, h4, caption, figcaption') || {}).innerText || '');
  return text.trim().split('\n')[0].slice(0, 60);
};
const describe = (el) => {
  const aria = el.getAttribute('aria-label');
  if (aria) return aria.slice(0, 40);
  const heading = el.querySelector('h1, h2, h3, h4');
  if (heading && heading.innerText.trim()) return heading.innerText.trim().slice(0, 40);
  let text = el.tagName.toLowerCase();
  if (el.id) text += '#' + el.id;
  else if (el.classList.length) text += '.' + [...el.classList].slice(0, 2).join('.');
  return text;
};
const selectorFor = (el) => {
  const parts = [];
  while (el && el.nodeType === 1 && el !== document.body && el !== document.documentElement) {
    if (el.id && document.querySelectorAll('#' + CSS.escape(el.id)).length === 1) {
      parts.unshift('#' + CSS.escape(el.id));
      return parts.join(' > ');
    }
    let part = el.tagName.toLowerCase();
    const parent = el.parentElement;
    if (parent) {
      const same = [...parent.children].filter(c => c.tagName === el.tagName);
      if (same.length > 1) part += `:nth-of-type(${same.indexOf(el) + 1})`;
    }
    parts.unshift(part);
    el = parent;
  }
  return 'body > ' + parts.join(' > ');
};

let current = null;
const draw = () => {
  if (!current) return;
  const r = current.getBoundingClientRect();
  Object.assign(box.style, { display: 'block', left: r.left - 2 + 'px', top: r.top - 2 + 'px', width: r.width + 4 + 'px', height: r.height + 4 + 'px' });
  label.textContent = `${describe(current)} · ${Math.round(r.width)}×${Math.round(r.height)}`;
  Object.assign(label.style, { display: 'block', left: Math.max(6, r.left) + 'px', top: (r.top > 30 ? r.top - 26 : Math.min(innerHeight - 26, r.bottom + 6)) + 'px' });
};
const move = (e) => { const el = pickable(document.elementFromPoint(e.clientX, e.clientY)); if (el && el !== current) { current = el; draw(); } };
const swallow = (e) => { e.preventDefault(); e.stopImmediatePropagation(); };
const click = (e) => {
  swallow(e);
  if (!current) return;
  const r = current.getBoundingClientRect();
  post({ type: 'popOutPick', selector: selectorFor(current), label: nameOf(current),
         x: r.left + scrollX, y: r.top + scrollY, w: r.width, h: r.height, layoutWidth: document.documentElement.clientWidth });
  stop();
};
const key = (e) => {
  if (e.key === 'Escape') { swallow(e); post({ type: 'popOutCancel' }); stop(); }
  else if (e.key === 'ArrowUp' && current) {
    swallow(e);
    const up = pickable(current.parentElement);
    if (up) { current = up; draw(); }
  } else if (e.key === 'ArrowDown' && current) {
    swallow(e);
    const down = [...current.children].find(big);
    if (down) { current = down; draw(); }
  }
};
const events = [['mousemove', move], ['click', click], ['mousedown', swallow], ['mouseup', swallow], ['keydown', key], ['scroll', draw]];
events.forEach(([name, fn]) => window.addEventListener(name, fn, true));
const stop = () => {
  events.forEach(([name, fn]) => window.removeEventListener(name, fn, true));
  box.remove(); label.remove();
  delete window.__wakePick;
};
window.__wakePick = { stop };

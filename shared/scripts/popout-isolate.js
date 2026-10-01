// Runs in a popped-out copy of a page: finds the element (waiting for pages that
// render late), hides fixed and sticky chrome around it, and keeps it scrolled to
// the top of a viewport exactly its height. Reports the element's size as it changes.
// params: { channel, selector }
const selector = params.selector;
const post = (data) => wake.post(params.channel, data);
let el = null, tries = 0, last = '';
const hideChrome = () => {
  for (const node of document.body.querySelectorAll('*')) {
    if (node === el || node.contains(el) || el.contains(node)) continue;
    const position = getComputedStyle(node).position;
    if (position === 'fixed' || position === 'sticky') node.style.setProperty('visibility', 'hidden', 'important');
  }
};
const report = () => {
  const r = el.getBoundingClientRect();
  const key = [Math.round(r.left + scrollX), Math.round(r.width), Math.round(r.height)].join();
  if (key === last) return;
  last = key;
  post({ type: 'rect', x: r.left + scrollX, w: r.width, h: r.height });
};
const pin = () => {
  if (!el) return;
  const top = el.getBoundingClientRect().top + scrollY;
  if (Math.abs(scrollY - top) > 0.5) window.scrollTo({ top, behavior: 'instant' });
  report();
};
const find = () => {
  el = document.querySelector(selector);
  if (!el) {
    if (++tries < 60) setTimeout(find, 250); else post({ type: 'lost' });
    return;
  }
  const root = document.documentElement;
  // Room to scroll an element near the page's end to the top of the viewport.
  root.style.setProperty('padding-bottom', '100vh', 'important');
  root.style.setProperty('scrollbar-width', 'none', 'important');
  root.style.setProperty('overflow', 'hidden', 'important');
  hideChrome();
  setTimeout(hideChrome, 2000);
  new ResizeObserver(pin).observe(el);
  window.addEventListener('scroll', pin, { passive: true });
  pin();
  post({ type: 'found' });
};
find();
// Single-page apps re-render: follow the element if it's replaced.
setInterval(() => { if (el && !el.isConnected) { el = null; tries = 0; last = ''; find(); } }, 2000);

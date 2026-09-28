// Link clicks open a new trail column instead of navigating in place.
// Capture phase on `window` runs before any page handler, which matters because
// single-page apps (React Router, Next, Turbo…) otherwise swallow the click and
// pushState, and the engine never sees a navigation.
// ⌥-click navigates in place; ⌘-click opens the column without focusing it.
// params: { channel }
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
  if (target && target !== '_self' && target !== '_top') return; // _blank is a popup; the engine asks the host natively.
  const raw = anchor instanceof SVGAElement ? anchor.href.baseVal : anchor.getAttribute('href');
  if (!raw || raw.startsWith('#') || raw.startsWith('javascript:')) return;
  let url;
  try { url = new URL(raw, location.href); } catch { return; }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return;
  const here = new URL(location.href);
  if (url.origin === here.origin && url.pathname === here.pathname && url.search === here.search) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  wake.post(params.channel, { type: 'openLink', href: url.href, background: event.metaKey });
}, true);

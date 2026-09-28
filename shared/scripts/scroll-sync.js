// Reports scroll position (as a fraction) when a responsive preview is linked to
// this page, and can be told to scroll to one. `applying` stops echo loops.
// params: { channel }
window.__wake = window.__wake || {};
window.__wake.syncScroll = false;
let pending = false;
window.addEventListener('scroll', () => {
  if (!window.__wake.syncScroll || window.__wake.applying || pending) return;
  pending = true;
  requestAnimationFrame(() => {
    pending = false;
    const max = document.scrollingElement.scrollHeight - innerHeight;
    wake.post(params.channel, { type: 'scroll', fraction: max > 0 ? scrollY / max : 0 });
  });
}, { passive: true });
window.__wake.scrollToFraction = (fraction) => {
  window.__wake.applying = true;
  scrollTo(0, fraction * (document.scrollingElement.scrollHeight - innerHeight));
  setTimeout(() => { window.__wake.applying = false; }, 80);
};

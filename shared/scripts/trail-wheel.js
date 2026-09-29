// Windows and Linux only. Wheel input that belongs to the trail, not the page.
// The macOS app routes this natively (TrailGestureRouter) before WebKit sees the
// event; WebView2 has no such hook, so on the desktop apps the page reports it.
// - ⇧ + mouse wheel: one column per notch ({ type: 'trailStep', direction }).
// - Horizontal trackpad scrolling the page can't use at the pointer: the trail
//   follows the fingers ({ type: 'trailPan', dx }), then snaps when it stops
//   ({ type: 'trailPanEnd' }).
// The host turns these off with `window.__wake.trailWheel = false` (Settings ▸ General).
// params: { channel }
window.__wake = window.__wake || {};
if (window.__wake.trailWheel !== undefined) return;
window.__wake.trailWheel = true;

let panning = false;
let endTimer = 0;
let lastStep = 0;

const canScrollX = (x, y, dir) => (window.__wake.canScrollX ? window.__wake.canScrollX(x, y, dir) : false);

window.addEventListener('wheel', (event) => {
  if (!window.__wake.trailWheel || window.__wakePick) return;
  // Pinch-zoom on trackpads arrives as ctrl + wheel.
  if (event.ctrlKey) return;
  const dx = event.deltaX;
  const dy = event.deltaY;

  // Chromium turns ⇧ + wheel into deltaX; WebKitGTK may keep deltaY.
  const notch = Math.abs(dy) >= Math.abs(dx) ? dy : dx;
  if (event.shiftKey && (event.deltaMode !== 0 || Math.abs(notch) >= 50)) {
    // A mouse notch (line mode, or a big pixel step). Several events per notch on
    // some drivers: one step per 180 ms at most.
    event.preventDefault();
    event.stopImmediatePropagation();
    const now = performance.now();
    if (now - lastStep < 180) return;
    lastStep = now;
    wake.post(params.channel, { type: 'trailStep', direction: notch > 0 ? 1 : -1 });
    return;
  }

  if (panning || (Math.abs(dx) > Math.abs(dy) * 1.5 && Math.abs(dx) > 2 && !canScrollX(event.clientX, event.clientY, dx > 0 ? 1 : -1))) {
    event.preventDefault();
    event.stopImmediatePropagation();
    panning = true;
    const pixels = event.deltaMode === 1 ? dx * 16 : dx;
    wake.post(params.channel, { type: 'trailPan', dx: pixels });
    clearTimeout(endTimer);
    endTimer = setTimeout(() => {
      panning = false;
      wake.post(params.channel, { type: 'trailPanEnd' });
    }, 140);
  }
}, { capture: true, passive: false });

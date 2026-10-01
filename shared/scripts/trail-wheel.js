// Windows and Linux only. Wheel input that belongs to the trail, not the page.
// The macOS app routes this natively (TrailGestureRouter) before WebKit sees the
// event; WebView2 has no such hook, so on the desktop apps the page reports it.
// - ⇧ + mouse wheel: one column per notch ({ type: 'trailStep', direction }).
// - Horizontal trackpad scrolling the page can't use at the pointer: the trail
//   follows the fingers ({ type: 'trailPan', dx }), then snaps when it stops
//   ({ type: 'trailPanEnd' }).
// The host turns these off with `window.__wake.trailWheel = false` (Settings ▸ General).
//
// Scrolling stays smooth: a wheel listener that may cancel the scroll makes the
// engine wait for the page's JavaScript on every wheel event, which stutters on
// busy pages. So the always-on listener is passive, and the cancelling one is
// attached only while Shift is down (⇧ + wheel would otherwise scroll the page
// sideways too).
// params: { channel }
window.__wake = window.__wake || {};
if (window.__wake.trailWheel !== undefined) return;
window.__wake.trailWheel = true;

let panning = false;
let endTimer = 0;
let lastStep = 0;
let stepping = false;

const canScrollX = (x, y, dir) => (window.__wake.canScrollX ? window.__wake.canScrollX(x, y, dir) : false);
const active = (event) => window.__wake.trailWheel && !window.__wakePick && !event.ctrlKey; // ctrl + wheel is pinch-zoom

// Chromium turns ⇧ + wheel into deltaX; WebKitGTK may keep deltaY.
const notchOf = (event) => (Math.abs(event.deltaY) >= Math.abs(event.deltaX) ? event.deltaY : event.deltaX);
// A mouse notch: line mode, or a big pixel step.
const isNotch = (event) => event.deltaMode !== 0 || Math.abs(notchOf(event)) >= 50;

function step(event) {
  if (!active(event) || !event.shiftKey || !isNotch(event)) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  // Several events per notch on some drivers: one step per 180 ms at most.
  const now = performance.now();
  if (now - lastStep < 180) return;
  lastStep = now;
  wake.post(params.channel, { type: 'trailStep', direction: notchOf(event) > 0 ? 1 : -1 });
}

function setStepping(on) {
  if (on === stepping) return;
  stepping = on;
  if (on) window.addEventListener('wheel', step, { capture: true, passive: false });
  else window.removeEventListener('wheel', step, { capture: true });
}

// Shift seen on the keyboard (the page has focus) or on the pointer (it hasn't).
window.addEventListener('keydown', (event) => event.key === 'Shift' && setStepping(true), true);
window.addEventListener('keyup', (event) => event.key === 'Shift' && setStepping(false), true);
window.addEventListener('mousemove', (event) => setStepping(event.shiftKey), { capture: true, passive: true });
window.addEventListener('blur', () => setStepping(false));

window.addEventListener('wheel', (event) => {
  if (!active(event)) return;
  if (event.shiftKey) {
    // Shift went down while the pointer was still: the cancelling listener isn't
    // attached yet. Step anyway (the page may scroll sideways this once).
    if (!stepping && isNotch(event)) {
      setStepping(true);
      const now = performance.now();
      if (now - lastStep >= 180) {
        lastStep = now;
        wake.post(params.channel, { type: 'trailStep', direction: notchOf(event) > 0 ? 1 : -1 });
      }
    }
    return;
  }
  const dx = event.deltaX;
  const dy = event.deltaY;
  if (panning || (Math.abs(dx) > Math.abs(dy) * 1.5 && Math.abs(dx) > 2 && !canScrollX(event.clientX, event.clientY, dx > 0 ? 1 : -1))) {
    panning = true;
    const pixels = event.deltaMode === 1 ? dx * 16 : dx;
    wake.post(params.channel, { type: 'trailPan', dx: pixels });
    clearTimeout(endTimer);
    endTimer = setTimeout(() => {
      panning = false;
      wake.post(params.channel, { type: 'trailPanEnd' });
    }, 140);
  }
}, { capture: true, passive: true });

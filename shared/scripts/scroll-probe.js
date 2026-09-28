// Answers "would a horizontal scroll at (x, y) move something in the page?"
// so trackpad swipes go to the trail only when the page wouldn't use them.
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

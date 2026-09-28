// Scrolls back and re-highlights a moment's selection. Returns whether the
// selection was found (pages that render late are retried by the host).
// The highlight uses the CSS Custom Highlight API, which marks text without
// touching the page's DOM (so React and friends don't notice).
// params: { key, prefix, scrollY, scrollFraction }
const key = params.key;
const prefix = params.prefix;
const root = document.scrollingElement || document.documentElement;
const max = Math.max(1, root.scrollHeight - window.innerHeight);
const scrollBack = () => {
  const y = params.scrollY;
  // The page grew or shrank since: use the same fraction of the way down.
  const target = (y + window.innerHeight * 0.5 <= root.scrollHeight) ? y : params.scrollFraction * max;
  window.scrollTo({ top: target, behavior: 'instant' });
};
if (!key) { scrollBack(); return true; }
if (!document.getElementById('__wake_moment_style')) {
  const style = document.createElement('style');
  style.id = '__wake_moment_style';
  style.dataset.wakeOverlay = '';
  style.textContent = '::highlight(wake-moment) { background-color: rgba(255, 214, 10, 0.45); }';
  (document.head || document.documentElement).appendChild(style);
}
const normal = s => s.replace(/\s+/g, ' ');
const selection = window.getSelection();
selection.removeAllRanges();
let found = null;
// window.find walks matches in order; the prefix picks the right one.
// Limitation: window.find is WebKit and Gecko only. Chromium (WebView2) doesn't
// have it, so there the walk below finds the text itself.
const matches = typeof window.find === 'function'
  ? function* () {
      for (let i = 0; i < 25 && window.find(key, false, false, false, false, false, false); i++) yield selection.getRangeAt(0).cloneRange();
    }
  : function* () {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let count = 0;
      for (let n = walker.nextNode(); n && count < 25; n = walker.nextNode()) {
        for (let at = n.nodeValue.indexOf(key); at >= 0 && count < 25; at = n.nodeValue.indexOf(key, at + 1)) {
          const range = document.createRange();
          range.setStart(n, at);
          range.setEnd(n, at + key.length);
          count++;
          yield range;
        }
      }
    };
for (const range of matches()) {
  if (!found) found = range;
  if (!prefix) break;
  const before = document.createRange();
  before.setStart(document.body, 0);
  before.setEnd(range.startContainer, range.startOffset);
  if (normal(before.toString()).endsWith(normal(prefix).slice(-24))) { found = range; break; }
}
selection.removeAllRanges();
if (!found) { scrollBack(); return false; }
if (window.CSS && CSS.highlights && window.Highlight) {
  CSS.highlights.set('wake-moment', new Highlight(found));
}
const rect = found.getBoundingClientRect();
window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight * 0.35, behavior: 'instant' });
return true;

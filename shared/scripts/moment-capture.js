// What a page reports when a moment is saved: selection (with the text just
// before it, to find the right match again), scroll position and visible text.
// params: { maxText }
const selection = window.getSelection();
const text = selection ? selection.toString().trim().slice(0, 1200) : '';
let prefix = '';
if (text && selection.rangeCount) {
  const range = selection.getRangeAt(0);
  const before = document.createRange();
  before.setStart(document.body, 0);
  before.setEnd(range.startContainer, range.startOffset);
  prefix = before.toString().replace(/\s+/g, ' ').slice(-48);
}
const root = document.scrollingElement || document.documentElement;
const max = Math.max(1, root.scrollHeight - window.innerHeight);
return {
  title: document.title,
  selection: text,
  prefix: prefix,
  scrollY: window.scrollY,
  fraction: Math.min(1, window.scrollY / max),
  text: document.body ? document.body.innerText.slice(0, params.maxText) : ''
};

// Replaces a raw JSON document with a formatted, collapsible tree.
// Returns true if the page was JSON.
let data;
try { data = JSON.parse(document.body ? document.body.innerText : ''); } catch { return false; }
const esc = (s) => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const leaf = (v) => {
  if (v === null) return '<span class="n">null</span>';
  if (typeof v === 'string') return /^https?:\/\//.test(v) ? `<a class="s" href="${esc(v)}">"${esc(v)}"</a>` : `<span class="s">"${esc(v)}"</span>`;
  if (typeof v === 'number') return `<span class="d">${v}</span>`;
  if (typeof v === 'boolean') return `<span class="b">${v}</span>`;
  return esc(v);
};
const node = (v, key, depth) => {
  const name = key === undefined ? '' : `<span class="k">${esc(key)}</span>: `;
  if (v === null || typeof v !== 'object') return `<div class="row">${name}${leaf(v)}</div>`;
  const isArray = Array.isArray(v);
  const entries = isArray ? v.map((x, i) => [i, x]) : Object.entries(v);
  const summary = isArray ? `Array(${entries.length})` : `{${entries.length}}`;
  const children = entries.map(([k, x]) => node(x, k, depth + 1)).join('');
  return `<details ${depth < 2 ? 'open' : ''}><summary>${name}<span class="t">${summary}</span></summary><div class="kids">${children}</div></details>`;
};
document.head.innerHTML = `<meta name="color-scheme" content="light dark"><style>
  body { font: 12.5px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; margin: 0; padding: 18px 22px; }
  summary { cursor: pointer; list-style: none; } summary::-webkit-details-marker { display: none; }
  summary::before { content: '▸'; display: inline-block; width: 14px; color: #8e8e93; transition: transform .12s; }
  details[open] > summary::before { transform: rotate(90deg); }
  .kids { padding-left: 16px; border-left: 1px solid rgba(128,128,128,.2); margin-left: 5px; }
  .row { padding-left: 14px; } .k { color: #b04ad8; } .s { color: #c4411a; } .d { color: #1c63d4; }
  .b { color: #0f8a6c; } .n { color: #8e8e93; } .t { color: #8e8e93; } a.s { text-decoration: none; }
  @media (prefers-color-scheme: dark) { .k { color: #d38cf5; } .s { color: #ff9f6b; } .d { color: #74b3ff; } .b { color: #5ed4b0; } }
</style>`;
document.body.innerHTML = node(data, undefined, 0);
document.title = document.title || location.pathname;
return true;

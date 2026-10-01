// Writes imported localStorage items the page doesn't already have. Returns how
// many it wrote; stops at the first failure (usually the quota).
// params: { items: [[key, value], …] }
let written = 0;
for (const [key, value] of params.items) {
  try { if (localStorage.getItem(key) === null) { localStorage.setItem(key, value); written++; } } catch (e) { break; }
}
return written;

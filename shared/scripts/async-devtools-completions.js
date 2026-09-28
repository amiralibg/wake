// Suggestions for the console prompt: properties of the object before the last dot.
// params: { code }
const code = params.code;
const match = /([\w$.\[\]'"]*?)\.?([\w$]*)$/.exec(code);
let target = window, prefix = code;
if (match && code.includes('.')) {
  prefix = match[2];
  try { target = (0, eval)(match[1]); } catch { return []; }
}
if (target === null || target === undefined) return [];
const names = new Set();
for (let o = Object(target), i = 0; o && i < 4; o = Object.getPrototypeOf(o), i++) Object.getOwnPropertyNames(o).forEach(n => names.add(n));
return Array.from(names).filter(n => n.startsWith(prefix) && /^[A-Za-z_$][\w$]*$/.test(n)).sort().slice(0, 12);

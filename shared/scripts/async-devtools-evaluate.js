// Evaluates console input in the page. Declarations stay global (indirect eval),
// promises are awaited, and `await` works at the top level.
// params: { code }
const code = params.code;
let value;
try {
  if (/\bawait\b/.test(code)) {
    try { value = await (0, eval)(`(async () => (${code}\n))()`); }
    catch (e) { if (!(e instanceof SyntaxError)) throw e; value = await (0, eval)(`(async () => {${code}\n})()`); }
  } else {
    value = (0, eval)(code);
    if (value instanceof Promise) value = await value;
  }
  if (value instanceof Element) window.__wakeDT.selected = value;
  return { ok: true, text: window.__wakeDT.preview(value), kind: window.__wakeDT.kindOf(value) };
} catch (error) {
  return { ok: false, text: window.__wakeDT.preview(error), kind: 'error' };
}

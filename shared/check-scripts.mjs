// Compiles every shared page script the way a host wraps it, without running it.
// Usage: node shared/check-scripts.mjs
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const dir = join(dirname(fileURLToPath(import.meta.url)), 'scripts');
let failed = 0;
for (const name of readdirSync(dir).filter(n => n.endsWith('.js')).sort()) {
  const body = readFileSync(join(dir, name), 'utf8');
  const wrapped = name === 'bridge.js'
    ? `(function () {\n${body}\n})();`
    : name.startsWith('async-')
      ? `(async function (wake, params) {\n${body}\n})();`
      : `(function (wake, params) {\n${body}\n})();`;
  try {
    new vm.Script(wrapped, { filename: name, lineOffset: -1 });
  } catch (error) {
    failed++;
    console.error(`${name}: ${error.message}`);
    console.error(error.stack.split('\n')[0]);
  }
}
if (failed) {
  console.error(`${failed} script${failed === 1 ? '' : 's'} failed to compile.`);
  process.exit(1);
}
console.log('All shared scripts compile.');

// Marks every page so content-script injection can be checked from outside.
document.documentElement.dataset.wakeTestExtension = 'injected';
const pill = document.createElement('div');
pill.textContent = 'Wake Test Extension ✓';
pill.style.cssText = 'position:fixed;left:12px;bottom:12px;z-index:2147483647;padding:6px 10px;border-radius:999px;font:600 12px -apple-system,system-ui;background:#6d28d9;color:white;box-shadow:0 4px 14px rgba(0,0,0,.25)';
(document.body || document.documentElement).appendChild(pill);
chrome.runtime.sendMessage({ type: 'seen' }, (reply) => {
  if (reply) pill.textContent = `Wake Test Extension ✓ · page ${reply.seen}`;
});

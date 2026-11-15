// On extension store pages (Chrome Web Store, Edge Add-ons, Firefox Add-ons), puts
// an "Add to Wake" button where the store offers its own browser instead, and hides
// the "switch to Chrome / get Firefox" nags. The host installs; this only asks.
// params: { channel, state: { installed: { chrome: [id], edge: [id], firefox: [slug|guid] }, installing } }
// Posts { type: 'storeInstall' | 'storeRemove', store, id }.
// The host calls window.__wakeStores.update(state) when installs change.
const host = location.hostname;
const store = host === 'chromewebstore.google.com' || (host === 'chrome.google.com' && location.pathname.startsWith('/webstore'))
  ? 'chrome'
  : host === 'microsoftedge.microsoft.com' ? 'edge'
  : host === 'addons.mozilla.org' ? 'firefox'
  : null;
if (!store) return;

let state = params.state || { installed: {}, installing: '' };
const ITEM_ID = /^[a-p]{32}$/;

function currentItem() {
  const parts = location.pathname.split('/').filter(Boolean);
  if (store === 'firefox') {
    const at = parts.indexOf('addon');
    return at >= 0 && parts[at + 1] ? decodeURIComponent(parts[at + 1]) : null;
  }
  const at = parts.indexOf('detail');
  if (at < 0) return null;
  return parts.slice(at + 1).find(p => ITEM_ID.test(p)) || null;
}

const isInstalled = id => ((state.installed || {})[store] || []).includes(id);

// Each store's own primary button look, so ours sits in the page as if it belonged.
const LOOK = {
  chrome: 'background:#0b57d0;color:#fff;border-radius:999px;min-height:40px;padding:0 24px;font:500 14px/1 "Google Sans",Roboto,-apple-system,system-ui,sans-serif;letter-spacing:.01em;',
  edge: 'background:#0f6cbd;color:#fff;border-radius:4px;min-height:32px;padding:0 20px;font:600 14px/1 "Segoe UI",-apple-system,system-ui,sans-serif;',
  firefox: 'background:#0060df;color:#fff;border-radius:4px;min-height:48px;padding:0 24px;font:600 16px/1 Inter,-apple-system,system-ui,sans-serif;width:100%;max-width:100%;',
};
const INSTALLED_LOOK = {
  chrome: 'background:transparent;color:#0b57d0;box-shadow:inset 0 0 0 1px #747775;',
  edge: 'background:transparent;color:#0f6cbd;box-shadow:inset 0 0 0 1px #0f6cbd;',
  firefox: 'background:#e0e0e6;color:#15141a;',
};

const button = document.createElement('button');
button.type = 'button';
button.setAttribute('data-wake-store-button', '');
const icon = document.createElement('span');
const label = document.createElement('span');
button.append(icon, label);

function paint() {
  const id = currentItem();
  const busy = id && state.installing === id;
  const installed = id && isInstalled(id);
  button.style.cssText = 'all:unset;box-sizing:border-box;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:8px;white-space:nowrap;transition:filter .15s,opacity .15s;'
    + LOOK[store] + (installed ? INSTALLED_LOOK[store] : '') + (busy ? 'opacity:.75;cursor:progress;' : '');
  icon.textContent = busy ? '' : installed ? '✓' : '+';
  icon.style.cssText = busy
    ? 'width:14px;height:14px;border-radius:50%;border:2px solid currentColor;border-right-color:transparent;animation:wake-store-spin .8s linear infinite;'
    : 'font-size:1.15em;line-height:1;';
  label.textContent = busy ? 'Adding to Wake…' : installed ? 'Remove from Wake' : 'Add to Wake';
  button.disabled = !!busy;
}

button.addEventListener('mouseenter', () => { button.style.filter = 'brightness(1.08)'; });
button.addEventListener('mouseleave', () => { button.style.filter = ''; });
button.addEventListener('click', (event) => {
  event.preventDefault();
  event.stopPropagation();
  const id = currentItem();
  if (!id || state.installing) return;
  wake.post(params.channel, { type: isInstalled(id) ? 'storeRemove' : 'storeInstall', store, id });
}, true);

// The store's own install button, by store (checked against each store's markup,
// November 2026). Chrome's is matched by the browser's name, which stays in the label
// in every language ("Zu Chrome hinzufügen", "Ajouter à Chrome"); for a non-Chrome
// browser it is the disabled one, while the banner's "Install Chrome" is enabled.
const shown = el => el && el.getClientRects().length > 0;
const chromeButtons = () => [...document.querySelectorAll('button')]
  .filter(b => /chrome/i.test(b.textContent || '') && !b.closest('[data-wake-store-button], header, [role="dialog"]'));

function storeButton() {
  if (store === 'chrome') {
    const candidates = chromeButtons().filter(shown);
    return candidates.find(b => b.disabled) || null;
  }
  if (store === 'edge') {
    return [...document.querySelectorAll('button[id^="installButton-"], button[id^="getOrRemoveButton"]')].find(shown) || null;
  }
  return [...document.querySelectorAll('.Addon-header .GetFirefoxButton, .Addon-install .GetFirefoxButton')].find(shown) || null;
}

// The "Install Chrome" / "Download the new Microsoft Edge" banners and Google's
// "Switch to Chrome?" card.
function hideNags() {
  const hide = el => {
    if (el && !el.hasAttribute('data-wake-hidden')) {
      el.setAttribute('data-wake-hidden', '');
      el.style.setProperty('display', 'none', 'important');
    }
  };
  if (store === 'chrome') {
    // The banner around "Install Chrome": the largest box around that button that
    // doesn't also hold the listing (its title, its real install button).
    for (const b of chromeButtons()) {
      if (b.disabled) continue;
      let banner = b;
      while (banner.parentElement && banner.parentElement !== document.body
        && !banner.parentElement.querySelector('h1, button[disabled], [data-wake-store-button]')) {
        banner = banner.parentElement;
      }
      hide(banner);
    }
    document.querySelectorAll('#gb [role="dialog"], #gb [role="alertdialog"]').forEach(hide);
  } else if (store === 'edge') {
    hide(document.getElementById('banner'));
  } else {
    document.querySelectorAll('.GetFirefoxBanner').forEach(hide);
  }
}

let fallbackTimer = 0;
function place() {
  hideNags();
  const id = currentItem();
  if (!id) {
    button.remove();
    return;
  }
  const original = storeButton();
  if (original) {
    if (original.previousElementSibling !== button) original.before(button);
    if (!original.hasAttribute('data-wake-hidden')) {
      original.setAttribute('data-wake-hidden', '');
      original.style.setProperty('display', 'none', 'important');
      // Edge puts "Incompatible with your browser" right under its button.
      const note = store === 'edge' && original.nextElementSibling;
      if (note && !note.querySelector('button, a')) note.style.setProperty('display', 'none', 'important');
    }
    button.style.position = '';
  } else if (!button.isConnected && !fallbackTimer) {
    // The store changed its page: float the button rather than lose it.
    fallbackTimer = setTimeout(() => {
      fallbackTimer = 0;
      if (button.isConnected || !currentItem() || storeButton()) return;
      document.body.append(button);
      button.style.cssText += 'position:fixed;right:24px;bottom:24px;z-index:2147483647;width:auto;box-shadow:0 8px 24px rgba(0,0,0,.25);';
    }, 2500);
  }
  paint();
}

const style = document.createElement('style');
style.textContent = '@keyframes wake-store-spin { to { transform: rotate(360deg); } }';

let scheduled = false;
function schedule() {
  if (scheduled) return;
  scheduled = true;
  setTimeout(() => { scheduled = false; place(); }, 120);
}

function start() {
  (document.head || document.documentElement).append(style);
  place();
  // The stores are single-page apps: watch for their re-renders and route changes.
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener('popstate', schedule);
}

window.__wakeStores = {
  update(next) {
    state = next || state;
    paint();
  },
};

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
else start();

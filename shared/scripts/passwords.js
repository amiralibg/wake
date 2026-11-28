// Password autofill and saving, in Wake's isolated world. Reports login fields
// as they get focus (so the host can offer saved logins under them), keys pressed
// while that menu is open, and sign-ins when a login form is submitted. Exposes
// window.__wakePasswords.fill / fillNew / setMenu for the host.
//
// Never reports a password on focus or typing, only on submit. Runs in the main
// frame only; logins inside iframes aren't seen.
if (window.__wakePasswords) return;
const channel = params.channel;
const post = (message) => wake.post(channel, Object.assign({ type: 'passwords' }, message));

const textTypes = new Set(['text', 'email', 'tel', '']);
const isPassword = (el) => el instanceof HTMLInputElement && el.type === 'password';
const isVisible = (el) => {
  const r = el.getBoundingClientRect();
  return r.width > 0 && r.height > 0 && getComputedStyle(el).visibility !== 'hidden';
};
const scope = (el) => el.form || el.closest('form') || document;
const passwordsIn = (root) => Array.from(root.querySelectorAll('input[type=password]')).filter(isVisible);

// A field that holds the account name: a text or email input before the password,
// or one marked as a username/email, in a form with a password field (or a form
// that's only a username step, like Google's first page).
const isUsernameField = (el) => {
  if (!(el instanceof HTMLInputElement) || !textTypes.has(el.type)) return false;
  const ac = (el.autocomplete || '').toLowerCase();
  if (ac.includes('username') || ac === 'email') return true;
  if (ac === 'off' && !passwordsIn(scope(el)).length) return false;
  const hint = `${el.name} ${el.id} ${el.placeholder} ${el.getAttribute('aria-label') || ''}`.toLowerCase();
  const looksLikeAccount = /user|email|e-mail|login|account|identifier|phone/.test(hint);
  const passwords = passwordsIn(scope(el));
  if (passwords.length) return looksLikeAccount || el.type === 'email' || precedes(el, passwords[0]);
  return looksLikeAccount && !!el.form;
};
const precedes = (a, b) => !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);

// "new" when the form makes a password: autocomplete=new-password, or two
// password fields (password + confirm), or three (change password).
const passwordKind = (el) => {
  if ((el.autocomplete || '').toLowerCase() === 'new-password') return 'newPassword';
  const fields = passwordsIn(scope(el));
  if (fields.length >= 2 && fields.indexOf(el) >= fields.length - 2 && fields.length !== 1) return 'newPassword';
  const hint = `${el.name} ${el.id}`.toLowerCase();
  if (/new|confirm|repeat|signup|register/.test(hint)) return 'newPassword';
  return 'password';
};

const usernameFor = (root, before) => {
  const candidates = Array.from(root.querySelectorAll('input')).filter((el) => isVisible(el) && isUsernameField(el) && el.value);
  const earlier = before ? candidates.filter((el) => precedes(el, before)) : candidates;
  const field = earlier[earlier.length - 1] || candidates[0];
  return field ? field.value.trim() : '';
};

const rectOf = (el) => {
  const r = el.getBoundingClientRect();
  return { x: r.left, y: r.top, w: r.width, h: r.height };
};

let focused = null;
let menuOpen = false;

document.addEventListener('focusin', (event) => {
  const el = event.target;
  let field = null;
  if (isPassword(el)) field = passwordKind(el);
  else if (isUsernameField(el)) field = 'username';
  if (!field) return;
  focused = el;
  post({ event: 'focus', field, rect: rectOf(el), value: field === 'username' ? el.value : '' });
}, true);

document.addEventListener('focusout', (event) => {
  if (event.target !== focused) return;
  focused = null;
  post({ event: 'blur' });
}, true);

document.addEventListener('input', (event) => {
  if (event.target !== focused || isPassword(focused)) return;
  post({ event: 'input', value: focused.value });
}, true);

document.addEventListener('keydown', (event) => {
  if (!menuOpen || event.target !== focused) return;
  const keys = { ArrowDown: 'down', ArrowUp: 'up', Enter: 'return', Escape: 'escape', Tab: 'tab' };
  const key = keys[event.key];
  if (!key) return;
  if (key !== 'tab') {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
  post({ event: 'key', key });
}, true);

addEventListener('scroll', () => {
  if (menuOpen && focused) post({ event: 'move', rect: rectOf(focused) });
}, { capture: true, passive: true });

// Sign-ins: a submitted form, Enter in a password field, or a click on a button
// next to one (single-page apps often never submit a form).
let lastReported = '';
const report = (root, origin) => {
  const fields = passwordsIn(root).filter((el) => el.value);
  if (!fields.length) {
    // A username-only step (enter your email, then the password page).
    const username = usernameFor(root, null);
    if (username) post({ event: 'username', value: username });
    return;
  }
  const isNew = fields.some((el) => passwordKind(el) === 'newPassword');
  // Change-password forms: the last one is the new password (the one before it
  // repeats it), and the first is the current one.
  const password = isNew ? fields[fields.length - 1].value : fields[0].value;
  const username = usernameFor(root, fields[0]);
  const key = `${username}\u0000${password}`;
  if (key === lastReported) return;
  lastReported = key;
  post({ event: 'submit', username, password, isNew, origin });
};

document.addEventListener('submit', (event) => report(event.target, 'submit'), true);
document.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && !menuOpen && event.target instanceof HTMLInputElement &&
      (isPassword(event.target) || passwordsIn(scope(event.target)).length)) {
    report(scope(event.target), 'enter');
  }
}, true);
document.addEventListener('click', (event) => {
  const button = event.target instanceof Element && event.target.closest('button, input[type=submit], [role=button]');
  if (!button) return;
  const root = scope(button);
  if (passwordsIn(root).length || root !== document) report(root, 'click');
}, true);

// Filling: the page's own value setter, then input and change events, so
// frameworks that track values (React, Vue) see the change.
const setValue = (el, value) => {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  el.focus();
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
};

window.__wakePasswords = {
  setMenu(open) { menuOpen = !!open; },
  // A saved login, into the form that has focus.
  fill(username, password) {
    const anchor = focused || document.activeElement;
    const root = anchor ? scope(anchor) : document;
    const passwords = passwordsIn(root);
    const user = Array.from(root.querySelectorAll('input')).find((el) => isVisible(el) && isUsernameField(el));
    if (user && username) setValue(user, username);
    if (passwords[0]) setValue(passwords[0], password);
    const last = passwords[0] || user;
    if (last) last.focus();
    return !!(passwords[0] || user);
  },
  // A generated password, into every new-password field of the form.
  fillNew(password) {
    const anchor = focused || document.activeElement;
    const root = anchor ? scope(anchor) : document;
    const fields = passwordsIn(root).filter((el) => passwordKind(el) === 'newPassword');
    const targets = fields.length ? fields : (isPassword(anchor) ? [anchor] : []);
    targets.forEach((el) => setValue(el, password));
    return targets.length;
  },
};

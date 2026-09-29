// Keyboard shortcuts. ⌘ becomes Ctrl; the Mac's ⌥⌘ shortcuts move to Ctrl+Shift
// (or the Windows/Linux browser convention), because Ctrl+Alt is AltGr on many
// layouts and would swallow typed characters (€, @, ą…) in pages.
//
// While a page has keyboard focus the host intercepts exactly the accelerators
// listed here (`keys.set`) before the page sees them; while Wake's own UI has
// focus, `handleKeyDown` reads them from the DOM event.

import { reaction } from 'mobx';
import { host } from '../host/host';
import { settings } from './settings';
import type { BrowserModel, ColumnCommand } from './browser';

type Action = (browser: BrowserModel) => void;

export interface Shortcut {
  keys: string[];
  label: string;
  run: Action;
}

const zoom = (b: BrowserModel, dir: 'in' | 'out' | 'reset') => {
  const page = b.webPage;
  if (!page || page.device) return;
  if (dir === 'in') page.zoomIn();
  else if (dir === 'out') page.zoomOut();
  else page.resetZoom();
};

export const SHORTCUTS: Shortcut[] = [
  { keys: ['ctrl+k'], label: 'Command Palette', run: (b) => b.togglePalette() },
  { keys: ['ctrl+t'], label: 'New Column', run: (b) => b.showPalette('newColumn') },
  { keys: ['ctrl+shift+n'], label: 'New Thread', run: (b) => b.newThread() },
  { keys: ['ctrl+n'], label: 'New Window', run: () => host.send('window.new') },
  { keys: ['ctrl+l', 'alt+d'], label: 'Open Location', run: (b) => b.showPalette('currentColumn') },
  { keys: ['ctrl+shift+t'], label: 'Reopen Closed Column', run: (b) => b.trail.reopenClosed() },
  { keys: ['ctrl+shift+d'], label: 'Duplicate Column', run: (b) => b.trail.duplicateFocused() },
  { keys: ['ctrl+w', 'ctrl+f4'], label: 'Close Column', run: (b) => b.closeCommand() },
  { keys: ['ctrl+shift+w'], label: 'Close Window', run: (b) => void b.closeWindow() },
  { keys: ['ctrl+q'], label: 'Quit', run: () => host.send('app.quit') },
  { keys: ['ctrl+,'], label: 'Settings', run: (b) => (b.isSettingsOpen ? b.hideSettings() : b.showSettings()) },
  { keys: ['ctrl+shift+l'], label: 'Copy Page Address', run: (b) => b.copyPageURL() },
  { keys: ['ctrl+\\'], label: 'Zen', run: (b) => b.setZen(!b.isZen) },
  { keys: ['f11'], label: 'Full Screen', run: () => host.send('window.fullscreen') },
  { keys: ['ctrl+='], label: 'Zoom In', run: (b) => zoom(b, 'in') },
  { keys: ['ctrl+-'], label: 'Zoom Out', run: (b) => zoom(b, 'out') },
  { keys: ['ctrl+0'], label: 'Actual Size', run: (b) => zoom(b, 'reset') },
  { keys: ['ctrl+shift+='], label: 'Wider Column', run: (b) => b.trail.resizeFocused(0.1) },
  { keys: ['ctrl+shift+-'], label: 'Narrower Column', run: (b) => b.trail.resizeFocused(-0.1) },
  { keys: ['ctrl+shift+0'], label: 'Default Column Width', run: (b) => b.page && b.trail.resetWidth(b.page) },
  { keys: ['ctrl+[', 'ctrl+pageup'], label: 'Previous Column', run: (b) => b.trail.focusPrevious() },
  { keys: ['ctrl+]', 'ctrl+pagedown'], label: 'Next Column', run: (b) => b.trail.focusNext() },
  { keys: ['ctrl+tab'], label: 'Cycle Columns', run: (b) => b.trail.cycleFocus(true) },
  { keys: ['ctrl+shift+tab'], label: 'Cycle Columns Backwards', run: (b) => b.trail.cycleFocus(false) },
  ...[1, 2, 3, 4, 5, 6, 7, 8].map((n) => ({ keys: [`ctrl+${n}`], label: `Column ${n}`, run: (b: BrowserModel) => b.trail.focus(n - 1) })),
  { keys: ['ctrl+9'], label: 'Last Column', run: (b) => b.trail.focus(b.trail.columns.length - 1) },
  { keys: ['ctrl+shift+pageup'], label: 'Move Column Left', run: (b) => b.trail.moveFocused(-1) },
  { keys: ['ctrl+shift+pagedown'], label: 'Move Column Right', run: (b) => b.trail.moveFocused(1) },
  { keys: ['alt+arrowleft'], label: 'Back', run: (b) => b.page?.goBack() },
  { keys: ['alt+arrowright'], label: 'Forward', run: (b) => b.page?.goForward() },
  { keys: ['ctrl+r', 'f5'], label: 'Reload Page', run: (b) => b.webPage?.reload() },
  { keys: ['ctrl+shift+r', 'ctrl+f5'], label: 'Reload Without Cache', run: (b) => b.webPage?.reloadFromOrigin() },
  { keys: ['ctrl+.'], label: 'Stop Loading', run: (b) => b.webPage?.stopLoading() },
  { keys: ['ctrl+shift+o'], label: 'Pop Out Element', run: (b) => b.togglePopOutPicker() },
  { keys: ['ctrl+d'], label: 'Save Moment', run: (b) => void b.saveMoment() },
  { keys: ['ctrl+shift+b'], label: 'Moments', run: (b) => b.toggleMoments() },
  { keys: ['ctrl+h'], label: 'History', run: (b) => b.showHistory('history') },
  { keys: ['ctrl+shift+h'], label: 'Searches', run: (b) => b.showHistory('searches') },
  { keys: ['ctrl+shift+e'], label: 'Developer Mode for Thread', run: (b) => b.toggleDeveloperMode() },
  { keys: ['ctrl+shift+i'], label: 'DevTools', run: (b) => b.toggleDevTools() },
  { keys: ['f12'], label: 'Web Inspector', run: (b) => b.showWebInspector() },
  { keys: ['ctrl+shift+c'], label: 'Inspect Element', run: (b) => b.inspectElement() },
  { keys: ['ctrl+shift+j'], label: 'JavaScript Console', run: (b) => b.showDevTools('console') },
  { keys: ['ctrl+u'], label: 'Page Source', run: (b) => b.showDevTools('sources') },
  { keys: ['ctrl+shift+x'], label: 'Inspect Components', run: (b) => b.toggleComponentInspector() },
  { keys: ['ctrl+shift+m'], label: 'Responsive Preview', run: (b) => b.openResponsivePreview() },
  { keys: ['ctrl+shift+delete'], label: 'Empty Caches', run: (b) => b.emptyCaches() },
  { keys: ['ctrl+shift+p'], label: 'Pin Page as App', run: (b) => b.webPage && b.pin(b.webPage) },
  ...[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => ({ keys: [`alt+${n}`], label: `App ${n}`, run: (b: BrowserModel) => b.toggleAppIndex(n - 1) })),
];

const COLUMN_MODE_KEY = 'alt+w';

/** A keyboard event as an accelerator: modifiers, then the key at its QWERTY position. */
export function accelerator(event: KeyboardEvent): string | null {
  const key = keyName(event.code);
  if (!key) return null;
  const parts: string[] = [];
  if (event.ctrlKey) parts.push('ctrl');
  if (event.altKey) parts.push('alt');
  if (event.shiftKey) parts.push('shift');
  if (event.metaKey) parts.push('meta');
  parts.push(key);
  return parts.join('+');
}

function keyName(code: string): string | null {
  if (code.startsWith('Key')) return code.slice(3).toLowerCase();
  if (code.startsWith('Digit')) return code.slice(5);
  if (/^Numpad\d$/.test(code)) return code.slice(6);
  if (/^F\d{1,2}$/.test(code)) return code.toLowerCase();
  const map: Record<string, string> = {
    Equal: '=', NumpadAdd: '=', Minus: '-', NumpadSubtract: '-', BracketLeft: '[', BracketRight: ']', Comma: ',',
    Period: '.', Slash: '/', Semicolon: ';', Backquote: '`', Quote: "'", Backslash: '\\', ArrowLeft: 'arrowleft',
    ArrowRight: 'arrowright', ArrowUp: 'arrowup', ArrowDown: 'arrowdown', Escape: 'escape', Enter: 'enter',
    NumpadEnter: 'enter', Tab: 'tab', Backspace: 'backspace', Delete: 'delete', Space: 'space', PageUp: 'pageup',
    PageDown: 'pagedown', Home: 'home', End: 'end',
  };
  return map[code] ?? null;
}

const byAccelerator = new Map<string, Shortcut>();
for (const shortcut of SHORTCUTS) for (const key of shortcut.keys) byAccelerator.set(key, shortcut);

/** The label shown next to a menu item or in a tooltip: "Ctrl+Shift+T". */
export function shortcutLabel(label: string): string {
  const shortcut = SHORTCUTS.find((s) => s.label === label);
  return shortcut ? prettyKey(shortcut.keys[0]) : '';
}

export function prettyKey(accel: string) {
  const names: Record<string, string> = {
    ctrl: 'Ctrl', alt: 'Alt', shift: 'Shift', meta: 'Super', arrowleft: '←', arrowright: '→', arrowup: '↑',
    arrowdown: '↓', escape: 'Esc', enter: 'Enter', tab: 'Tab', pageup: 'PgUp', pagedown: 'PgDn', delete: 'Del',
    space: 'Space', backspace: 'Backspace',
  };
  return accel
    .split('+')
    .map((p) => names[p] ?? (p.length === 1 ? p.toUpperCase() : p.toUpperCase()))
    .join('+');
}

/** Runs a shortcut; returns whether it was one. */
export function runAccelerator(browser: BrowserModel, accel: string): boolean {
  if (accel === 'escape') {
    if (browser.isColumnModeActive) {
      browser.exitColumnMode();
      return true;
    }
    if (browser.hasOverlay) {
      browser.dismissOverlays();
      return true;
    }
    return false;
  }
  if (accel === COLUMN_MODE_KEY && settings.columnModeKeyEnabled) {
    if (browser.isColumnModeActive) browser.perform('cycleForward');
    else browser.enterColumnMode();
    return true;
  }
  const shortcut = byAccelerator.get(accel);
  if (!shortcut) return false;
  if (browser.isColumnModeActive) browser.exitColumnMode();
  shortcut.run(browser);
  return true;
}

/** Column mode: the command for a key (Vim's window keys), or null (which ends the mode). */
function columnCommand(event: KeyboardEvent): ColumnCommand | null {
  let key = keyName(event.code);
  if (!key) return null;
  const shift = event.shiftKey;
  if (event.ctrlKey || event.metaKey) return null;
  if (shift) {
    const shifted: Record<string, string> = { h: 'H', l: 'L', w: 'W', g: 'G', arrowleft: 'H', arrowright: 'L', tab: 'W', '4': '$', '6': '^', '=': '+', ',': '<', '.': '>' };
    key = shifted[key] ?? key;
  }
  switch (key) {
    case 'h': case 'arrowleft': return 'previous';
    case 'l': case 'arrowright': return 'next';
    case 'H': return 'moveLeft';
    case 'L': return 'moveRight';
    case 'w': case 'tab': return 'cycleForward';
    case 'W': return 'cycleBackward';
    case 'g': case '^': return 'first';
    case 'G': case '$': case '9': return 'last';
    case '>': case '+': return 'wider';
    case '<': case '-': return 'narrower';
    case '=': return 'defaultWidth';
    case 'x': case 'c': case 'q': return 'close';
    case 'v': case 's': return 'duplicate';
    case 'u': return 'reopen';
    case 'n': case 't': return 'newColumn';
    case 'escape': case 'enter': return 'exit';
  }
  if (/^[1-8]$/.test(key)) return { jump: Number(key) - 1 };
  return null;
}

/** Keydown in Wake's own UI. */
export function handleKeyDown(browser: BrowserModel, event: KeyboardEvent) {
  if (browser.isColumnModeActive) {
    if (['Shift', 'Control', 'Alt', 'Meta'].includes(event.key)) return;
    const accel = accelerator(event);
    if (accel === COLUMN_MODE_KEY) {
      event.preventDefault();
      browser.perform('cycleForward');
      return;
    }
    const command = columnCommand(event);
    event.preventDefault();
    if (command) browser.perform(command);
    else browser.exitColumnMode();
    return;
  }
  const accel = accelerator(event);
  if (!accel) return;
  // Text fields keep their own editing keys.
  const target = event.target as HTMLElement | null;
  const typing = !!target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable);
  if (typing && ['ctrl+a', 'ctrl+c', 'ctrl+v', 'ctrl+x', 'ctrl+z', 'ctrl+shift+z', 'ctrl+y', 'alt+arrowleft', 'alt+arrowright', 'ctrl+backspace', 'ctrl+delete'].includes(accel)) return;
  if (accel === 'escape' && typing && !browser.hasOverlay) return;
  if (runAccelerator(browser, accel)) {
    event.preventDefault();
    event.stopPropagation();
  }
}

/** Keeps the host's list of keys to take from pages in step with the state. */
export function syncKeys(browser: BrowserModel) {
  return reaction(
    () => {
      const keys = SHORTCUTS.flatMap((s) => s.keys);
      if (settings.columnModeKeyEnabled) keys.push(COLUMN_MODE_KEY);
      if (browser.hasOverlay || browser.isColumnModeActive) keys.push('escape');
      return keys.sort().join('|');
    },
    (joined) => host.send('keys.set', { keys: joined.split('|') }),
    { fireImmediately: true },
  );
}


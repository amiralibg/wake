// One live page (port of BrowserPage.swift): mirrors a host webview's state and
// routes what its scripts report. The webview itself lives in the host; this
// object names it by id.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { settings } from './settings';
import { DevToolsLog, type ComponentPick } from './devtools-log';
import { type LiveState, mergeLive, liveEqual, priceWatch } from './live';
import { type DeviceFrame, userAgent } from './device';

export type World = 'wake' | 'page';

export interface MomentRestore {
  selection: string | null;
  prefix: string | null;
  scrollY: number;
  scrollFraction: number;
}

export interface PopOutPick {
  url: string;
  title: string;
  selector: string;
  label: string;
  rect: { x: number; y: number; width: number; height: number };
  layoutWidth: number;
}

const registry = new Map<string, Page>();

export const pageByID = (id: string) => registry.get(id);

export const ZOOM_STEPS = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3];

export function isLocal(url: string | null | undefined): boolean {
  if (!url) return false;
  try {
    const host = new URL(url).hostname.toLowerCase();
    return (
      ['localhost', '127.0.0.1', '0.0.0.0', '::1', '[::1]'].includes(host) ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.test')
    );
  } catch {
    return false;
  }
}

export function hostOf(url: string | null | undefined): string {
  if (!url) return '';
  try {
    const host = new URL(url).hostname;
    return host.startsWith('www.') ? host.slice(4) : host;
  } catch {
    return url;
  }
}

/** Same document, ignoring the fragment. */
export function samePage(a: string | null | undefined, b: string | null | undefined) {
  if (!a || !b) return false;
  return a.split('#')[0] === b.split('#')[0];
}

let nextID = 0;
const newID = () => (crypto.randomUUID ? crypto.randomUUID() : `page-${Date.now()}-${nextID++}`);

export interface PageOptions {
  /** A popup the host already created (its webview is tied to the opener). */
  adopt?: string;
  devToolsFor?: Page;
  ephemeral?: boolean;
  device?: DeviceFrame | null;
}

export class Page {
  readonly id: string;
  readonly isDevTools: boolean;
  inspectedPage: Page | null = null;

  title = '';
  url: string | null = null;
  /** What was last asked for, before the engine reports a committed URL. */
  requestedURL: string | null = null;
  progress = 0;
  isLoading = false;
  canGoBack = false;
  canGoForward = false;
  isSecure = false;
  faviconURL: string | null = null;
  failure: string | null = null;
  isPlayingMedia = false;
  hasUnsavedInput = false;
  live: LiveState = {};
  zoom = 1;
  /** The latest picture of the page, drawn in its place while the UI covers it. */
  snapshot: string | null = null;
  isFullscreen = false;

  // Developer mode
  devtools = new DevToolsLog();
  isDeveloperMode = false;
  /** The thread's choice; null is automatic (on for localhost). */
  developerModeOverride: boolean | null = null;
  isInspectingComponents = false;
  isPickingPopOut = false;
  isJSONDocument = false;
  isJavaScriptDisabled = false;
  isEphemeral = false;
  device: DeviceFrame | null = null;
  isClosed = false;
  /** The DevTools tab to show (set by "Show Console" and friends). */
  devtoolsTab = 'elements';
  /** Bumped to ask the DevTools column to start the element picker. */
  devtoolsPickRequest = 0;

  // Hooks (not observed)
  onOpenLink?: (url: string, background: boolean) => void;
  /** A popup the page opened: return true to keep it (the owner adopts `page`). */
  onPopup?: (page: Page) => boolean;
  onClose?: () => void;
  onStateChange?: () => void;
  onDidFinish?: (page: Page) => void;
  onScroll?: (fraction: number) => void;
  onInspect?: (pick: ComponentPick) => void;
  onRestored?: (page: Page) => void;
  onFocused?: (page: Page) => void;
  onPopOutPick?: (pick: PopOutPick) => void;
  onTrailWheel?: (message: { type: string; dx?: number; direction?: number }) => void;
  onDevToolsMessage?: (message: any) => void;
  onPopOutMessage?: (message: any) => void;
  /** A document loaded or was replaced (DevTools sessions refresh). */
  onDocument?: (phase: 'committed' | 'finished') => void;
  syncsScroll = false;
  pendingRestore: MomentRestore | null = null;
  pendingScrollY: number | null = null;
  isRestoring = false;
  private pendingHTTPStatus: number | null = null;
  private committed = false;

  constructor(options: PageOptions = {}) {
    this.id = options.adopt ?? newID();
    this.isDevTools = !!options.devToolsFor;
    this.inspectedPage = options.devToolsFor ?? null;
    this.isEphemeral = !!options.ephemeral || this.isDevTools;
    this.device = options.device ?? null;
    makeAutoObservable<Page, 'pendingHTTPStatus' | 'committed'>(this, {
      id: false,
      isDevTools: false,
      inspectedPage: false,
      onOpenLink: false,
      onPopup: false,
      onClose: false,
      onStateChange: false,
      onDidFinish: false,
      onScroll: false,
      onInspect: false,
      onRestored: false,
      onFocused: false,
      onPopOutPick: false,
      onTrailWheel: false,
      onDevToolsMessage: false,
      onPopOutMessage: false,
      onDocument: false,
      pendingRestore: false,
      pendingScrollY: false,
      isRestoring: false,
      pendingHTTPStatus: false,
      committed: false,
      syncsScroll: false,
    });
    registry.set(this.id, this);
    if (!this.isDevTools && !options.adopt) {
      host.send('page.create', {
        page: this.id,
        userAgent: this.device ? userAgent(this.device.preset) : undefined,
      });
    }
  }

  get displayTitle(): string {
    if (this.isDevTools) return `DevTools · ${this.inspectedPage?.host ?? ''}`;
    const base = this.title || hostOf(this.url ?? this.requestedURL) || 'New page';
    return this.device ? `${this.device.preset.name} · ${base}` : base;
  }

  get host(): string {
    return hostOf(this.url);
  }

  get address(): string | null {
    return this.url ?? this.requestedURL;
  }

  // MARK: Navigation

  load(url: string) {
    this.failure = null;
    this.requestedURL = url;
    this.updateDeveloperMode(url);
    host.send('page.load', { page: this.id, url });
  }

  reload() {
    this.failure = null;
    host.send('page.nav', { page: this.id, action: 'reload' });
  }

  reloadFromOrigin() {
    host.send('page.nav', { page: this.id, action: 'reloadHard' });
  }

  stopLoading() {
    host.send('page.nav', { page: this.id, action: 'stop' });
  }

  goBack() {
    host.send('page.nav', { page: this.id, action: 'back' });
  }

  goForward() {
    host.send('page.nav', { page: this.id, action: 'forward' });
  }

  focus() {
    if (!this.isDevTools) host.send('page.focus', { page: this.id });
  }

  /** The column is gone for good: the host lets its webview (and process) go. */
  close() {
    if (this.isClosed) return;
    this.isClosed = true;
    registry.delete(this.id);
    if (!this.isDevTools) host.send('page.close', { page: this.id });
  }

  // MARK: Scripts

  /** Runs `body` (an async function body) and returns its (JSON) value. */
  eval<T = any>(body: string, world: World = 'wake'): Promise<T> {
    if (this.isDevTools || this.isClosed) return Promise.resolve(null as T);
    return host.call<T>('page.eval', { page: this.id, js: body, world });
  }

  /** Runs a shared script (shared/scripts/<name>.js) and returns its value. */
  run<T = any>(script: string, params: Record<string, unknown> = {}, world: World = 'wake'): Promise<T> {
    if (this.isDevTools || this.isClosed) return Promise.resolve(null as T);
    return host.call<T>('page.run', { page: this.id, script, params, world });
  }

  /** Runs a shared script without waiting for it. */
  fire(script: string, params: Record<string, unknown> = {}, world: World = 'wake') {
    if (this.isDevTools || this.isClosed) return;
    host.send('page.run', { page: this.id, script, params, world });
  }

  /** Evaluates a statement without waiting. */
  exec(js: string, world: World = 'wake') {
    if (this.isDevTools || this.isClosed) return;
    host.send('page.exec', { page: this.id, js, world });
  }

  async scrollY(): Promise<number | null> {
    try {
      return await this.eval<number>('return window.scrollY;');
    } catch {
      return null;
    }
  }

  async takeSnapshot(width = 900): Promise<string | null> {
    if (this.isDevTools || this.isClosed || !this.url) return this.snapshot;
    try {
      const image = await host.call<string>('page.snapshot', { page: this.id, width });
      runInAction(() => (this.snapshot = image));
      return image;
    } catch {
      return this.snapshot;
    }
  }

  /** Saves a snapshot to a file in the data folder (thumbnails). */
  saveSnapshot(file: string, width = 640): Promise<unknown> {
    if (this.isDevTools || this.isClosed || !this.url) return Promise.resolve(null);
    return host.call('page.snapshot', { page: this.id, width, file }).catch(() => null);
  }

  // MARK: Zoom

  setZoom(value: number) {
    this.zoom = value;
    host.send('page.zoom', { page: this.id, zoom: value });
  }
  zoomIn() {
    this.setZoom(ZOOM_STEPS.find((z) => z > this.zoom + 0.001) ?? this.zoom);
  }
  zoomOut() {
    this.setZoom([...ZOOM_STEPS].reverse().find((z) => z < this.zoom - 0.001) ?? this.zoom);
  }
  resetZoom() {
    this.setZoom(1);
  }

  setDevice(device: DeviceFrame | null) {
    const oldAgent = this.device ? userAgent(this.device.preset) : null;
    const newAgent = device ? userAgent(device.preset) : null;
    const had = this.device;
    this.device = device;
    if (oldAgent !== newAgent) {
      host.send('page.userAgent', { page: this.id, userAgent: newAgent ?? '' });
      if (had && this.url) this.reload();
    }
  }

  // MARK: Developer mode

  setDeveloperModeOverride(value: boolean | null) {
    this.developerModeOverride = value;
    this.updateDeveloperMode(this.url, true);
  }

  /** Adds or removes the page-world hooks so the next document matches the mode. */
  updateDeveloperMode(url: string | null, applyNow = false) {
    if (this.isDevTools) return;
    const wanted = this.developerModeOverride ?? (settings.autoEnableForLocalhost && isLocal(url));
    if (wanted === this.isDeveloperMode) return;
    this.isDeveloperMode = wanted;
    host.send('page.devHooks', { page: this.id, on: wanted });
    if (wanted && applyNow) this.fire('dev-hooks', { channel: 'wakeDev' }, 'page');
  }

  setJavaScriptDisabled(disabled: boolean) {
    this.isJavaScriptDisabled = disabled;
    host.send('page.javascript', { page: this.id, on: !disabled });
  }

  setMock(body: string | null, path: string) {
    this.devtools.setMock(body, path);
    this.pushMocks();
  }

  private pushMocks() {
    if (!this.isDeveloperMode) return;
    this.exec(`window.__wakeDev && (window.__wakeDev.mocks = ${JSON.stringify(this.devtools.mocks)});`, 'page');
  }

  setInspectingComponents(on: boolean) {
    this.isInspectingComponents = on;
    if (on) {
      this.fire('component-inspector', { channel: 'wakeDev' }, 'page');
      this.exec('window.__wakeInspect && window.__wakeInspect.start();', 'page');
    } else {
      this.exec('window.__wakeInspect && window.__wakeInspect.stop();', 'page');
    }
  }

  /** Starts or stops the Pop Out picker in this page. */
  setPickingPopOut(on: boolean) {
    this.isPickingPopOut = on;
    if (on) {
      this.fire('popout-picker', { channel: 'wake' });
      this.focus();
    } else {
      this.exec('window.__wakePick && window.__wakePick.stop && window.__wakePick.stop();');
    }
  }

  setScrollSync(on: boolean) {
    this.exec(`window.__wake && (window.__wake.syncScroll = ${on});`);
  }

  scrollToFraction(fraction: number) {
    this.exec(`window.__wake && window.__wake.scrollToFraction(${Number(fraction) || 0});`);
  }

  setTrailWheel(on: boolean) {
    this.exec(`window.__wake && (window.__wake.trailWheel = ${on});`);
  }

  // MARK: Moments

  async visibleText(maxText = 40000): Promise<string> {
    try {
      return (await this.run<string>('visible-text', { maxText })) ?? '';
    } catch {
      return '';
    }
  }

  /** Scrolls back and highlights, retrying while a late-rendering page fills in. */
  async applyRestore(restore: MomentRestore) {
    const firstLine = (restore.selection ?? '').split(/\r?\n/)[0]?.trim().slice(0, 150) ?? '';
    for (const delay of [300, 1200, 3000]) {
      await new Promise((r) => setTimeout(r, delay));
      try {
        const found = await this.run<boolean>('moment-restore', {
          key: firstLine,
          prefix: restore.prefix ?? '',
          scrollY: Number.isFinite(restore.scrollY) ? restore.scrollY : 0,
          scrollFraction: Number.isFinite(restore.scrollFraction) ? restore.scrollFraction : 0,
        });
        if (found) return;
      } catch {}
    }
  }

  // MARK: Host events

  applyState(state: any) {
    let changed = false;
    if ('title' in state && typeof state.title === 'string' && state.title !== this.title) {
      this.title = state.title;
      changed = true;
    }
    if ('url' in state && state.url && state.url !== this.url) {
      this.url = state.url;
      this.isSecure = state.url.startsWith('https:');
      changed = true;
    }
    if (typeof state.progress === 'number') this.progress = state.progress;
    if (typeof state.loading === 'boolean') this.isLoading = state.loading;
    if (typeof state.canGoBack === 'boolean') this.canGoBack = state.canGoBack;
    if (typeof state.canGoForward === 'boolean') this.canGoForward = state.canGoForward;
    if (typeof state.audio === 'boolean' && state.audio && !this.isPlayingMedia) this.isPlayingMedia = true;
    if (changed) this.onStateChange?.();
  }

  loadEvent(phase: 'started' | 'finished', url: string) {
    if (phase === 'started') {
      this.failure = null;
      this.isLoading = true;
      this.committed = false;
      if (url && url !== 'about:blank') this.updateDeveloperMode(url);
      return;
    }
    this.didFinish();
  }

  /** A new document: whatever the old one was playing or holding is gone. */
  didCommit(url: string | null, secure: boolean) {
    this.committed = true;
    if (url) this.url = url;
    this.isSecure = secure || !!url?.startsWith('https:');
    this.faviconURL = null;
    this.isPlayingMedia = false;
    this.hasUnsavedInput = false;
    this.isInspectingComponents = false;
    this.isPickingPopOut = false;
    this.live = { httpStatus: this.pendingHTTPStatus };
    this.pendingHTTPStatus = null;
    this.devtools.reset();
    // The engine may have created the document before the hooks were added.
    if (this.isDeveloperMode) this.fire('dev-hooks', { channel: 'wakeDev' }, 'page');
    this.pushMocks();
    this.onDocument?.('committed');
    if (!settings.shiftScrollMovesColumns) this.setTrailWheel(false);
  }

  response(status: number | null, mime: string | null) {
    if (mime != null) this.isJSONDocument = mime.toLowerCase().includes('json');
    if (status == null) return;
    // WebKitGTK reports the response before the commit, WebView2 after the load.
    if (this.committed) this.live = { ...this.live, httpStatus: status };
    else this.pendingHTTPStatus = status;
  }

  fail(message: string) {
    this.failure = message;
    this.isLoading = false;
  }

  private async didFinish() {
    this.isLoading = false;
    this.progress = 1;
    if (this.url) {
      if (this.isJSONDocument === false) {
        // WebView2 doesn't report the MIME type: ask the document.
        const type = await this.eval<string>('return document.contentType;').catch(() => null);
        if (type) runInAction(() => (this.isJSONDocument = type.toLowerCase().includes('json')));
      }
      if (this.isJSONDocument) this.fire('json-viewer');
    }
    if (this.syncsScroll) this.setScrollSync(true);
    const y = this.pendingScrollY;
    if (y != null) {
      this.pendingScrollY = null;
      if (y > 0) {
        // Pages that build themselves after the load event get a second try.
        this.exec(`window.scrollTo(0, ${y})`, 'page');
        setTimeout(async () => {
          const now = await this.scrollY();
          if (now != null && Math.abs(now - y) > 4) this.exec(`window.scrollTo(0, ${y})`, 'page');
        }, 600);
      }
    }
    const restore = this.pendingRestore;
    if (restore) {
      this.pendingRestore = null;
      void this.applyRestore(restore).then(() => {
        this.onRestored?.(this);
        this.onRestored = undefined;
      });
    }
    this.resolveFavicon();
    this.onDocument?.('finished');
    this.onDidFinish?.(this);
  }

  private async resolveFavicon() {
    try {
      const href = await this.run<string>('favicon');
      runInAction(() => (this.faviconURL = href || null));
    } catch {}
  }

  receive(message: any) {
    if (!message || typeof message.type !== 'string') return;
    switch (message.type) {
      case 'scroll':
        if (typeof message.fraction === 'number') this.onScroll?.(message.fraction);
        break;
      case 'openLink':
        if (typeof message.href === 'string') this.onOpenLink?.(message.href, !!message.background);
        break;
      case 'state':
        this.isPlayingMedia = !!message.playing;
        this.hasUnsavedInput = !!message.unsaved;
        break;
      case 'popOutPick':
        this.isPickingPopOut = false;
        if (!this.url || typeof message.selector !== 'string') return;
        this.onPopOutPick?.({
          url: this.url,
          title: this.displayTitle,
          selector: message.selector,
          label: message.label ?? '',
          rect: { x: message.x ?? 0, y: message.y ?? 0, width: message.w ?? 320, height: message.h ?? 200 },
          layoutWidth: message.layoutWidth ?? 1024,
        });
        break;
      case 'popOutCancel':
        this.isPickingPopOut = false;
        break;
      case 'live': {
        if (message.reset) {
          this.live = { media: this.live.media, httpStatus: this.live.httpStatus };
          return;
        }
        const next = mergeLive(this.live, message);
        if (!liveEqual(next, this.live)) this.live = next;
        if (this.live.price && this.url) priceWatch.observe(this.live.price.amount, this.url);
        break;
      }
      case 'trailStep':
      case 'trailPan':
      case 'trailPanEnd':
        this.onTrailWheel?.(message);
        break;
    }
  }

  receiveDeveloperMessage(message: any) {
    if (!(this.isDeveloperMode || this.isInspectingComponents) || !message) return;
    switch (message.type) {
      case 'inspect':
        this.onInspect?.({
          framework: message.framework ?? null,
          name: message.name ?? null,
          file: message.file ?? null,
          line: message.line ?? null,
          pageURL: this.url,
        });
        break;
      case 'inspectEnd':
        this.isInspectingComponents = false;
        break;
      default:
        this.devtools.receive(message);
    }
  }
}

// MARK: Routing host events to pages

function route(name: string, handle: (page: Page, payload: any) => void) {
  host.on(name, (payload: any) => {
    const page = registry.get(payload?.page);
    if (page) handle(page, payload);
  });
}

route('page.state', (page, p) => page.applyState(p));
route('page.load', (page, p) => page.loadEvent(p.phase, p.url));
route('page.committed', (page, p) => page.didCommit(p.url ?? null, !!p.secure));
route('page.response', (page, p) => page.response(p.status ?? null, p.mime ?? null));
route('page.failed', (page, p) => page.fail(String(p.message ?? 'The page couldn’t be loaded.')));
route('page.closeRequest', (page) => page.onClose?.());
route('page.focused', (page) => page.onFocused?.(page));
route('page.fullscreen', (page, p) => (page.isFullscreen = !!p.on));
route('page.external', (_page, p) => host.send('open.external', { url: p.url }));
route('page.message', (page, p) => {
  switch (p.channel) {
    case 'wake':
      page.receive(p.message);
      break;
    case 'wakeDev':
      page.receiveDeveloperMessage(p.message);
      break;
    case 'wakeDT':
      page.onDevToolsMessage?.(p.message);
      break;
    case 'wakePopOut':
      page.onPopOutMessage?.(p.message);
      break;
  }
});
host.on('page.popup', (p: any) => {
  const opener = registry.get(p.opener);
  const popup = new Page({ adopt: p.page });
  popup.requestedURL = p.url ?? null;
  popup.developerModeOverride = opener?.developerModeOverride ?? null;
  if (!opener?.onPopup?.(popup)) popup.close();
});

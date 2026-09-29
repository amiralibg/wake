// Per-window browser state (port of BrowserModel.swift and its Moments and
// column-mode extensions): the active thread and its trail, background threads,
// the palette, the Deck, settings, Zen, pinned apps and Moments.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { settings, SINK_AFTER_DAYS } from './settings';
import { BrowserThread, threadStore, type ThreadRecord } from './threads';
import { PaletteModel, type PaletteItem, type PaletteTarget, type RecentPage } from './palette';
import { PinnedAppsModel, type PinnedApp } from './apps';
import { history } from './history';
import { Page, isLocal, samePage, hostOf } from './page';
import { topChip } from './live';
import { buildDeck, threadThumbnails, momentThumbnails, type DeckArrangement, type DeckItem, type LiveThread } from './deck';
import { momentStore, parsePageState, MomentWatcher, type Moment, type MomentShelf } from './moments';
import { type DevicePreset, DEFAULT_PHONE } from './device';
import { popOuts } from './popout';
import { devServers, projectFor, type DevEnvironment, type DevServer } from './developer';
import { openInEditor } from './editor';

export type SettingsSection = 'general' | 'appearance' | 'search' | 'deck' | 'privacy' | 'developer';
export type MomentsLayout = 'grid' | 'timeline';

export type ColumnCommand =
  | 'previous' | 'next' | 'moveLeft' | 'moveRight' | 'cycleForward' | 'cycleBackward' | 'first' | 'last'
  | 'wider' | 'narrower' | 'defaultWidth' | 'close' | 'duplicate' | 'reopen' | 'newColumn' | 'exit'
  | { jump: number };

/** Threads switched away from stay alive (media keeps playing) up to this many. */
const MAX_BACKGROUND_THREADS = 4;
/** A thread left alone this long in the background is discarded. */
const DISCARD_AFTER = 10 * 60_000;

export class BrowserModel {
  thread: BrowserThread;
  readonly palette = new PaletteModel();
  readonly apps = new PinnedAppsModel();
  windowID = 0;
  platform = 'linux';

  isPaletteOpen = false;
  isSettingsOpen = false;
  settingsSection: SettingsSection = 'appearance';
  isZen = !!settings.get('window.zen', false);
  /** In Zen, whether the toolbar is slid in. */
  isChromeRevealed = false;
  /** In Zen (or when set to hide), whether the app capsule has slid in. */
  isCapsuleRevealed = false;
  /** Bumps whenever thread records change, so lists re-read. */
  threadListVersion = 0;

  isDeckOpen = false;
  deckArrangement: DeckArrangement = 'heat';
  isDeckPeeking = false;

  isMomentsOpen = false;
  momentsShelf: MomentShelf = 'everything';
  momentsQuery = '';
  momentsLayout: MomentsLayout = 'grid';
  /** The moment just saved, while its note island is up. */
  savedMoment: Moment | null = null;
  isImportingBrowserData = false;
  isColumnModeActive = false;
  /** A popover or menu over the pages (thread switcher, context menus). */
  openMenus = 0;
  /** A page is showing its fullscreen element (video): it fills the window. */
  fullscreenPage: Page | null = null;
  /** Downloads this window started, newest first. */
  downloads: { url: string; path: string | null; state: string; at: number }[] = [];
  /** Short messages at the bottom ("Copied", "Download finished"). */
  toast: { text: string; action?: { label: string; run: () => void } } | null = null;
  isOnboarding = !settings.get('onboarding.completed', false);

  private backgroundThreads: BrowserThread[] = [];
  private discardTimers = new Map<string, number>();
  private peekTimer = 0;
  private capsuleTimer = 0;
  private columnModeTimer = 0;
  private toastTimer = 0;
  watcher: MomentWatcher | null = null;

  constructor(thread: BrowserThread) {
    this.thread = thread;
    makeAutoObservable<BrowserModel, 'backgroundThreads' | 'discardTimers' | 'peekTimer' | 'capsuleTimer' | 'columnModeTimer' | 'toastTimer'>(this, {
      palette: false,
      apps: false,
      backgroundThreads: false,
      discardTimers: false,
      peekTimer: false,
      capsuleTimer: false,
      columnModeTimer: false,
      toastTimer: false,
      watcher: false,
    });
    this.palette.recents = () => this.recents;
    this.apps.configurePage = (page) => {
      // A pinned app is a place you return to; what you open from it joins the trail.
      page.onOpenLink = (url, background) => this.openFromApp(url, background);
      page.onPopup = (popup) => {
        this.apps.dismiss();
        this.trail.adoptPopup(popup, null);
        return true;
      };
      page.onPopOutPick = (pick) => popOuts.open(pick);
      page.setTrailWheel(false);
    };
  }

  /** Picks the thread a new window starts with: the most recent one nobody shows. */
  static async create(windowID: number): Promise<BrowserModel> {
    await threadStore.load();
    const resumable = settings.restoresLastThread
      ? threadStore.unresolvedThreads.find((r) => threadStore.owner(r.id) == null)
      : undefined;
    const browser = new BrowserModel(resumable ? new BrowserThread(resumable) : new BrowserThread());
    browser.windowID = windowID;
    await browser.activate(browser.thread);
    void browser.apps.load();
    void history.refresh(false);
    void momentStore.load();
    return browser;
  }

  get trail() {
    return this.thread.trail;
  }

  get page(): Page | null {
    return this.trail.focused;
  }

  /** The web page developer actions apply to (not a DevTools column). */
  get webPage(): Page | null {
    const page = this.page;
    return page?.isDevTools ? page.inspectedPage : page;
  }

  get recents(): RecentPage[] {
    return history.recent.map((v) => ({ url: v.url, title: v.title, visitedAt: v.visitedAt }));
  }

  // MARK: What covers the pages

  /**
   * True while the UI draws something over the pages: they're then shown as
   * snapshots (a native webview can't be drawn over; see desktop/README.md).
   */
  get coversPages(): boolean {
    return (
      this.isPaletteOpen ||
      this.isDeckOpen ||
      this.isDeckPeeking ||
      this.isSettingsOpen ||
      this.isMomentsOpen ||
      this.isImportingBrowserData ||
      this.isOnboarding ||
      this.openMenus > 0 ||
      this.savedMoment != null ||
      this.isColumnModeActive ||
      (this.isZen && this.isChromeRevealed) ||
      (this.capsuleFloats && this.isCapsuleRevealed) ||
      this.apps.active != null
    );
  }

  get hasOverlay(): boolean {
    return (
      this.isSettingsOpen || this.isPaletteOpen || this.isDeckOpen || this.apps.active != null || this.isMomentsOpen ||
      this.savedMoment != null || this.webPage?.isPickingPopOut === true || this.isImportingBrowserData
    );
  }

  menuOpened() {
    this.openMenus += 1;
  }

  menuClosed() {
    this.openMenus = Math.max(0, this.openMenus - 1);
  }

  showToast(text: string, action?: { label: string; run: () => void }) {
    clearTimeout(this.toastTimer);
    this.toast = { text, action };
    this.toastTimer = window.setTimeout(() => runInAction(() => (this.toast = null)), action ? 5000 : 2200);
  }

  // MARK: Closing

  /** Ctrl+W closes the innermost thing: an overlay, the showing app, then the focused column. */
  closeCommand() {
    if (this.savedMoment) this.finishSavingMoment();
    else if (this.isMomentsOpen) this.hideMoments();
    else if (this.isSettingsOpen) this.hideSettings();
    else if (this.isPaletteOpen || this.isDeckOpen) this.hidePalette();
    else if (this.apps.active) {
      this.apps.dismiss();
      this.refocusPage();
    } else if (this.page) this.trail.closeFocused();
    else void this.closeWindow();
  }

  /** Esc: close whichever overlay is up. */
  dismissOverlays() {
    const page = this.webPage;
    if (page?.isPickingPopOut) page.setPickingPopOut(false);
    else if (this.savedMoment) this.finishSavingMoment();
    else if (this.isMomentsOpen) this.hideMoments();
    else if (this.isSettingsOpen) this.hideSettings();
    else if (this.isPaletteOpen || this.isDeckOpen) this.hidePalette();
    else if (this.isImportingBrowserData) this.isImportingBrowserData = false;
    else if (this.apps.active) {
      this.apps.dismiss();
      this.refocusPage();
    }
  }

  /** Saves everything this window holds and lets its threads go, then closes it. */
  async closeWindow() {
    await threadStore.flush();
    for (const live of [this.thread, ...this.backgroundThreads]) {
      await threadStore.save(live);
      threadStore.release(live.id);
    }
    host.send('window.close');
  }

  copyPageURL() {
    const url = this.webPage?.url;
    if (!url) return;
    host.send('clipboard.write', { text: url });
    this.showToast('Address copied');
  }

  // MARK: Palette and Deck

  /** Ctrl+K, Ctrl+T and + open the Deck with its search field; Ctrl+L and the address bar the plain palette. */
  showPalette(target: PaletteTarget = 'newColumn') {
    if (target === 'newColumn' || this.trail.columns.length === 0) {
      this.openDeck();
      return;
    }
    this.isSettingsOpen = false;
    this.isDeckOpen = false;
    this.isMomentsOpen = false;
    this.palette.reset();
    this.palette.target = 'currentColumn';
    this.palette.showsRecentsWhenEmpty = true;
    this.isPaletteOpen = true;
    if (this.isZen) this.isChromeRevealed = false;
  }

  hidePalette() {
    this.isPaletteOpen = false;
    this.isDeckOpen = false;
    this.refocusPage();
  }

  togglePalette() {
    if (this.isPaletteOpen || this.isDeckOpen) this.hidePalette();
    else this.showPalette();
  }

  openDeck() {
    this.apps.dismiss();
    this.isMomentsOpen = false;
    this.captureThumbnail();
    this.isSettingsOpen = false;
    this.isPaletteOpen = false;
    this.palette.reset();
    this.palette.target = 'newColumn';
    this.palette.showsRecentsWhenEmpty = false;
    this.isDeckPeeking = false;
    this.isDeckOpen = true;
    if (this.isZen) this.isChromeRevealed = false;
  }

  choose(item: PaletteItem) {
    switch (item.kind) {
      case 'open':
        return this.openURL(item.url);
      case 'result':
        return this.openURL(item.result.url);
      case 'recent':
        return this.openURL(item.page.url);
      case 'suggestion':
        // With palette results, a suggestion refines them in place; without, it searches.
        if (settings.braveAPIKey) this.palette.setQuery(item.text);
        else this.openURL(settings.searchURL(item.text));
        return;
      case 'searchOnWeb':
        return this.openURL(settings.searchURL(item.query));
    }
  }

  private openURL(url: string) {
    const target = this.palette.target;
    this.hidePalette();
    if (target === 'currentColumn' && this.page && !this.page.isDevTools) this.page.load(url);
    else this.trail.open(url);
  }

  refocusPage() {
    const page = this.page;
    if (page && !page.isDevTools) page.focus();
    else host.send('shell.focus');
  }

  /** Cards for the Deck, from saved threads plus what live pages report. */
  get deckItems(): DeckItem[] {
    void this.threadListVersion;
    const live = new Map<string, LiveThread>();
    for (const thread of [this.thread, ...this.backgroundThreads]) {
      const pages = thread.trail.columns;
      live.set(thread.id, {
        pageCount: thread.pageCount,
        isPlaying: pages.some((p) => p.isPlayingMedia),
        hasUnsaved: pages.some((p) => p.hasUnsavedInput),
        title: thread.title,
        host: pages[0]?.host ?? '',
        chip: topChip(pages.filter((p) => !p.isDevTools)),
      });
    }
    const days = SINK_AFTER_DAYS[settings.sinkAfter];
    return buildDeck({
      records: threadStore.unresolvedThreads,
      live,
      activeID: this.thread.id,
      sinkAfter: days == null ? null : days * 86_400,
      keepActiveAfloat: settings.keepActiveAfloat,
      arrangement: this.deckArrangement,
    });
  }

  selectDeckItem(item: DeckItem) {
    this.isDeckPeeking = false;
    if (item.threadID === this.thread.id) {
      if (this.isDeckOpen) this.hidePalette();
      else this.openDeck();
      return;
    }
    this.hidePalette();
    void this.switchToThread(item.threadID);
  }

  /** Dragging a sunk card up: it's warm again. */
  async revive(threadID: string) {
    await threadStore.touch(threadID);
    this.threadListVersion++;
  }

  /** "Let them go": closes every thread below the waterline. */
  async letGo(threadIDs: string[]) {
    for (const id of threadIDs) {
      if (id === this.thread.id || this.backgroundThreads.some((t) => t.id === id)) continue;
      if (threadStore.owner(id) != null) continue;
      await threadStore.delete(id);
      threadThumbnails.remove(id);
    }
    runInAction(() => this.threadListVersion++);
  }

  /** The pointer reached the bottom edge: bring the Deck island up. */
  peekDeck() {
    clearTimeout(this.peekTimer);
    if (this.isDeckOpen || this.isSettingsOpen || this.isPaletteOpen || this.isDeckPeeking || this.isMomentsOpen) return;
    this.captureThumbnail();
    this.isDeckPeeking = true;
    // If the pointer never moves onto the island, it goes away on its own.
    this.endDeckPeek(1200);
  }

  holdDeckPeek() {
    clearTimeout(this.peekTimer);
  }

  endDeckPeek(delay = 450) {
    clearTimeout(this.peekTimer);
    this.peekTimer = window.setTimeout(() => runInAction(() => (this.isDeckPeeking = false)), delay);
  }

  /** Scrolling a page means reading: put the island away. */
  noteReadingScroll() {
    if (this.isDeckPeeking) this.endDeckPeek(0);
  }

  captureThumbnail() {
    const page = this.page;
    if (page && !page.isDevTools && page.url) void threadThumbnails.capture(page, this.thread.id);
  }

  // MARK: Zen and edges

  setZen(on: boolean) {
    this.isZen = on;
    settings.set('window.zen', on);
    this.isChromeRevealed = false;
    // A reveal belongs to the mode it happened in.
    this.concealCapsule();
  }

  revealZenChrome() {
    if (!this.isZen || this.isChromeRevealed) return;
    this.isChromeRevealed = true;
  }

  concealZenChrome() {
    if (this.isPaletteOpen) return;
    this.isChromeRevealed = false;
  }

  get showsAppCapsule() {
    return !this.capsuleFloats || this.isCapsuleRevealed;
  }

  /** In Zen, or when set to hide at the edge, the capsule floats over the pages on demand. */
  get capsuleFloats() {
    return this.isZen || settings.capsuleHidesAtEdge;
  }

  revealCapsule() {
    if (!this.capsuleFloats || this.isCapsuleRevealed) return;
    this.isCapsuleRevealed = true;
    this.scheduleCapsuleConceal();
  }

  concealCapsule() {
    clearTimeout(this.capsuleTimer);
    this.isCapsuleRevealed = false;
  }

  capsuleHovered(inside: boolean) {
    if (inside) clearTimeout(this.capsuleTimer);
    else if (this.capsuleFloats) this.concealCapsule();
  }

  private scheduleCapsuleConceal() {
    clearTimeout(this.capsuleTimer);
    this.capsuleTimer = window.setTimeout(() => runInAction(() => this.concealCapsule()), 1600);
  }

  // MARK: Settings

  showSettings(section?: SettingsSection) {
    this.isMomentsOpen = false;
    this.isPaletteOpen = false;
    this.isDeckOpen = false;
    this.apps.dismiss();
    if (section) this.settingsSection = section;
    this.isSettingsOpen = true;
  }

  hideSettings() {
    this.isSettingsOpen = false;
    this.refocusPage();
  }

  // MARK: Pinned apps

  toggleApp(app: PinnedApp) {
    this.isPaletteOpen = false;
    this.isDeckOpen = false;
    this.isSettingsOpen = false;
    this.apps.toggle(app);
    if (this.apps.active) this.apps.active.page.focus();
    else this.refocusPage();
  }

  toggleAppIndex(index: number) {
    const app = this.apps.apps[index];
    if (app) this.toggleApp(app);
  }

  pin(page: Page) {
    if (page.url) void this.apps.pin(page.url, page.displayTitle);
  }

  unpin(app: PinnedApp) {
    void this.apps.unpin(app);
  }

  private openFromApp(url: string, background: boolean) {
    if (!background) this.apps.dismiss();
    this.trail.open(url, null, !background);
  }

  // MARK: Developer

  get devServers(): DevServer[] {
    return settings.scansPorts ? devServers.servers : [];
  }

  toggleDevTools() {
    const page = this.webPage;
    if (page) this.trail.toggleDevTools(page);
  }

  /** Opens DevTools beside the page (if closed) on `tab`. */
  showDevTools(tab: string) {
    const page = this.webPage;
    if (!page) return;
    page.devtoolsTab = tab;
    if (!this.trail.devTools(page)) this.trail.toggleDevTools(page);
  }

  inspectElement() {
    const page = this.webPage;
    if (!page) return;
    this.showDevTools('elements');
    page.devtoolsPickRequest++;
  }

  showWebInspector() {
    const page = this.webPage;
    if (page && settings.webInspectorEnabled) host.send('page.inspector', { page: page.id });
  }

  /** Flips developer mode for the whole thread and reloads, so the hooks see the page from its first line. */
  toggleDeveloperMode() {
    this.thread.setDeveloperMode(!(this.webPage?.isDeveloperMode ?? false));
    threadStore.scheduleSave(this.thread);
    this.webPage?.reload();
  }

  resetDeveloperMode() {
    this.thread.setDeveloperMode(null);
    threadStore.scheduleSave(this.thread);
    this.webPage?.reload();
  }

  openResponsivePreview(preset: DevicePreset = DEFAULT_PHONE) {
    const page = this.webPage;
    if (!page) return;
    const source = this.trail.previewSource(page) ?? page;
    this.trail.openResponsivePreview(source, preset);
  }

  /** Empties the engine's HTTP caches (not cookies or storage). */
  emptyCaches() {
    void host.call('data.clearCache').then(
      () => this.showToast('Caches emptied'),
      () => this.showToast('Couldn’t empty the caches'),
    );
  }

  togglePopOutPicker() {
    const page = this.webPage;
    if (!page?.url) return;
    if (page.isInspectingComponents) page.setInspectingComponents(false);
    page.setPickingPopOut(!page.isPickingPopOut);
  }

  toggleComponentInspector() {
    const page = this.webPage;
    if (page) page.setInspectingComponents(!page.isInspectingComponents);
  }

  /** Same path and query on another environment of the page's project. */
  switchEnvironment(environment: DevEnvironment) {
    const page = this.webPage;
    const url = page?.url;
    if (!page || !url) return;
    const target = projectFor(url)?.url(url, environment);
    if (target) page.load(target);
  }

  /** Focuses a column already showing the server, or opens one. */
  openDevServer(server: DevServer) {
    const existing = this.trail.columns.find((c) => isLocal(c.url) && c.url && new URL(c.url).port === String(server.port));
    if (existing) this.trail.focusID(existing.id);
    else this.trail.open(server.url);
  }

  // MARK: Threads

  get otherThreads(): ThreadRecord[] {
    void this.threadListVersion;
    return threadStore.unresolvedThreads.filter((r) => r.id !== this.thread.id);
  }

  newThread() {
    void this.switchTo(new BrowserThread()).then(() => this.showPalette());
  }

  /** Switches to a saved thread. If another window already shows it, that window comes forward instead. */
  async switchToThread(id: string) {
    if (id === this.thread.id) return;
    const owner = threadStore.owner(id);
    if (owner != null && owner !== this.windowID) {
      host.send('threads.focusOwner', { thread: id });
      return;
    }
    const alive = this.backgroundThreads.find((t) => t.id === id);
    if (alive) return this.switchTo(alive);
    const record = threadStore.record(id);
    if (record) await this.switchTo(new BrowserThread(record));
  }

  renameThread(title: string) {
    const trimmed = title.trim();
    this.thread.customTitle = trimmed || null;
    threadStore.scheduleSave(this.thread);
    this.threadListVersion++;
  }

  /** Records a one-line outcome, closes the thread's pages and moves on. */
  async resolveThread(outcome: string) {
    await threadStore.resolve(this.thread, outcome.trim());
    const resolved = this.thread;
    const nextRecord = threadStore.unresolvedThreads.find((r) => r.id !== resolved.id && threadStore.owner(r.id) == null);
    const next = this.backgroundThreads[0] ?? (nextRecord ? new BrowserThread(nextRecord) : new BrowserThread());
    await this.switchTo(next, false, false);
    if (!this.trail.columns.length) this.showPalette();
  }

  async reopenResolvedThread(id: string) {
    await threadStore.unresolve(id);
    this.threadListVersion++;
    await this.switchToThread(id);
  }

  async deleteThread(id: string) {
    if (id === this.thread.id) return;
    const live = this.backgroundThreads.find((t) => t.id === id);
    if (live) {
      this.backgroundThreads = this.backgroundThreads.filter((t) => t !== live);
      clearTimeout(this.discardTimers.get(id));
      this.discardTimers.delete(id);
      this.unload(live);
    }
    if (threadStore.owner(id) != null) return;
    await threadStore.delete(id);
    threadThumbnails.remove(id);
    runInAction(() => this.threadListVersion++);
  }

  private async switchTo(next: BrowserThread, saveCurrent = true, keepAlive = true) {
    this.captureThumbnail();
    const previous = this.thread;
    if (saveCurrent) void threadStore.save(previous);
    this.backgroundThreads = this.backgroundThreads.filter((t) => t !== next && t !== previous);
    clearTimeout(this.discardTimers.get(next.id));
    this.discardTimers.delete(next.id);
    if (keepAlive && previous.isLoaded) {
      this.backgroundThreads.unshift(previous);
      this.scheduleDiscard(previous);
    } else {
      this.unload(previous);
    }
    // Past the limit, unload the least recent loaded thread that isn't playing anything.
    while (this.backgroundThreads.filter((t) => t.isLoaded).length > MAX_BACKGROUND_THREADS) {
      const loaded = this.backgroundThreads.filter((t) => t.isLoaded);
      const victim =
        [...loaded].reverse().find((t) => !t.trail.columns.some((p) => p.isPlayingMedia)) ?? loaded[loaded.length - 1];
      this.backgroundThreads = this.backgroundThreads.filter((t) => t !== victim);
      clearTimeout(this.discardTimers.get(victim.id));
      this.discardTimers.delete(victim.id);
      void threadStore.save(victim);
      this.unload(victim);
    }
    runInAction(() => (this.thread = next));
    await this.activate(next);
    runInAction(() => this.threadListVersion++);
  }

  private scheduleDiscard(thread: BrowserThread) {
    clearTimeout(this.discardTimers.get(thread.id));
    this.discardTimers.set(
      thread.id,
      window.setTimeout(() => void this.discard(thread), DISCARD_AFTER),
    );
  }

  /** Frees a background thread's webviews unless it's playing or has typed input. */
  private async discard(thread: BrowserThread) {
    this.discardTimers.delete(thread.id);
    if (thread === this.thread || !this.backgroundThreads.includes(thread) || !thread.isLoaded) return;
    if (thread.trail.columns.some((p) => p.isPlayingMedia || p.hasUnsavedInput)) {
      this.scheduleDiscard(thread);
      return;
    }
    await threadStore.save(thread);
    await thread.discard(() => thread !== this.thread);
  }

  private unload(thread: BrowserThread) {
    threadStore.release(thread.id);
    thread.trail.closeAll();
  }

  private async activate(thread: BrowserThread) {
    thread.lastActiveAt = Date.now() / 1000;
    await threadStore.claim(thread.id);
    const trail = thread.trail;
    trail.didCreatePage = (page) => {
      page.onDidFinish = (p) => this.remember(p);
      page.onPopOutPick = (pick) => popOuts.open(pick);
      page.onInspect = (pick) => void openInEditor(pick);
      page.onTrailWheel = (message) => this.trailWheel(message);
    };
    trail.onChange = () => {
      // Pages in a thread you've left keep changing their URL and title; that's
      // worth saving, but it isn't you using the thread.
      if (thread === this.thread) thread.lastActiveAt = Date.now() / 1000;
      threadStore.scheduleSave(thread);
    };
    trail.onFocus = (page) => {
      if (thread === this.thread && !this.coversPages) page.focus();
    };
    thread.restoreIfNeeded();
  }

  private remember(page: Page) {
    if (page === this.page) this.captureThumbnail();
    if (page.isRestoring) {
      page.isRestoring = false;
      return;
    }
    const url = page.url;
    if (!url || !/^https?:/.test(url) || page.isEphemeral) return;
    void history.recordVisit(url, page.title);
  }

  // MARK: Wheel over pages (shared/scripts/trail-wheel.js)

  private panVelocity = { last: 0, dx: 0 };

  trailWheel(message: { type: string; dx?: number; direction?: number }) {
    if (this.coversPages) return;
    switch (message.type) {
      case 'trailStep':
        if (!settings.shiftScrollMovesColumns) return;
        if ((message.direction ?? 0) > 0) this.trail.focusNext();
        else this.trail.focusPrevious();
        break;
      case 'trailPan': {
        const now = performance.now();
        const dx = message.dx ?? 0;
        const dt = Math.max(1, now - this.panVelocity.last);
        this.panVelocity = { last: now, dx: (-dx / dt) * 1000 };
        this.trail.scroll(-dx);
        break;
      }
      case 'trailPanEnd':
        this.trail.endScroll(this.panVelocity.dx);
        this.panVelocity = { last: 0, dx: 0 };
        break;
    }
  }

  // MARK: Moments

  /** The site you're on, for "Relevant here". */
  get momentsHost(): string | null {
    return hostOf(this.webPage?.url) || null;
  }

  /** Ctrl+D: saves the focused page as a moment right away, then offers a note. */
  async saveMoment() {
    const page = this.webPage;
    const url = page?.url;
    if (!page || !url || !/^https?:/.test(url)) return;
    const threadID = this.thread.id;
    const value = await page.run('moment-capture', { maxText: 40_000 }).catch(() => null);
    const state = parsePageState(value);
    if (!state.title) state.title = page.displayTitle;
    const moment = await momentStore.save(url, state, threadID, 'nextWeek');
    void momentThumbnails.capture(page, moment.id);
    runInAction(() => (this.savedMoment = moment));
  }

  finishSavingMoment() {
    this.savedMoment = null;
    this.refocusPage();
  }

  undoSaveMoment() {
    if (this.savedMoment) void momentStore.delete(this.savedMoment);
    this.finishSavingMoment();
  }

  toggleMoments() {
    if (this.isMomentsOpen) this.hideMoments();
    else this.showMoments();
  }

  showMoments(shelf?: MomentShelf) {
    this.hidePalette();
    this.isSettingsOpen = false;
    this.apps.dismiss();
    this.savedMoment = null;
    this.momentsQuery = '';
    if (shelf) this.momentsShelf = shelf;
    void momentStore.archiveStale();
    this.isMomentsOpen = true;
  }

  /** Ctrl+H: the library, open on History. */
  showHistory(shelf: MomentShelf = 'history') {
    if (this.isMomentsOpen && this.momentsShelf === shelf) this.hideMoments();
    else this.showMoments(shelf);
  }

  openFromLibrary(url: string) {
    this.isMomentsOpen = false;
    this.trail.open(url);
  }

  hideMoments() {
    this.isMomentsOpen = false;
    this.refocusPage();
  }

  /** Takes you back to the moment: its page, scrolled to where you were, selection highlighted. */
  openMoment(moment: Moment) {
    this.isMomentsOpen = false;
    void momentStore.markOpened(moment);
    const restore = {
      selection: moment.selectedText,
      prefix: moment.selectionPrefix,
      scrollY: moment.scrollY,
      scrollFraction: moment.scrollFraction,
    };
    const rebaseline = (page: Page) => void page.visibleText().then((text) => momentStore.rebaseline(moment, text));
    const open = this.trail.columns.find((c) => !c.isDevTools && !c.device && samePage(c.url, moment.url));
    if (open) {
      this.trail.focusID(open.id);
      void open.applyRestore(restore).then(() => rebaseline(open));
    } else {
      const page = this.trail.open(moment.url);
      page.pendingRestore = restore;
      page.onRestored = rebaseline;
    }
  }

  reopenThread(record: ThreadRecord) {
    this.isMomentsOpen = false;
    void this.reopenResolvedThread(record.id);
  }

  startWatcher() {
    if (this.watcher) return;
    this.watcher = new MomentWatcher(() => {
      const page = new Page({ ephemeral: true });
      return page;
    });
    this.watcher.start();
  }

  // MARK: Column mode (Vim's window keys, after Alt+W)

  enterColumnMode() {
    if (!this.trail.columns.length || this.hasOverlay) return;
    this.isColumnModeActive = true;
    host.send('shell.focus');
    this.restartColumnModeTimeout();
  }

  exitColumnMode() {
    clearTimeout(this.columnModeTimer);
    if (!this.isColumnModeActive) return;
    this.isColumnModeActive = false;
    this.refocusPage();
  }

  perform(command: ColumnCommand) {
    const trail = this.trail;
    if (typeof command === 'object') trail.focus(command.jump);
    else {
      switch (command) {
        case 'previous': trail.focusPrevious(); break;
        case 'next': trail.focusNext(); break;
        case 'moveLeft': trail.moveFocused(-1); break;
        case 'moveRight': trail.moveFocused(1); break;
        case 'cycleForward': trail.cycleFocus(true); break;
        case 'cycleBackward': trail.cycleFocus(false); break;
        case 'first': trail.focus(0); break;
        case 'last': trail.focus(trail.columns.length - 1); break;
        case 'wider': trail.resizeFocused(0.1); break;
        case 'narrower': trail.resizeFocused(-0.1); break;
        case 'defaultWidth': if (this.page) trail.resetWidth(this.page); break;
        case 'close': trail.closeFocused(); break;
        case 'duplicate': trail.duplicateFocused(); break;
        case 'reopen': trail.reopenClosed(); break;
        case 'newColumn':
          this.exitColumnMode();
          this.showPalette('newColumn');
          return;
        case 'exit':
          this.exitColumnMode();
          return;
      }
    }
    if (!trail.columns.length) this.exitColumnMode();
    if (this.isColumnModeActive) this.restartColumnModeTimeout();
  }

  /** A mode left on while you look away would eat the next thing you type. */
  private restartColumnModeTimeout() {
    clearTimeout(this.columnModeTimer);
    this.columnModeTimer = window.setTimeout(() => runInAction(() => this.exitColumnMode()), 4000);
  }

  // MARK: Onboarding

  finishOnboarding() {
    this.isOnboarding = false;
    settings.set('onboarding.completed', true);
    if (!this.trail.columns.length) this.showPalette();
  }

  showOnboarding() {
    this.isOnboarding = true;
  }

  // MARK: Downloads and fullscreen

  noteDownload(payload: { state: string; url: string; path: string | null }) {
    const existing = this.downloads.find((d) => d.url === payload.url && d.state === 'started');
    if (existing) {
      existing.state = payload.state;
      existing.path = payload.path ?? existing.path;
    } else {
      this.downloads.unshift({ ...payload, at: Date.now() });
    }
    const name = (payload.path ?? payload.url).split(/[\\/]/).pop();
    if (payload.state === 'finished') {
      this.showToast(`Downloaded ${name}`, payload.path ? { label: 'Show', run: () => host.send('open.reveal', { path: payload.path }) } : undefined);
    } else if (payload.state === 'failed') {
      this.showToast(`Download failed: ${name}`);
    } else {
      this.showToast(`Downloading ${name}…`);
    }
  }

  setFullscreen(page: Page | null) {
    this.fullscreenPage = page;
    host.send('window.fullscreen', { on: !!page });
  }
}

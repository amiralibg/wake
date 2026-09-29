// Moments: pages saved as they were, with where you were in them and why (ports
// of MomentRecord, MomentStore, MomentRules, MomentDiff and MomentWatcher).

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { db } from '../host/db';
import { hostOf } from './page';

export interface Moment {
  id: string;
  url: string;
  title: string;
  /** Seconds since 1970, like every date in the schema. */
  createdAt: number;
  note: string | null;
  selectedText: string | null;
  selectionPrefix: string | null;
  scrollY: number;
  scrollFraction: number;
  contentHash: string;
  contentText: string;
  resurfaceAt: number | null;
  lastOpenedAt: number | null;
  openCount: number;
  lastCheckedAt: number | null;
  changedAt: number | null;
  changeSummary: string | null;
  isArchived: boolean;
  threadID: string | null;
}

export const momentHost = (m: Moment) => hostOf(m.url);
/** Last time you had anything to do with it. */
export const lastSeenAt = (m: Moment) => m.lastOpenedAt ?? m.createdAt;

// MARK: Rules

const DAY = 86_400;
/** Unopened this long, a moment starts fading… */
export const FADE_AFTER = 30 * DAY;
/** …and this long, it's archived. */
export const ARCHIVE_AFTER = 45 * DAY;

const nowSeconds = () => Date.now() / 1000;

export const rules = {
  isFading: (m: Moment, now = nowSeconds()) => !m.isArchived && now - lastSeenAt(m) >= FADE_AFTER,
  shouldArchive: (m: Moment, now = nowSeconds()) => !m.isArchived && now - lastSeenAt(m) >= ARCHIVE_AFTER,
  daysUntilArchive: (m: Moment, now = nowSeconds()) => Math.max(0, Math.ceil((ARCHIVE_AFTER - (now - lastSeenAt(m))) / DAY)),
  /** Due today (or overdue) and not opened since it came due. */
  isResurfacing(m: Moment, now = new Date()) {
    if (m.isArchived || m.resurfaceAt == null) return false;
    const endOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime() / 1000;
    if (m.resurfaceAt >= endOfToday) return false;
    if (m.lastOpenedAt != null && m.lastOpenedAt >= m.resurfaceAt) return false;
    return true;
  },
  isRelevant(m: Moment, site: string | null) {
    if (!site || m.isArchived) return false;
    const h = momentHost(m);
    return h === site || h.endsWith('.' + site) || site.endsWith('.' + h);
  },
};

export type ResurfaceChoice = 'whenRelevant' | 'tomorrow' | 'weekend' | 'nextWeek' | 'nextMonth';

export const RESURFACE_LABELS: Record<ResurfaceChoice, string> = {
  whenRelevant: 'Only on its site',
  tomorrow: 'Tomorrow',
  weekend: 'This weekend',
  nextWeek: 'Next week',
  nextMonth: 'In a month',
};

/** Mornings, so it's waiting when the day starts. Seconds since 1970, or null. */
export function resurfaceDate(choice: ResurfaceChoice, from = new Date()): number | null {
  const morning = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 9, 0, 0).getTime() / 1000;
  const day = (offset: number) => new Date(from.getFullYear(), from.getMonth(), from.getDate() + offset);
  switch (choice) {
    case 'whenRelevant':
      return null;
    case 'tomorrow':
      return morning(day(1));
    case 'weekend': {
      const ahead = ((6 - from.getDay() + 7) % 7) || 7;
      return morning(day(ahead));
    }
    case 'nextWeek':
      return morning(day(7));
    case 'nextMonth':
      return morning(new Date(from.getFullYear(), from.getMonth() + 1, from.getDate()));
  }
}

// MARK: Diff

/** Visible text is capped so a huge page doesn't bloat the store. */
export const MAX_TEXT = 40_000;

export function normalized(text: string) {
  return text
    .split(/\r?\n/)
    .map((line) => line.split(/\s+/).filter(Boolean).join(' '))
    .filter(Boolean)
    .join('\n');
}

export async function hashText(text: string): Promise<string> {
  const data = new TextEncoder().encode(normalized(text));
  if (crypto.subtle) {
    const digest = await crypto.subtle.digest('SHA-256', data);
    return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
  }
  return host.call<string>('hash.sha256', { text: normalized(text) });
}

const PRICE = /(?:[$€£¥₹]\s?\d[\d,]*(?:\.\d{1,2})?|\d[\d,]*(?:\.\d{1,2})?\s?(?:USD|EUR|GBP|€|\$))/g;

export function prices(text: string) {
  return text.match(PRICE) ?? [];
}

const amount = (price: string) => {
  const n = parseFloat(price.replace(/[^\d.]/g, ''));
  return Number.isFinite(n) ? n : null;
};

/** A short description of what changed, or null when the difference is just noise. */
export function changeSummary(oldText: string, newText: string): string | null {
  const before = normalized(oldText);
  const after = normalized(newText);
  if (before === after) return null;
  const oldPrices = prices(before);
  const newPrices = prices(after);
  if (oldPrices.length && newPrices.length && oldPrices[0] !== newPrices[0]) {
    const was = amount(oldPrices[0]!);
    const now = amount(newPrices[0]!);
    if (was != null && now != null) {
      if (now < was) return `price ↓ ${newPrices[0]}`;
      if (now > was) return `price ↑ ${newPrices[0]}`;
    }
  }
  const oldLines = new Set(before.split('\n'));
  const newLines = new Set(after.split('\n'));
  const added = [...newLines].filter((l) => !oldLines.has(l));
  const removed = [...oldLines].filter((l) => !newLines.has(l));
  const changed = [...added, ...removed].reduce((n, l) => n + l.length, 0);
  // Below this it's a timestamp or a view counter, not a change worth telling.
  if (changed < 80) return null;
  if (!removed.length || added.length >= removed.length * 2) return 'new content';
  if (!added.length) return 'content removed';
  return 'text changed';
}

// MARK: Store

export interface MomentPageState {
  title: string;
  selection: string | null;
  selectionPrefix: string | null;
  scrollY: number;
  scrollFraction: number;
  text: string;
}

export function parsePageState(value: any): MomentPageState {
  return {
    title: typeof value?.title === 'string' ? value.title : '',
    selection: value?.selection ? String(value.selection) : null,
    selectionPrefix: value?.prefix ? String(value.prefix) : null,
    scrollY: Number(value?.scrollY) || 0,
    scrollFraction: Number(value?.fraction) || 0,
    text: String(value?.text ?? '').slice(0, MAX_TEXT),
  };
}

const COLUMNS = [
  'id', 'url', 'title', 'createdAt', 'note', 'selectedText', 'selectionPrefix', 'scrollY', 'scrollFraction', 'contentHash',
  'contentText', 'resurfaceAt', 'lastOpenedAt', 'openCount', 'lastCheckedAt', 'changedAt', 'changeSummary', 'isArchived', 'threadID',
] as const;

function toRow(m: Moment) {
  return COLUMNS.map((c) => (c === 'isArchived' ? (m.isArchived ? 1 : 0) : (m as any)[c]));
}

class MomentStore {
  all: Moment[] = [];
  version = 0;

  constructor() {
    makeAutoObservable(this);
    host.on('moments.changed', () => void this.load(false));
  }

  async load(notify = false) {
    const rows = await db.query('SELECT * FROM MomentRecord ORDER BY createdAt DESC');
    runInAction(() => {
      this.all = rows.map((r) => ({ ...r, isArchived: !!r.isArchived }) as Moment);
      this.version++;
    });
    if (notify) host.send('broadcast', { name: 'moments.changed' });
  }

  /** Newest first. Archived ones only when asked for. */
  moments(includingArchived = false): Moment[] {
    return includingArchived ? this.all : this.all.filter((m) => !m.isArchived);
  }

  moment(id: string) {
    return this.all.find((m) => m.id === id);
  }

  async save(url: string, state: MomentPageState, threadID: string | null, resurface: ResurfaceChoice): Promise<Moment> {
    const now = nowSeconds();
    const moment: Moment = {
      id: crypto.randomUUID(),
      url,
      title: state.title,
      createdAt: now,
      note: null,
      selectedText: state.selection,
      selectionPrefix: state.selectionPrefix,
      scrollY: state.scrollY,
      scrollFraction: state.scrollFraction,
      contentHash: await hashText(state.text),
      contentText: state.text,
      resurfaceAt: resurfaceDate(resurface),
      lastOpenedAt: null,
      openCount: 0,
      lastCheckedAt: now,
      changedAt: null,
      changeSummary: null,
      isArchived: false,
      threadID,
    };
    runInAction(() => {
      this.all = [moment, ...this.all];
      this.version++;
    });
    await db.exec(`INSERT INTO MomentRecord (${COLUMNS.map((c) => `"${c}"`).join(', ')}) VALUES (${COLUMNS.map(() => '?').join(', ')})`, toRow(moment));
    host.send('broadcast', { name: 'moments.changed' });
    return moment;
  }

  async update(id: string, change: Partial<Moment>) {
    const current = this.moment(id);
    if (!current) return;
    const next = { ...current, ...change };
    runInAction(() => {
      this.all = this.all.map((m) => (m.id === id ? next : m));
      this.version++;
    });
    const keys = Object.keys(change).filter((k) => (COLUMNS as readonly string[]).includes(k));
    if (!keys.length) return;
    await db.exec(
      `UPDATE MomentRecord SET ${keys.map((k) => `"${k}" = ?`).join(', ')} WHERE id = ?`,
      [...keys.map((k) => (k === 'isArchived' ? ((next as any)[k] ? 1 : 0) : (next as any)[k])), id],
    );
    host.send('broadcast', { name: 'moments.changed' });
  }

  /** Opened: it's fresh again. */
  markOpened(m: Moment) {
    return this.update(m.id, { lastOpenedAt: nowSeconds(), openCount: m.openCount + 1 });
  }

  /** What's on screen now becomes the new baseline. */
  async rebaseline(m: Moment, text: string) {
    if (!text) return;
    const capped = text.slice(0, MAX_TEXT);
    await this.update(m.id, { contentText: capped, contentHash: await hashText(text), changedAt: null, changeSummary: null, lastCheckedAt: nowSeconds() });
  }

  async delete(m: Moment) {
    host.send('file.remove', { path: `moments/${m.id}.jpg` });
    runInAction(() => {
      this.all = this.all.filter((x) => x.id !== m.id);
      this.version++;
    });
    await db.exec('DELETE FROM MomentRecord WHERE id = ?', [m.id]);
    host.send('broadcast', { name: 'moments.changed' });
  }

  /** Moments nobody opened for ARCHIVE_AFTER go to the archive. */
  async archiveStale() {
    const stale = this.moments().filter((m) => rules.shouldArchive(m));
    for (const m of stale) await this.update(m.id, { isArchived: true });
  }
}

export const momentStore = new MomentStore();

// MARK: Shelves

export type MomentShelf =
  | 'everything' | 'relevant' | 'resurfacing' | 'changed' | 'fading' | 'archived' | 'history' | 'searches'
  | { resolvedThread: string };

export const SMART_SHELVES: MomentShelf[] = ['everything', 'relevant', 'resurfacing', 'changed', 'fading'];

export const SHELF_TITLES: Record<string, string> = {
  everything: 'Everything',
  relevant: 'Relevant here',
  resurfacing: 'Resurfacing today',
  changed: 'Changed since saved',
  fading: 'Fading',
  archived: 'Archived',
  history: 'History',
  searches: 'Searches',
};

export const SHELF_ICONS: Record<string, string> = {
  everything: 'inbox',
  relevant: 'map-pin',
  resurfacing: 'clock',
  changed: 'refresh-cw',
  fading: 'hourglass',
  archived: 'archive',
  history: 'history',
  searches: 'search',
};

export const shelfKey = (shelf: MomentShelf) => (typeof shelf === 'string' ? shelf : `thread:${shelf.resolvedThread}`);

export function shelfContains(shelf: MomentShelf, m: Moment, site: string | null, now = new Date()) {
  switch (shelf) {
    case 'everything': return !m.isArchived;
    case 'relevant': return rules.isRelevant(m, site);
    case 'resurfacing': return rules.isResurfacing(m, now);
    case 'changed': return !m.isArchived && m.changedAt != null;
    case 'fading': return rules.isFading(m, now.getTime() / 1000);
    case 'archived': return m.isArchived;
    default: return false;
  }
}

// MARK: Background watcher

/**
 * Looks at saved pages again in the background and marks the ones that changed:
 * each check loads the page in a hidden webview (with your cookies), reads its
 * visible text once it settles, and compares it with the text saved with the
 * moment. One page at a time, each at most every 12 hours. Only one window runs it.
 *
 * Limitation: checks only run while Wake is open.
 */
export class MomentWatcher {
  private readonly recheckAfter = 12 * 3600;
  private running = false;
  private stopped = false;

  constructor(private readonly makePage: () => import('./page').Page) {}

  start() {
    if (this.running) return;
    this.running = true;
    // Let launch and the first window settle before doing background work.
    setTimeout(() => void this.loop(), 20_000);
  }

  stop() {
    this.stopped = true;
  }

  private async loop() {
    while (!this.stopped) {
      await this.pass().catch(() => {});
      await new Promise((r) => setTimeout(r, 30 * 60_000));
    }
  }

  private async pass() {
    await momentStore.archiveStale();
    const now = nowSeconds();
    const due = momentStore
      .moments()
      .filter((m) => /^https?:/.test(m.url) && m.changedAt == null && now - (m.lastCheckedAt ?? 0) >= this.recheckAfter)
      .slice(0, 12);
    if (!due.length) return;
    const page = this.makePage();
    page.setTrailWheel(false);
    try {
      for (const m of due) {
        if (this.stopped) return;
        const text = await this.load(page, m.url);
        if (!text) continue;
        const same = (await hashText(text)) === m.contentHash;
        const summary = same ? null : changeSummary(m.contentText, text);
        await momentStore.update(m.id, summary ? { lastCheckedAt: nowSeconds(), changedAt: nowSeconds(), changeSummary: summary } : { lastCheckedAt: nowSeconds() });
      }
    } finally {
      page.close();
    }
  }

  private load(page: import('./page').Page, url: string): Promise<string | null> {
    return new Promise((resolve) => {
      let done = false;
      const finish = async (ok: boolean) => {
        if (done) return;
        done = true;
        page.onDidFinish = undefined;
        if (!ok) {
          page.stopLoading();
          return resolve(null);
        }
        // Script-rendered pages fill in after the load event.
        await new Promise((r) => setTimeout(r, 2000));
        resolve(await page.visibleText());
      };
      page.onDidFinish = () => void finish(true);
      setTimeout(() => void finish(false), 25_000);
      page.load(url);
    });
  }
}

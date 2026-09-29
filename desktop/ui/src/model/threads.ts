// Threads: the live ones (BrowserThread.swift) and the store (ThreadStore.swift).
// The store keeps every thread record in memory, writes through to SQLite in the
// host, and tells other windows when records change. Which window shows which
// thread is kept by the host, so one thread is never live in two windows.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { db, toSeconds } from '../host/db';
import { TrailModel, type ColumnSnapshot } from './trail';

export interface ColumnRecord {
  order: number;
  url: string;
  title: string;
  widthFraction: number | null;
}

export interface ThreadRecord {
  id: string;
  customTitle: string | null;
  title: string;
  /** Seconds since 1970. */
  createdAt: number;
  lastActiveAt: number;
  focusedIndex: number;
  isResolved: boolean;
  outcome: string | null;
  resolvedAt: number | null;
  developerMode: boolean | null;
  columns: ColumnRecord[];
}

const now = () => Date.now() / 1000;
const newID = () => crypto.randomUUID();

export class BrowserThread {
  readonly id: string;
  readonly createdAt: number;
  customTitle: string | null;
  lastActiveAt: number;
  /** Developer mode for the whole thread; null is automatic (on for localhost). */
  developerMode: boolean | null = null;
  readonly trail = new TrailModel();
  private pendingColumns: ColumnSnapshot[] = [];
  private pendingFocus = 0;

  constructor(record?: ThreadRecord) {
    if (record) {
      this.id = record.id;
      this.customTitle = record.customTitle;
      this.developerMode = record.developerMode;
      this.createdAt = record.createdAt;
      this.lastActiveAt = record.lastActiveAt;
      this.pendingColumns = [...record.columns]
        .sort((a, b) => a.order - b.order)
        .map((c) => ({ url: c.url, title: c.title, widthFraction: c.widthFraction }));
      this.pendingFocus = record.focusedIndex;
    } else {
      this.id = newID();
      this.customTitle = null;
      this.createdAt = now();
      this.lastActiveAt = this.createdAt;
    }
    makeAutoObservable(this, { id: false, createdAt: false, trail: false });
  }

  get title(): string {
    if (this.customTitle?.trim()) return this.customTitle;
    return this.trail.columns[0]?.displayTitle ?? this.pendingColumns[0]?.title ?? 'New thread';
  }

  get pageCount() {
    return Math.max(this.trail.columns.length, this.pendingColumns.length);
  }

  /** Whether the thread's pages are loaded (a discarded or unshown thread only has its column list). */
  get isLoaded() {
    return this.trail.columns.length > 0;
  }

  setDeveloperMode(value: boolean | null) {
    this.developerMode = value;
    this.trail.setDeveloperModeOverride(value);
  }

  /**
   * Lets the thread's webviews go, keeping what's needed to bring it back: its
   * columns, widths, focus and scroll positions. `stillWanted` is checked after
   * reading scroll positions, in case you came back meanwhile.
   */
  async discard(stillWanted: () => boolean) {
    if (!this.isLoaded) return;
    const current = this.snapshot;
    const columns = current.columns.map((c) => ({ ...c }));
    const pages = this.trail.columns.filter((p) => !p.isEphemeral && p.address);
    for (let i = 0; i < pages.length && i < columns.length; i++) {
      columns[i].scrollY = await pages[i].scrollY();
    }
    if (!stillWanted() || !this.isLoaded) return;
    runInAction(() => {
      this.pendingColumns = columns;
      this.pendingFocus = current.focusedIndex;
      this.trail.closeAll();
    });
  }

  /** Creates the pages. Call after the owner has hooked `trail` up. */
  restoreIfNeeded() {
    this.trail.setDeveloperModeOverride(this.developerMode);
    if (!this.pendingColumns.length) return;
    this.trail.restore(this.pendingColumns, this.pendingFocus);
    this.pendingColumns = [];
  }

  /** What to persist. A thread never shown still has its columns pending. */
  get snapshot(): { columns: ColumnSnapshot[]; focusedIndex: number } {
    if (this.pendingColumns.length) return { columns: this.pendingColumns, focusedIndex: this.pendingFocus };
    const columns: ColumnSnapshot[] = [];
    for (const page of this.trail.columns) {
      if (page.isEphemeral) continue;
      const url = page.address;
      if (!url) continue;
      columns.push({ url, title: page.displayTitle, widthFraction: this.trail.widthFraction(page) });
    }
    return { columns, focusedIndex: Math.min(this.trail.focusedIndex, Math.max(columns.length - 1, 0)) };
  }
}

class ThreadStore {
  records: ThreadRecord[] = [];
  /** Thread id → the window showing it. */
  claims: Record<string, number> = {};
  loaded = false;
  window = 0;
  private pendingSaves = new Map<string, { timer: number; thread: BrowserThread }>();

  constructor() {
    makeAutoObservable<ThreadStore, 'pendingSaves'>(this, { pendingSaves: false });
    host.on('threads.claims', (claims) => runInAction(() => (this.claims = claims ?? {})));
    host.on('threads.changed', () => void this.load());
  }

  async load() {
    const [threads, columns] = await Promise.all([
      db.query('SELECT * FROM ThreadRecord'),
      db.query('SELECT * FROM ColumnRecord ORDER BY "order"'),
    ]);
    const byThread = new Map<string, ColumnRecord[]>();
    for (const c of columns) {
      const list = byThread.get(c.threadID) ?? [];
      list.push({ order: c.order, url: c.url, title: c.title, widthFraction: c.widthFraction ?? null });
      byThread.set(c.threadID, list);
    }
    runInAction(() => {
      this.records = threads.map((t) => ({
        id: t.id,
        customTitle: t.customTitle ?? null,
        title: t.title,
        createdAt: t.createdAt,
        lastActiveAt: t.lastActiveAt,
        focusedIndex: t.focusedIndex ?? 0,
        isResolved: !!t.isResolved,
        outcome: t.outcome ?? null,
        resolvedAt: t.resolvedAt ?? null,
        developerMode: t.developerMode == null ? null : !!t.developerMode,
        columns: byThread.get(t.id) ?? [],
      }));
      this.loaded = true;
    });
  }

  get unresolvedThreads(): ThreadRecord[] {
    return this.records.filter((r) => !r.isResolved).sort((a, b) => b.lastActiveAt - a.lastActiveAt);
  }

  /** Resolved threads, most recently active first (shown in Moments). */
  get resolvedThreads(): ThreadRecord[] {
    return this.records.filter((r) => r.isResolved).sort((a, b) => b.lastActiveAt - a.lastActiveAt);
  }

  record(id: string): ThreadRecord | undefined {
    return this.records.find((r) => r.id === id);
  }

  // MARK: Saving

  /** Coalesces bursts of changes (a page load fires several) into one write. */
  scheduleSave(thread: BrowserThread) {
    const pending = this.pendingSaves.get(thread.id);
    if (pending) clearTimeout(pending.timer);
    const timer = window.setTimeout(() => this.save(thread), 400);
    this.pendingSaves.set(thread.id, { timer, thread });
  }

  /** Writes debounced saves now (the window is closing). */
  async flush() {
    const threads = [...this.pendingSaves.values()].map((p) => p.thread);
    await Promise.all(threads.map((t) => this.save(t)));
  }

  async save(thread: BrowserThread) {
    const pending = this.pendingSaves.get(thread.id);
    if (pending) clearTimeout(pending.timer);
    this.pendingSaves.delete(thread.id);
    const { columns, focusedIndex } = thread.snapshot;
    const existing = this.record(thread.id);
    // Empty threads aren't worth keeping.
    if (!columns.length && thread.customTitle == null) {
      if (existing && !existing.isResolved) await this.delete(thread.id);
      return;
    }
    const record: ThreadRecord = {
      id: thread.id,
      customTitle: thread.customTitle,
      title: thread.title,
      createdAt: thread.createdAt,
      lastActiveAt: thread.lastActiveAt,
      focusedIndex,
      isResolved: existing?.isResolved ?? false,
      outcome: existing?.outcome ?? null,
      resolvedAt: existing?.resolvedAt ?? null,
      developerMode: thread.developerMode,
      columns: columns.map((c, order) => ({ order, url: c.url, title: c.title, widthFraction: c.widthFraction })),
    };
    runInAction(() => {
      this.records = [...this.records.filter((r) => r.id !== thread.id), record];
    });
    await this.write(record);
  }

  private async write(record: ThreadRecord) {
    await db.batch([
      {
        sql: `INSERT INTO ThreadRecord (id, customTitle, title, createdAt, lastActiveAt, focusedIndex, isResolved, outcome, resolvedAt, developerMode)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET customTitle = excluded.customTitle, title = excluded.title, lastActiveAt = excluded.lastActiveAt,
                focusedIndex = excluded.focusedIndex, isResolved = excluded.isResolved, outcome = excluded.outcome,
                resolvedAt = excluded.resolvedAt, developerMode = excluded.developerMode`,
        params: [
          record.id, record.customTitle, record.title, record.createdAt, record.lastActiveAt, record.focusedIndex,
          record.isResolved ? 1 : 0, record.outcome, record.resolvedAt,
          record.developerMode == null ? null : record.developerMode ? 1 : 0,
        ],
      },
      { sql: 'DELETE FROM ColumnRecord WHERE threadID = ?', params: [record.id] },
      ...record.columns.map((c) => ({
        sql: 'INSERT INTO ColumnRecord (threadID, "order", url, title, widthFraction) VALUES (?, ?, ?, ?, ?)',
        params: [record.id, c.order, c.url, c.title, c.widthFraction],
      })),
    ]);
    host.send('threads.changed');
  }

  private async update(id: string, change: Partial<ThreadRecord>) {
    const record = this.record(id);
    if (!record) return;
    const next = { ...record, ...change };
    runInAction(() => (this.records = this.records.map((r) => (r.id === id ? next : r))));
    await this.write(next);
  }

  async resolve(thread: BrowserThread, outcome: string) {
    await this.save(thread);
    await this.update(thread.id, { isResolved: true, outcome, resolvedAt: now() });
  }

  /** Brings a resolved thread back into the Deck. */
  unresolve(id: string) {
    return this.update(id, { isResolved: false, lastActiveAt: now() });
  }

  /** Marks a thread as just used (reviving it from below the waterline). */
  touch(id: string) {
    return this.update(id, { lastActiveAt: now() });
  }

  async delete(id: string) {
    const pending = this.pendingSaves.get(id);
    if (pending) clearTimeout(pending.timer);
    this.pendingSaves.delete(id);
    runInAction(() => (this.records = this.records.filter((r) => r.id !== id)));
    await db.exec('DELETE FROM ThreadRecord WHERE id = ?', [id]);
    host.send('threads.changed');
  }

  // MARK: Which window shows which thread

  owner(id: string): number | null {
    const owner = this.claims[id];
    return owner == null ? null : owner;
  }

  async claim(id: string): Promise<boolean> {
    const ok = await host.call<boolean>('threads.claim', { thread: id });
    if (ok) runInAction(() => (this.claims = { ...this.claims, [id]: this.window }));
    return ok;
  }

  release(id: string) {
    host.send('threads.release', { thread: id });
    runInAction(() => {
      const next = { ...this.claims };
      if (next[id] === this.window) delete next[id];
      this.claims = next;
    });
  }
}

export const threadStore = new ThreadStore();

export const recordDate = (seconds: number) => new Date(seconds * 1000);
export { toSeconds };

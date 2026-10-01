// The Deck's model (ports of DeckItem.swift, DeckLayout.swift, ThumbnailStore.swift):
// threads as cards whose height is their heat, sinking below a waterline when
// left alone.

import { makeAutoObservable } from 'mobx';
import { host } from '../host/host';
import type { LiveChip } from './live';
import type { ThreadRecord } from './threads';
import { hostOf } from './page';

export type DeckArrangement = 'heat' | 'thread' | 'site';
export const ARRANGEMENT_LABELS: Record<DeckArrangement, string> = { heat: 'By heat', thread: 'By thread', site: 'By site' };

export type DeckChip = { kind: 'playing' } | { kind: 'unsaved' } | { kind: 'live'; chip: LiveChip };
export type Afloat = 'playing' | 'unsaved';

export interface DeckItem {
  id: string;
  /** The thread a click on this card switches to. */
  threadID: string;
  title: string;
  host: string;
  pageCount: number;
  /** Seconds since 1970. */
  lastActiveAt: number;
  isActive: boolean;
  chip: DeckChip | null;
  afloat: Afloat | null;
  /** 1 = just touched, falling towards 0. */
  heat: number;
  isSunk: boolean;
}

export function relativeTime(seconds: number, now = Date.now() / 1000) {
  const diff = seconds - now;
  const abs = Math.abs(diff);
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });
  if (abs < 60) return rtf.format(Math.round(diff), 'second');
  if (abs < 3600) return rtf.format(Math.round(diff / 60), 'minute');
  if (abs < 86400) return rtf.format(Math.round(diff / 3600), 'hour');
  if (abs < 86400 * 30) return rtf.format(Math.round(diff / 86400), 'day');
  if (abs < 86400 * 365) return rtf.format(Math.round(diff / (86400 * 30)), 'month');
  return rtf.format(Math.round(diff / (86400 * 365)), 'year');
}

export function footnote(item: DeckItem) {
  if (item.isActive) return item.pageCount === 1 ? "You're here" : `${item.pageCount} pages · you're here`;
  if (item.afloat === 'unsaved') return "Won't sink while unsaved";
  if (item.afloat === 'playing') return 'Playing · never sinks';
  const age = relativeTime(item.lastActiveAt);
  return item.pageCount > 1 ? `${item.pageCount} pages · ${age}` : age;
}

export interface LiveThread {
  pageCount: number;
  isPlaying: boolean;
  hasUnsaved: boolean;
  title: string;
  host: string;
  chip: LiveChip | null;
}

const afloatOf = (live?: LiveThread): Afloat | null => (live?.hasUnsaved ? 'unsaved' : live?.isPlaying ? 'playing' : null);

/** One chip per card: errors and price moves first, then unsaved input, then the rest. */
function deckChip(live?: LiveThread): DeckChip | null {
  if (!live) return null;
  if (live.chip && ['status', 'ci', 'errors', 'price'].includes(live.chip.kind)) return { kind: 'live', chip: live.chip };
  if (live.hasUnsaved) return { kind: 'unsaved' };
  if (live.chip) return { kind: 'live', chip: live.chip };
  return live.isPlaying ? { kind: 'playing' } : null;
}

export function buildDeck(options: {
  records: ThreadRecord[];
  live: Map<string, LiveThread>;
  activeID: string;
  /** Seconds, or null for never. */
  sinkAfter: number | null;
  keepActiveAfloat: boolean;
  arrangement: DeckArrangement;
  now?: number;
}): DeckItem[] {
  const { records, live, activeID, sinkAfter, keepActiveAfloat, arrangement } = options;
  const now = options.now ?? Date.now() / 1000;

  const item = (
    id: string, threadID: string, title: string, host: string, pageCount: number, lastActiveAt: number,
    chip: DeckChip | null, afloat: Afloat | null, flatHeat: boolean,
  ): DeckItem => {
    const isActive = threadID === activeID;
    const age = Math.max(0, now - lastActiveAt);
    // Half-life of a third of the sink delay: a card is at 1/8 height when it sinks.
    const halfLife = (sinkAfter ?? 9 * 86_400) / 3;
    const heat = isActive ? 1 : flatHeat ? 0.6 : Math.pow(0.5, age / halfLife);
    const isSunk = !isActive && !(keepActiveAfloat && afloat) && sinkAfter != null && age > sinkAfter;
    return { id, threadID, title, host, pageCount, lastActiveAt, isActive, chip, afloat, heat, isSunk };
  };

  if (arrangement === 'site') {
    const groups = new Map<string, { count: number; record: ThreadRecord }>();
    for (const record of records) {
      for (const column of record.columns) {
        const h = hostOf(column.url);
        if (!h) continue;
        const existing = groups.get(h);
        const newest = existing && existing.record.lastActiveAt > record.lastActiveAt ? existing.record : record;
        groups.set(h, { count: (existing?.count ?? 0) + 1, record: newest });
      }
    }
    return [...groups].map(([h, g]) => item(`site:${h}`, g.record.id, h, h, g.count, g.record.lastActiveAt, null, null, false));
  }

  const flat = arrangement === 'thread';
  const items = records.map((record) => {
    const l = live.get(record.id);
    const first = [...record.columns].sort((a, b) => a.order - b.order)[0];
    return item(
      record.id, record.id, l?.title ?? record.customTitle ?? record.title, l?.host ?? (first ? hostOf(first.url) : ''),
      l?.pageCount ?? record.columns.length, record.lastActiveAt, deckChip(l), afloatOf(l), flat,
    );
  });
  // The active thread may be brand new and not saved yet.
  const activeLive = live.get(activeID);
  if (!records.some((r) => r.id === activeID) && activeLive) {
    items.push(item(activeID, activeID, activeLive.title, activeLive.host, activeLive.pageCount, now, deckChip(activeLive), afloatOf(activeLive), false));
  }
  return items;
}

// MARK: Layout

export type DeckState = 'hidden' | 'peek' | 'open';

export interface Placement {
  /** Card centre, horizontally, relative to the window's centre. */
  x: number;
  /** Distance from the window's bottom edge to the card's bottom edge. */
  bottom: number;
  rotation: number;
  zIndex: number;
}

export const DeckMetrics = {
  margin: 12,
  peekFooterHeight: 30,
  peekPadding: 14,
  stackAllowance: 12,
  waterlineIslandHeight: 64,
};

export class DeckLayout {
  constructor(readonly state: DeckState, readonly width: number) {}

  get cardSize() {
    return this.state === 'open' ? { width: 250, height: 180 } : { width: 150, height: 108 };
  }

  /** Orders afloat items for the fan: active first, then by heat. */
  static fanOrder(items: DeckItem[]) {
    return [...items].sort((a, b) => (a.isActive !== b.isActive ? (a.isActive ? -1 : 1) : b.heat - a.heat));
  }

  peekIslandSize(count: number) {
    const row = Math.max(count - 1, 0) * this.peekSpacing(count) + this.cardSize.width;
    return {
      width: Math.max(260, row + DeckMetrics.peekPadding * 2),
      height: DeckMetrics.peekPadding + DeckMetrics.stackAllowance + this.cardSize.height + 6 + DeckMetrics.peekFooterHeight,
    };
  }

  private peekSpacing(count: number) {
    const fit = (this.width - 48 - DeckMetrics.peekPadding * 2 - this.cardSize.width) / Math.max(count - 1, 1);
    return Math.min(this.cardSize.width + 10, Math.max(28, fit));
  }

  /** `rank` 0 is the centre; 1 goes right, 2 left, 3 further right… */
  placement(rank: number, heat: number, count: number): Placement {
    const ring = Math.floor((rank + 1) / 2);
    const side = rank === 0 ? 0 : rank % 2 === 1 ? 1 : -1;
    if (this.state === 'open') {
      const rings = Math.max(1, Math.floor(count / 2));
      const spacing = Math.min(165, (this.width / 2 - this.cardSize.width / 2 - 20) / rings);
      const waterlineTop = DeckMetrics.margin + DeckMetrics.waterlineIslandHeight;
      return {
        x: side * ring * spacing,
        bottom: waterlineTop + 14 + heat * 150 - ring * 12,
        rotation: side * Math.min(12, ring * 4),
        zIndex: 100 - ring,
      };
    }
    const x = (rank - (count - 1) / 2) * this.peekSpacing(count);
    const base = DeckMetrics.margin + DeckMetrics.peekFooterHeight + 6;
    return { x, bottom: this.state === 'peek' ? base : -this.cardSize.height - 60, rotation: 0, zIndex: 100 - rank };
  }

  /** Sunk cards: a row behind the waterline island, just their tops showing. */
  sunkPlacement(index: number, count: number): Placement {
    const usable = Math.max(0, this.width - this.cardSize.width - 120);
    const step = count > 1 ? Math.min(this.cardSize.width * 0.75, usable / (count - 1)) : 0;
    const x = (-step * (count - 1)) / 2 + index * step;
    const wobble = [-6, 3, -2, 5, -4, 6][index % 6];
    const bottom =
      this.state === 'open'
        ? DeckMetrics.margin + DeckMetrics.waterlineIslandHeight - this.cardSize.height * 0.5
        : -this.cardSize.height - 60;
    return { x, bottom, rotation: wobble, zIndex: index };
  }
}

// MARK: Thumbnails

/**
 * Snapshots of each thread's focused page (Deck cards) and of saved moments, as
 * JPEGs in the data folder, shown through `data/…` URLs. `version` changes when a
 * picture is replaced, so <img> reloads it.
 */
class Thumbnails {
  versions = new Map<string, number>();
  missing = new Set<string>();

  constructor(private readonly folder: string, private readonly width: number) {
    makeAutoObservable<Thumbnails, 'folder' | 'width'>(this, { folder: false, width: false } as any);
  }

  url(id: string): string | null {
    if (this.missing.has(id) && !this.versions.has(id)) return null;
    return `data/${this.folder}/${id}.jpg?v=${this.versions.get(id) ?? 0}`;
  }

  markMissing(id: string) {
    this.missing.add(id);
  }

  async capture(page: import('./page').Page, id: string) {
    const result = await page.saveSnapshot(`${this.folder}/${id}.jpg`, this.width);
    if (result) this.bump(id);
  }

  bump(id: string) {
    this.missing.delete(id);
    this.versions.set(id, (this.versions.get(id) ?? 0) + 1);
  }

  remove(id: string) {
    this.versions.delete(id);
    this.missing.add(id);
    host.send('file.remove', { path: `${this.folder}/${id}.jpg` });
  }
}

export const threadThumbnails = new Thumbnails('thumbs', 480);
export const momentThumbnails = new Thumbnails('moments', 720);

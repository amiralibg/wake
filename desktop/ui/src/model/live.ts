// Live state and chips (ports of LiveChip.swift, LiveChipProviders.swift and
// PriceWatch.swift): one glanceable fact per page, from what its scripts report.

import { settings } from './settings';
import type { Page } from './page';

export type ChipKind = 'status' | 'ci' | 'errors' | 'price' | 'unread' | 'media' | 'changed';
export type Tone = 'accent' | 'good' | 'bad' | 'warning' | 'neutral';

export interface LiveChip {
  kind: ChipKind;
  text: string;
  /** A lucide icon name. */
  icon: string;
  tone: Tone;
  /** 0…1, for media. */
  progress?: number;
}

export interface LiveState {
  media?: { current: number; duration: number; isPlaying: boolean } | null;
  price?: { amount: number; currency: string } | null;
  contentChanged?: boolean;
  ci?: 'passed' | 'failed' | 'pending' | null;
  httpStatus?: number | null;
}

/** Merges a `{ type: 'live', … }` message. */
export function mergeLive(state: LiveState, message: any): LiveState {
  const next: LiveState = { ...state };
  if (message.media && typeof message.media === 'object') {
    const duration = Number(message.media.d) || 0;
    next.media =
      duration > 0 || message.media.playing
        ? { current: Number(message.media.t) || 0, duration, isPlaying: !!message.media.playing }
        : null;
  } else if (message.media === null) {
    next.media = null;
  }
  if (message.price && Number(message.price.amount) > 0) {
    next.price = { amount: Number(message.price.amount), currency: String(message.price.currency ?? '') };
  }
  if (typeof message.changed === 'boolean') next.contentChanged = message.changed;
  if (typeof message.ci === 'string' && ['passed', 'failed', 'pending'].includes(message.ci)) next.ci = message.ci;
  return next;
}

export function liveEqual(a: LiveState, b: LiveState) {
  return JSON.stringify(a) === JSON.stringify(b);
}

/** Unread count from a title: "(3) Inbox – Gmail", "Inbox (12)", "(99+) Chat". */
export function badgeIn(title: string): number | null {
  const match = /\((\d{1,4})\+?\)/.exec(title);
  const count = match ? Number(match[1]) : 0;
  return count > 0 ? count : null;
}

export function formatTime(seconds: number) {
  const total = Math.floor(Number.isFinite(seconds) ? seconds : 0);
  const h = Math.floor(total / 3600);
  const m = Math.floor(total / 60) % 60;
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

// MARK: Price watch

const PRICE_KEY = 'live.prices';
const PRICE_LIMIT = 300;

function priceKey(url: string) {
  try {
    const u = new URL(url);
    return u.hostname + u.pathname;
  } catch {
    return url;
  }
}

export const priceWatch = {
  firstPrice(url: string): number | null {
    const prices = settings.get<Record<string, { first: number; seen: number }>>(PRICE_KEY, {});
    return prices[priceKey(url)]?.first ?? null;
  },
  /** Records a sighting; the first one sticks. */
  observe(amount: number, url: string) {
    const prices = { ...settings.get<Record<string, { first: number; seen: number }>>(PRICE_KEY, {}) };
    const key = priceKey(url);
    if (prices[key]) return;
    const keys = Object.keys(prices);
    if (keys.length >= PRICE_LIMIT) {
      const oldest = keys.reduce((a, b) => ((prices[a].seen ?? 0) <= (prices[b].seen ?? 0) ? a : b));
      delete prices[oldest];
    }
    prices[key] = { first: amount, seen: Date.now() / 1000 };
    settings.set(PRICE_KEY, prices);
  },
  format(price: { amount: number; currency: string }) {
    if (price.currency.length === 3) {
      try {
        return new Intl.NumberFormat(undefined, { style: 'currency', currency: price.currency, maximumFractionDigits: 2, minimumFractionDigits: 0 }).format(price.amount);
      } catch {}
    }
    return new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(price.amount);
  },
};

// MARK: Providers, in priority order

type Provider = (page: Page) => LiveChip | null;

const providers: Provider[] = [
  // "404", "500": the page came back with an error.
  (page) => {
    const status = page.live.httpStatus;
    if (!status || status < 400) return null;
    return { kind: 'status', text: String(status), icon: 'triangle-alert', tone: status >= 500 ? 'bad' : 'warning' };
  },
  // CI on GitHub pull request pages.
  (page) => {
    switch (page.live.ci) {
      case 'passed': return { kind: 'ci', text: 'CI passed', icon: 'circle-check', tone: 'good' };
      case 'failed': return { kind: 'ci', text: 'CI failed', icon: 'circle-x', tone: 'bad' };
      case 'pending': return { kind: 'ci', text: 'CI running', icon: 'circle-dashed', tone: 'warning' };
      default: return null;
    }
  },
  // Console errors, in developer mode.
  (page) => {
    const count = page.devtools.errorCount;
    if (!page.isDeveloperMode || count <= 0) return null;
    return { kind: 'errors', text: `${count} error${count === 1 ? '' : 's'}`, icon: 'octagon-alert', tone: 'bad' };
  },
  // A product's price, compared with the first time you saw it.
  (page) => {
    const price = page.live.price;
    if (!price || !page.url) return null;
    const first = priceWatch.firstPrice(page.url) ?? price.amount;
    const text = priceWatch.format(price);
    if (price.amount < first - 0.005) return { kind: 'price', text: `${text} ↓`, icon: 'arrow-down', tone: 'good' };
    if (price.amount > first + 0.005) return { kind: 'price', text: `${text} ↑`, icon: 'arrow-up', tone: 'bad' };
    return { kind: 'price', text, icon: 'tag', tone: 'neutral' };
  },
  // "(3) Inbox": the unread count web apps put in their title.
  (page) => {
    const count = badgeIn(page.title);
    return count ? { kind: 'unread', text: `${count} unread`, icon: 'mail', tone: 'accent' } : null;
  },
  // Playing audio or video: time and progress.
  (page) => {
    const media = page.live.media;
    if (!media || (!media.isPlaying && media.current <= 0)) return null;
    const finite = Number.isFinite(media.duration) && media.duration > 0;
    return {
      kind: 'media',
      text: finite ? `${formatTime(media.current)} / ${formatTime(media.duration)}` : media.isPlaying ? 'Live' : 'Paused',
      icon: media.isPlaying ? 'volume-2' : 'pause',
      tone: media.isPlaying ? 'accent' : 'neutral',
      progress: finite ? Math.min(1, media.current / media.duration) : undefined,
    };
  },
  // The page's content changed while you were in another column.
  (page) => (page.live.contentChanged ? { kind: 'changed', text: 'Updated', icon: 'refresh-cw', tone: 'accent' } : null),
];

const RANK: ChipKind[] = ['status', 'ci', 'errors', 'price', 'unread', 'media', 'changed'];

export function chipsFor(page: Page): LiveChip[] {
  return providers.map((p) => p(page)).filter((c): c is LiveChip => !!c);
}

/** The most important chip across several pages (a thread). */
export function topChip(pages: Page[]): LiveChip | null {
  let best: LiveChip | null = null;
  for (const page of pages) {
    const chip = chipsFor(page)[0];
    if (chip && (!best || RANK.indexOf(chip.kind) < RANK.indexOf(best.kind))) best = chip;
  }
  return best;
}

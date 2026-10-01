// Moments' words and dates (MomentFormat, MomentStatus and MomentSearch in the Mac
// app).

import { type Moment, momentHost, rules } from '../../model/moments';

const DAY = 86_400_000;
const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const daysBetween = (a: Date, b: Date) => Math.round((startOfDay(b).getTime() - startOfDay(a).getTime()) / DAY);

/** "today", "yesterday", "saved Tuesday", "3 weeks ago", "August". */
export function savedLabel(seconds: number, now = new Date()) {
  const date = new Date(seconds * 1000);
  const days = daysBetween(date, now);
  if (days === 0) return 'today';
  if (days === 1) return 'yesterday';
  if (days < 7) return 'saved ' + date.toLocaleDateString(undefined, { weekday: 'long' });
  if (days < 14) return 'last week';
  if (days < 45) return `${Math.floor(days / 7)} weeks ago`;
  return date.toLocaleDateString(undefined, { month: 'long' });
}

/** "tomorrow", "Saturday", "Oct 3": a weekday only within the coming six days. */
export function dayLabel(seconds: number, now = new Date()) {
  const date = new Date(seconds * 1000);
  const days = daysBetween(now, date);
  if (days === 0) return 'today';
  if (days === 1) return 'tomorrow';
  return days < 7 ? date.toLocaleDateString(undefined, { weekday: 'long' }) : date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

/** Group titles: "Today", "Yesterday", "This week", "August", "August 2025". */
export function groupTitle(seconds: number, now = new Date()) {
  const date = new Date(seconds * 1000);
  const days = daysBetween(date, now);
  if (days === 0) return 'Today';
  if (days === 1) return 'Yesterday';
  const weekStart = startOfDay(new Date(now.getTime() - now.getDay() * DAY));
  if (date >= weekStart) return 'This week';
  if (date.getFullYear() === now.getFullYear()) return date.toLocaleDateString(undefined, { month: 'long' });
  return date.toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
}

/** History's day titles: "Today", "Yesterday", "Tuesday, 3 September". */
export function historyDayTitle(seconds: number, now = new Date()) {
  const date = new Date(seconds * 1000);
  const days = daysBetween(date, now);
  if (days === 0) return 'Today';
  if (days === 1) return 'Yesterday';
  return date.toLocaleDateString(undefined, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: date.getFullYear() === now.getFullYear() ? undefined : 'numeric',
  });
}

export const timeLabel = (seconds: number) => new Date(seconds * 1000).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });

export type StatusKind = 'changed' | 'resurfacing' | 'relevant' | 'fading' | 'archived';
export interface MomentStatus {
  kind: StatusKind;
  text: string;
}

/** The one thing worth knowing about a moment right now. */
export function statusOf(m: Moment, site: string | null, now = new Date()): MomentStatus | null {
  const seconds = now.getTime() / 1000;
  if (m.isArchived) return { kind: 'archived', text: 'Archived' };
  if (m.changedAt != null) return { kind: 'changed', text: 'Changed' + (m.changeSummary ? ` · ${m.changeSummary}` : '') };
  if (rules.isResurfacing(m, now)) return { kind: 'resurfacing', text: 'Resurfacing today' };
  if (rules.isFading(m, seconds)) {
    const days = rules.daysUntilArchive(m, seconds);
    return { kind: 'fading', text: `Fading · archives in ${days} day${days === 1 ? '' : 's'}` };
  }
  if (rules.isRelevant(m, site) && site) return { kind: 'relevant', text: `Relevant here · ${site}` };
  if (m.resurfaceAt != null && m.resurfaceAt > seconds) return { kind: 'resurfacing', text: `Resurfaces ${dayLabel(m.resurfaceAt, now)}` };
  return null;
}

// MARK: Search

export function searchTokens(query: string): string[] {
  return query
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((t) => t.length > 1 || /^\p{N}/u.test(t));
}

/** 0 when nothing matches; words in what you wrote yourself count most. */
export function searchScore(m: Moment, tokens: string[]): number {
  if (!tokens.length) return 0;
  const fields: [string, number][] = [
    [m.title.toLowerCase(), 4],
    [(m.note ?? '').toLowerCase(), 5],
    [(m.selectedText ?? '').toLowerCase(), 4],
    [momentHost(m).toLowerCase(), 3],
    [m.url.toLowerCase(), 1],
    [m.contentText.toLowerCase(), 1],
  ];
  let score = 0;
  let matched = 0;
  for (const token of tokens) {
    const best = fields.reduce((b, [text, weight]) => (text.includes(token) ? Math.max(b, weight) : b), 0);
    if (best > 0) matched++;
    score += best;
  }
  if (!matched) return 0;
  // All words found beats a few strong ones.
  return score + (matched === tokens.length ? 10 : 0);
}

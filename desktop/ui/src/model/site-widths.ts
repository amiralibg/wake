// Minimum column widths by address pattern (port of SiteWidthRules.swift).

import { settings } from './settings';
import { canHaveRule, normalizePattern, patternMatches, patternSpecificity } from './site-pattern';

export interface SiteWidthRule {
  id: string;
  pattern: string;
  minWidth: number;
}

const KEY = 'browsing.siteWidths';
const newID = () => (crypto.randomUUID ? crypto.randomUUID() : `rule-${Date.now()}-${Math.random()}`);

export const siteWidths = {
  get rules(): SiteWidthRule[] {
    return settings.get<SiteWidthRule[]>(KEY, []);
  },

  minimumWidth(url: string | null | undefined): number | null {
    if (!url) return null;
    let best: SiteWidthRule | null = null;
    for (const rule of this.rules) {
      if (rule.minWidth <= 0 || !rule.pattern || !patternMatches(rule.pattern, url)) continue;
      if (!best || patternSpecificity(rule.pattern) > patternSpecificity(best.pattern)) best = rule;
    }
    return best?.minWidth ?? null;
  },

  /** Whole-site rule for the address, replacing what's there. */
  remember(width: number, url: string) {
    if (!canHaveRule(url)) return;
    const pattern = normalizePattern(new URL(url).host);
    const kept = this.rules.filter((r) => normalizePattern(r.pattern) !== pattern);
    settings.set(KEY, [...kept, { id: newID(), pattern, minWidth: Math.round(width) }]);
  },

  /** Removes every rule that applies to the address. */
  forget(url: string) {
    settings.set(KEY, this.rules.filter((r) => !patternMatches(r.pattern, url)));
  },

  add() {
    settings.set(KEY, [...this.rules, { id: newID(), pattern: '', minWidth: 800 }]);
  },

  update(id: string, change: Partial<SiteWidthRule>) {
    settings.set(KEY, this.rules.map((r) => (r.id === id ? { ...r, ...change } : r)));
  },

  remove(id: string) {
    settings.set(KEY, this.rules.filter((r) => r.id !== id));
  },
};

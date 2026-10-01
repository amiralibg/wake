// Preferences: the keys of shared/schema/settings.json, kept by the host in
// settings.json and shared by every window (a change in one reaches all).

import { makeAutoObservable } from 'mobx';
import { host } from '../host/host';
import { SEARCH_ENGINES, type SearchEngineID, searchURL, isValidTemplate } from './search';

export type Theme = 'light' | 'dark' | 'auto';
export type Accent = 'blue' | 'purple' | 'pink' | 'orange' | 'green' | 'teal' | 'graphite';
export type Glass = 'subtle' | 'balanced' | 'clear';
export type PageWidth = 'narrow' | 'balanced' | 'wide';
export type SinkAfter = 'threeDays' | 'sevenDays' | 'fourteenDays' | 'never';
export type Editor = 'cursor' | 'vscode' | 'zed' | 'xcode';

export const ACCENTS: Record<Accent, string> = {
  blue: '#007AFF',
  purple: '#AF52DE',
  pink: '#FF2D55',
  orange: '#FF9500',
  green: '#34C759',
  teal: '#30B0C7',
  graphite: '#8E8E93',
};

export const GAP_PRESETS: { label: string; value: number }[] = [
  { label: 'None', value: 0 },
  { label: 'Tight', value: 8 },
  { label: 'Balanced', value: 14 },
  { label: 'Roomy', value: 24 },
];

export const CORNER_PRESETS: { label: string; value: number }[] = [
  { label: 'Square', value: 0 },
  { label: 'Soft', value: 8 },
  { label: 'Round', value: 12 },
  { label: 'Pill', value: 18 },
];

export const COLUMNS_PER_SCREEN: Record<PageWidth, number> = { narrow: 3, balanced: 2, wide: 1.5 };

export const SINK_AFTER_DAYS: Record<SinkAfter, number | null> = {
  threeDays: 3,
  sevenDays: 7,
  fourteenDays: 14,
  never: null,
};

class Settings {
  values: Record<string, any> = {};

  constructor() {
    makeAutoObservable(this);
    host.on('settings.changed', ({ key, value }) => this.apply(key, value));
  }

  load(values: Record<string, unknown>) {
    this.values = { ...values };
  }

  private apply(key: string, value: unknown) {
    this.values[key] = value;
  }

  get<T = any>(key: string, fallback?: T): T {
    const value = this.values[key];
    return (value === undefined || value === null ? fallback : value) as T;
  }

  set(key: string, value: unknown) {
    this.values[key] = value;
    host.send('settings.set', { key, value });
  }

  // Appearance
  get theme(): Theme { return this.get('appearance.theme', 'auto'); }
  get accent(): Accent { return this.get('appearance.accent', 'blue'); }
  get accentColor() { return ACCENTS[this.accent] ?? ACCENTS.blue; }
  get glass(): Glass { return this.get('appearance.glass', 'balanced'); }
  get gap(): number { return this.get('appearance.gap', 14); }
  get cornerRadius(): number { return this.get('appearance.cornerRadius', 12); }
  get pageWidth(): PageWidth { return this.get('appearance.pageWidth', 'balanced'); }
  get columnsPerScreen() { return COLUMNS_PER_SCREEN[this.pageWidth] ?? 2; }

  // Browsing
  get linksOpenInNewColumn(): boolean { return this.get('browsing.linksInNewColumn', true); }
  get restoresLastThread(): boolean { return this.get('browsing.restoreThread', true); }
  get capsuleHidesAtEdge(): boolean { return this.get('browsing.capsuleHides', false); }
  get shiftScrollMovesColumns(): boolean { return this.get('browsing.shiftScrollColumns', true); }
  get columnModeKeyEnabled(): boolean { return this.get('browsing.columnModeKey', true); }

  // Search
  get searchEngine(): SearchEngineID { return this.get('search.engine', 'duckDuckGo'); }
  get customSearchTemplate(): string { return this.get('search.customTemplate', ''); }
  get showsSearchSuggestions(): boolean { return this.get('search.suggestions', true); }
  get braveAPIKey(): string { return this.get('search.braveKey', ''); }

  /** A custom engine without a valid template falls back to DuckDuckGo. */
  get effectiveEngine(): SearchEngineID {
    return this.searchEngine === 'custom' && !isValidTemplate(this.customSearchTemplate) ? 'duckDuckGo' : this.searchEngine;
  }
  get searchTemplate(): string {
    return this.effectiveEngine === 'custom' ? this.customSearchTemplate.trim() : SEARCH_ENGINES[this.effectiveEngine].template;
  }
  /** Shown in the palette: "Search Google for …". */
  get searchName(): string {
    if (this.effectiveEngine !== 'custom') return SEARCH_ENGINES[this.effectiveEngine].name;
    try {
      return new URL(this.searchTemplate.replace('%s', 'x')).hostname.replace(/^www\./, '');
    } catch {
      return 'the web';
    }
  }
  get searchHost(): string {
    try {
      return new URL(this.searchTemplate.replace('%s', '')).hostname;
    } catch {
      return 'duckduckgo.com';
    }
  }
  searchURL(query: string): string {
    return searchURL(this.searchTemplate, query) ?? searchURL(SEARCH_ENGINES.duckDuckGo.template, query)!;
  }

  // Deck
  get sinkAfter(): SinkAfter { return this.get('deck.sinkAfter', 'sevenDays'); }
  get keepActiveAfloat(): boolean { return this.get('deck.keepActiveAfloat', true); }
  get deckPeeksFromEdge(): boolean { return this.get('deck.peekFromEdge', true); }

  // Developer
  get editor(): Editor { return this.get('developer.editor', 'cursor'); }
  get autoEnableForLocalhost(): boolean { return this.get('developer.autoLocalhost', true); }
  get scansPorts(): boolean { return this.get('developer.scanPorts', true); }
  get webInspectorEnabled(): boolean { return this.get('developer.webInspector', true); }
}

export const settings = new Settings();

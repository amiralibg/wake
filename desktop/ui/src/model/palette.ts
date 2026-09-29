// The palette: address bar, search and results in one place (port of
// PaletteModel.swift and SearchService.swift).
//
// Limitation (as on the Mac): there's no free, keyless web-search API.
// Suggestions come from the chosen engine's public OpenSearch endpoint; results
// inside the palette need a Brave Search API key (Settings ▸ Search).

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { settings } from './settings';
import { SEARCH_ENGINES, urlFromInput, searchURL, parseSuggestions } from './search';

export interface SearchResult {
  url: string;
  title: string;
  snippet: string;
}

export interface RecentPage {
  url: string;
  title: string;
  visitedAt: number;
}

export type PaletteItem =
  | { kind: 'open'; url: string }
  | { kind: 'result'; result: SearchResult }
  | { kind: 'suggestion'; text: string }
  | { kind: 'recent'; page: RecentPage }
  | { kind: 'searchOnWeb'; query: string };

export function itemID(item: PaletteItem): string {
  switch (item.kind) {
    case 'open': return `open:${item.url}`;
    case 'result': return `result:${item.result.url}`;
    case 'suggestion': return `suggest:${item.text}`;
    case 'recent': return `recent:${item.page.url}`;
    case 'searchOnWeb': return `web:${item.query}`;
  }
}

export interface PaletteSection {
  title: string | null;
  items: PaletteItem[];
}

export type PaletteTarget = 'newColumn' | 'currentColumn';

const stripTags = (text: string) =>
  text.replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&#x27;/g, "'").replace(/&quot;/g, '"');

async function fetchSuggestions(query: string): Promise<string[]> {
  const url = searchURL(SEARCH_ENGINES[settings.effectiveEngine].suggestions, query);
  if (!url) return [];
  const response = await host.call<{ status: number; text: string }>('http.fetch', { url, timeoutMs: 4000 });
  return response.status === 200 ? parseSuggestions(response.text, query) : [];
}

async function fetchResults(query: string, key: string): Promise<SearchResult[]> {
  if (!key) return [];
  const url = `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(query)}&count=8`;
  const response = await host.call<{ status: number; text: string }>('http.fetch', {
    url,
    headers: { Accept: 'application/json', 'X-Subscription-Token': key },
    timeoutMs: 6000,
  });
  if (response.status !== 200) return [];
  const json = JSON.parse(response.text);
  return (json?.web?.results ?? []).map((r: any) => ({
    url: r.url,
    title: stripTags(r.title ?? ''),
    snippet: stripTags(r.description ?? ''),
  }));
}

export class PaletteModel {
  target: PaletteTarget = 'newColumn';
  /** In the Deck the cards already show what's recent, so the list waits for typing. */
  showsRecentsWhenEmpty = true;
  query = '';
  selection = 0;
  results: SearchResult[] = [];
  suggestions: string[] = [];
  isSearching = false;
  /** Supplied by the browser. */
  recents: () => RecentPage[] = () => [];
  private timer = 0;
  private generation = 0;

  constructor() {
    makeAutoObservable<PaletteModel, 'timer' | 'generation'>(this, { recents: false, timer: false, generation: false });
  }

  get trimmedQuery() {
    return this.query.trim();
  }

  setQuery(query: string) {
    if (query === this.query) return;
    this.query = query;
    this.refresh();
  }

  get sections(): PaletteSection[] {
    const query = this.trimmedQuery;
    const lower = query.toLowerCase();
    const matching = this.recents()
      .filter((r) => !query || r.title.toLowerCase().includes(lower) || r.url.toLowerCase().includes(lower))
      .slice(0, query ? 3 : 8)
      .map((page): PaletteItem => ({ kind: 'recent', page }));

    if (!query) {
      if (!this.showsRecentsWhenEmpty || !matching.length) return [];
      return [{ title: 'Recent', items: matching }];
    }
    const sections: PaletteSection[] = [];
    const address = urlFromInput(query);
    if (address) sections.push({ title: null, items: [{ kind: 'open', url: address }] });
    // ↩ on typed words searches, as in every browser's address bar.
    else if (!this.results.length) sections.push({ title: null, items: [{ kind: 'searchOnWeb', query }] });
    if (matching.length) sections.push({ title: 'Recent', items: matching });
    if (this.results.length) sections.push({ title: 'Top results', items: this.results.map((result) => ({ kind: 'result', result })) });
    if (this.suggestions.length) {
      sections.push({ title: 'Refine', items: this.suggestions.slice(0, 4).map((text) => ({ kind: 'suggestion', text })) });
    }
    if (address || this.results.length) sections.push({ title: null, items: [{ kind: 'searchOnWeb', query }] });
    return sections;
  }

  get items(): PaletteItem[] {
    return this.sections.flatMap((s) => s.items);
  }

  get selectedItem(): PaletteItem | null {
    const items = this.items;
    return items[this.selection] ?? items[0] ?? null;
  }

  moveSelection(delta: number) {
    const count = this.items.length;
    if (!count) return;
    this.selection = (this.selection + delta + count) % count;
  }

  select(index: number) {
    this.selection = index;
  }

  reset() {
    clearTimeout(this.timer);
    this.generation++;
    this.query = '';
    this.results = [];
    this.suggestions = [];
    this.selection = 0;
    this.isSearching = false;
  }

  private refresh() {
    clearTimeout(this.timer);
    const generation = ++this.generation;
    this.selection = 0;
    const query = this.trimmedQuery;
    const key = settings.braveAPIKey;
    if (!query || urlFromInput(query) || (!settings.showsSearchSuggestions && !key)) {
      this.results = [];
      this.suggestions = [];
      this.isSearching = false;
      return;
    }
    this.isSearching = true;
    const wantsSuggestions = settings.showsSearchSuggestions;
    this.timer = window.setTimeout(async () => {
      const [suggestions, results] = await Promise.all([
        wantsSuggestions ? fetchSuggestions(query).catch(() => []) : Promise.resolve([]),
        fetchResults(query, key).catch(() => []),
      ]);
      if (generation !== this.generation) return;
      runInAction(() => {
        this.suggestions = suggestions;
        this.results = results;
        this.isSearching = false;
      });
    }, 180);
  }
}

// Import from another browser (BrowserImporter.swift). The host reads the other
// browser's files; the UI merges: history and searches into the database,
// cookies into Wake's jar, localStorage through a hidden page that loads each
// origin from a local blank document.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { history } from './history';
import { Page } from './page';
import { isValidTemplate, matchSearch } from './search';
import { settings } from './settings';

export interface BrowserProfile {
  id: string;
  browser: string;
  profile: string | null;
  title: string;
  engine: 'chromium' | 'firefox';
}

export interface ImportOptions {
  history: boolean;
  searches: boolean;
  cookies: boolean;
  siteData: boolean;
}

export interface ImportReport {
  source: string;
  options: ImportOptions;
  pages: number;
  searches: number;
  cookies: number;
  sites: number;
  notes: string[];
}

export type ImportPhase = { kind: 'idle' } | { kind: 'running'; step: string } | { kind: 'finished'; report: ImportReport };

interface ReadResult {
  source: string;
  visits: { url: string; title: string; visitCount: number; lastVisit: number }[];
  searches: { query: string; url: string; date: number }[];
  cookies: Record<string, unknown>[];
  sites: Record<string, [string, string][]>;
  notes: string[];
}

export class BrowserImporter {
  profiles: BrowserProfile[] = [];
  selection: string | null = null;
  options: ImportOptions = { history: true, searches: true, cookies: true, siteData: true };
  phase: ImportPhase = { kind: 'idle' };

  constructor() {
    makeAutoObservable(this);
  }

  get selected(): BrowserProfile | null {
    return this.profiles.find((p) => p.id === this.selection) ?? null;
  }

  get isIdle() {
    return this.phase.kind === 'idle';
  }

  get canStart() {
    const o = this.options;
    return this.isIdle && !!this.selected && (o.history || o.searches || o.cookies || o.siteData);
  }

  /** Browser names in display order, each once. */
  get browsers(): string[] {
    return [...new Set(this.profiles.map((p) => p.browser))];
  }

  profilesOf(browser: string) {
    return this.profiles.filter((p) => p.browser === browser);
  }

  selectBrowser(browser: string) {
    if (!this.isIdle || this.selected?.browser === browser) return;
    this.selection = this.profilesOf(browser)[0]?.id ?? null;
  }

  setOption(key: keyof ImportOptions, value: boolean) {
    this.options = { ...this.options, [key]: value };
  }

  async refresh() {
    const found = await host.call<BrowserProfile[]>('import.profiles').catch(() => []);
    runInAction(() => {
      this.profiles = found;
      if (!this.selected) this.selection = found[0]?.id ?? null;
    });
  }

  reset() {
    this.phase = { kind: 'idle' };
  }

  private step(text: string) {
    this.phase = { kind: 'running', step: text };
  }

  async start() {
    const profile = this.selected;
    if (!this.canStart || !profile) return;
    const options = { ...this.options };
    const source = profile.browser;
    const report: ImportReport = { source, options, pages: 0, searches: 0, cookies: 0, sites: 0, notes: [] };
    this.step(`Reading ${source}…`);
    const off = host.on('import.progress', (p: { text: string }) => runInAction(() => this.step(p.text)));
    let data: ReadResult;
    try {
      data = await host.call<ReadResult>('import.read', { id: profile.id, ...options });
    } catch (error) {
      off();
      report.notes.push(String(error));
      runInAction(() => (this.phase = { kind: 'finished', report }));
      return;
    } finally {
      off();
    }
    report.notes.push(...data.notes.filter((n) => !n.startsWith('IndexedDB')));

    if (options.history) {
      runInAction(() => this.step(`Adding ${data.visits.length.toLocaleString()} pages…`));
      report.pages = await history.importVisits(data.visits, source);
    }
    if (options.searches) {
      runInAction(() => this.step('Finding searches…'));
      report.searches = await history.importSearches(searchesFrom(data), source);
    }
    // The site-data writer page doubles as the page cookies.add needs.
    const writer = options.cookies || options.siteData ? new Page() : null;
    try {
      if (options.cookies && data.cookies.length) {
        runInAction(() => this.step(`Adding ${data.cookies.length.toLocaleString()} cookies…`));
        report.cookies = await host.call<number>('cookies.add', { cookies: data.cookies }).catch((e) => {
          report.notes.push(String(e));
          return 0;
        });
      }
      if (options.siteData && writer) {
        const sites = Object.entries(data.sites);
        for (const [index, [origin, items]] of sites.entries()) {
          runInAction(() => this.step(`Site data ${index + 1} of ${sites.length}…`));
          if ((await writeLocalStorage(writer, origin, items)) > 0) report.sites++;
        }
        report.notes.push("IndexedDB, caches and service workers can't move between browser engines; sites rebuild them as you use them.");
      }
    } finally {
      writer?.close();
    }
    runInAction(() => (this.phase = { kind: 'finished', report }));
  }
}

/** Chromium's own search terms, plus searches recognised in the visited URLs. */
function searchesFrom(data: ReadResult) {
  const custom = settings.searchEngine === 'custom' && isValidTemplate(settings.customSearchTemplate) ? settings.customSearchTemplate : null;
  const out: { query: string; engine: string; url: string; date: number }[] = [];
  for (const s of data.searches) {
    if (!s.query) continue;
    out.push({ query: s.query, engine: matchSearch(s.url, custom)?.engine ?? engineName(s.url), url: s.url, date: s.date });
  }
  for (const v of data.visits) {
    const match = matchSearch(v.url, custom);
    if (match) out.push({ query: match.query, engine: match.engine, url: v.url, date: v.lastVisit });
  }
  return out;
}

function engineName(url: string) {
  try {
    const hostname = new URL(url).hostname;
    return hostname.startsWith('www.') ? hostname.slice(4) : hostname || 'Search';
  } catch {
    return 'Search';
  }
}

/** Loads `origin` from a local blank document, then adds the keys it doesn't have. */
function writeLocalStorage(page: Page, origin: string, items: [string, string][]): Promise<number> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      page.onDidFinish = undefined;
      resolve(0);
    }, 8000);
    page.onDidFinish = () => {
      page.onDidFinish = undefined;
      clearTimeout(timer);
      page
        .run<number>('async-local-storage-write', { items })
        .then((n) => resolve(typeof n === 'number' ? n : 0))
        .catch(() => resolve(0));
    };
    host.send('page.loadAsOrigin', { page: page.id, url: origin + '/' });
  });
}

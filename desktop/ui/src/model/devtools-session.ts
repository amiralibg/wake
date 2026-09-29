// Everything the DevTools column knows about one inspected page beyond the
// developer-mode log (port of DevToolsSession.swift): the DOM tree and selection,
// resource timing, storage, performance and audits, sources, and the page
// overrides from the Tools menu. The page-side half is shared/scripts/devtools.js,
// reached through the host's `page.devtools` and `page.devtoolsRun` commands.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import type { Page } from './page';

export type Tab = 'elements' | 'console' | 'network' | 'sources' | 'storage' | 'performance';
export const TABS: Tab[] = ['elements', 'console', 'network', 'sources', 'storage', 'performance'];

export interface DOMNode {
  id: number;
  type: number;
  tag: string | null;
  attributes: { name: string; value: string }[];
  text: string | null;
  childCount: number;
}

export const isElement = (n: DOMNode) => n.type === 1;
export const isExpandable = (n: DOMNode) => n.childCount > 0;
export function nodeLabel(n: DOMNode) {
  if (!n.tag) return n.text ?? '';
  const id = n.attributes.find((a) => a.name === 'id');
  const classes = n.attributes.find((a) => a.name === 'class')?.value.split(/\s+/).filter(Boolean).slice(0, 2).map((c) => `.${c}`).join('') ?? '';
  return n.tag + (id ? `#${id.value}` : '') + classes;
}

function parseNode(any: any): DOMNode | null {
  if (!any || typeof any.id !== 'number') return null;
  return {
    id: any.id,
    type: any.type ?? 1,
    tag: any.tag ?? null,
    attributes: (Array.isArray(any.attrs) ? any.attrs : [])
      .filter((p: any) => Array.isArray(p) && p.length === 2 && typeof p[0] === 'string')
      .map((p: any) => ({ name: p[0], value: String(p[1] ?? '') })),
    text: any.text ?? null,
    childCount: any.childCount ?? 0,
  };
}

export interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
  margin: number[];
  border: number[];
  padding: number[];
  position: string;
  display: string;
  boxSizing: string;
}

export interface Rule {
  selector: string;
  declarations: [string, string][];
  source: string;
  media: string | null;
}

export interface ElementDetails {
  id: number;
  path: number[];
  node: DOMNode | null;
  selector: string;
  box: Box | null;
  computed: [string, string][];
  inlineStyle: string;
  rules: Rule[];
  isHidden: boolean;
  htmlLength: number;
}

export interface TreeRow {
  node: DOMNode;
  depth: number;
  isClosing: boolean;
  key: string;
}

export interface Resource {
  id: number;
  url: string;
  type: string;
  start: number;
  duration: number;
  transferSize: number;
  encodedSize: number;
  decodedSize: number;
  protocolName: string;
  status: number;
  blocked: number;
  dns: number;
  connect: number;
  tls: number;
  wait: number;
  download: number;
}

export const isCached = (r: Resource) => r.transferSize === 0 && r.decodedSize > 0;

export interface StorageItem {
  key: string;
  value: string;
  length: number;
}

export interface Cookie {
  name: string;
  value: string;
  domain: string;
  path: string;
  secure: boolean;
  httpOnly: boolean;
  sameSite: string | null;
  expires: number | null;
}

export interface AsyncStorage {
  databases: { name: string; version: number }[];
  caches: { name: string; count: number }[];
  workers: { scope: string; script: string; state: string }[];
}

export interface Metrics {
  ttfb: number | null;
  domInteractive: number | null;
  dcl: number | null;
  load: number | null;
  fcp: number | null;
  lcp: number | null;
  cls: number | null;
  inp: number | null;
  support: Record<string, boolean>;
  requests: number;
  transfer: number;
  decoded: number;
  documentTransfer: number;
  protocolName: string;
  navigationType: string;
  byType: { type: string; count: number; transfer: number; decoded: number }[];
  domNodes: number;
  domDepth: number;
  scripts: number;
  styleSheets: number;
  images: number;
  iframes: number;
  devicePixelRatio: number;
  viewport: string;
}

export interface Audit {
  id: string;
  title: string;
  state: 'pass' | 'warn' | 'fail';
  detail: string;
  count: number;
}

export interface Source {
  kind: 'script' | 'style';
  url: string | null;
  index: number;
  isModule: boolean;
  inlineNumber: number;
  id: string;
}

export function sourceName(s: Source) {
  if (!s.url) return s.kind === 'script' ? `Inline script ${s.inlineNumber}` : `Inline style ${s.inlineNumber}`;
  try {
    const u = new URL(s.url);
    const last = u.pathname.split('/').pop();
    return last || u.hostname;
  } catch {
    return s.url;
  }
}

export function sourceGroup(s: Source) {
  if (!s.url) return 'Inline';
  try {
    return new URL(s.url).hostname;
  } catch {
    return 'Other';
  }
}

export type ColorScheme = 'system' | 'light' | 'dark';

export const USER_AGENTS: { id: string; title: string; value: string }[] = [
  { id: 'safariMac', title: 'Safari — macOS', value: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15' },
  { id: 'safariiPhone', title: 'Safari — iPhone', value: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1' },
  { id: 'safariiPad', title: 'Safari — iPad', value: 'Mozilla/5.0 (iPad; CPU OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1' },
  { id: 'chromeMac', title: 'Chrome — macOS', value: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36' },
  { id: 'chromeWindows', title: 'Chrome — Windows', value: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36' },
  { id: 'chromeAndroid', title: 'Chrome — Android', value: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36' },
  { id: 'firefoxLinux', title: 'Firefox — Linux', value: 'Mozilla/5.0 (X11; Linux x86_64; rv:142.0) Gecko/20100101 Firefox/142.0' },
  { id: 'edgeWindows', title: 'Edge — Windows', value: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0' },
];

const n = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) ? value : 0);
const opt = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) ? value : null);

const sessions = new WeakMap<Page, DevToolsSession>();

/** The page's session, made on first use: most pages are never inspected. */
export function inspector(page: Page): DevToolsSession {
  let session = sessions.get(page);
  if (!session) {
    session = new DevToolsSession(page);
    sessions.set(page, session);
  }
  return session;
}

export class DevToolsSession {
  documentLoads = 0;

  roots: DOMNode[] = [];
  children = new Map<number, DOMNode[]>();
  expanded = new Set<number>();
  selectedID: number | null = null;
  details: ElementDetails | null = null;
  isPicking = false;
  hoveredID: number | null = null;
  treeVersion = 0;
  searchMatches: number[] = [];
  searchIndex = 0;

  history: string[] = [];

  resources: Resource[] = [];
  private resourceCursor = 0;

  localItems: StorageItem[] = [];
  sessionItems: StorageItem[] = [];
  cookies: Cookie[] = [];
  asyncStorage: AsyncStorage = { databases: [], caches: [], workers: [] };
  blockedDatabase: string | null = null;

  metrics: Metrics | null = null;
  audits: Audit[] = [];
  fpsSamples: number[] = [];

  sources: Source[] = [];

  colorScheme: ColorScheme = 'system';
  userAgent: string | null = null;
  stylesDisabled = false;
  outlinesShown = false;
  designMode = false;

  constructor(readonly page: Page) {
    makeAutoObservable<DevToolsSession, 'resourceCursor'>(this, { page: false, resourceCursor: false });
    page.onDevToolsMessage = (message) => this.receive(message);
    page.onDocument = (phase) => (phase === 'committed' ? this.documentChanged() : this.documentFinished());
  }

  get tab(): Tab {
    return (this.page.devtoolsTab as Tab) || 'console';
  }

  setTab(tab: Tab) {
    this.page.devtoolsTab = tab;
  }

  // MARK: Evaluation

  /** Runs `expression` against `__wakeDT` in the page's world. */
  async run<T = any>(expression: string): Promise<T | null> {
    if (this.page.isClosed) return null;
    try {
      return await host.call<T>('page.devtools', { page: this.page.id, expr: expression });
    } catch {
      return null;
    }
  }

  async runScript<T = any>(script: string, params: Record<string, unknown> = {}, world: 'wake' | 'page' = 'page'): Promise<T | null> {
    if (this.page.isClosed) return null;
    try {
      return await host.call<T>('page.devtoolsRun', { page: this.page.id, script, params, world });
    } catch {
      return null;
    }
  }

  documentFinished() {
    this.documentLoads++;
  }

  /** A new document: node ids and timings belong to the old one. */
  documentChanged() {
    this.roots = [];
    this.children = new Map();
    this.expanded = new Set();
    this.selectedID = null;
    this.details = null;
    this.hoveredID = null;
    this.isPicking = false;
    this.resources = [];
    this.resourceCursor = 0;
    this.metrics = null;
    this.audits = [];
    this.fpsSamples = [];
    this.localItems = [];
    this.sessionItems = [];
    this.asyncStorage = { databases: [], caches: [], workers: [] };
    this.blockedDatabase = null;
    this.sources = [];
    this.stylesDisabled = false;
    this.outlinesShown = false;
    this.designMode = false;
    this.treeVersion++;
  }

  receive(message: any) {
    switch (message?.type) {
      case 'picked': {
        this.isPicking = false;
        this.setWakePickFlag(false);
        if (typeof message.id !== 'number') return;
        const path = (Array.isArray(message.path) ? message.path : []).filter((x: unknown) => typeof x === 'number');
        void this.reveal(message.id, path);
        this.setTab('elements');
        break;
      }
      case 'pickEnd':
        this.isPicking = false;
        this.setWakePickFlag(false);
        break;
    }
  }

  // MARK: Elements

  async loadDocument() {
    const result = await this.run<any>('__wakeDT.document()');
    if (!result) return;
    runInAction(() => {
      this.roots = (result.nodes ?? []).map(parseNode).filter(Boolean);
      this.children = new Map();
      this.treeVersion++;
    });
    // Like Safari: <html> and <body> open, everything else closed.
    const html = this.roots.find((r) => r.tag === 'html');
    if (html) {
      await this.expand(html.id);
      const body = this.children.get(html.id)?.find((c) => c.tag === 'body');
      if (body) await this.expand(body.id);
      if (this.selectedID == null && body) await this.select(body.id, false);
    }
  }

  /** Reloads what's open without losing the selection. */
  async refreshTree() {
    const open = [...this.expanded];
    const selected = this.selectedID;
    const result = await this.run<any>('__wakeDT.document()');
    if (!result) return;
    runInAction(() => {
      this.roots = (result.nodes ?? []).map(parseNode).filter(Boolean);
      this.children = new Map();
    });
    for (const id of open) await this.loadChildren(id);
    runInAction(() => (this.expanded = new Set(open.filter((id) => this.children.has(id)))));
    if (selected != null) await this.select(selected, false);
  }

  async loadChildren(id: number) {
    const result = await this.run<any[]>(`__wakeDT.children(${id})`);
    if (!Array.isArray(result)) return;
    runInAction(() => {
      const next = new Map(this.children);
      next.set(id, result.map(parseNode).filter(Boolean) as DOMNode[]);
      this.children = next;
    });
  }

  async expand(id: number) {
    if (!this.children.has(id)) await this.loadChildren(id);
    runInAction(() => this.expanded.add(id));
  }

  collapse(id: number) {
    this.expanded.delete(id);
  }

  async toggle(id: number, recursive = false) {
    if (this.expanded.has(id)) {
      this.expanded.delete(id);
      return;
    }
    await this.expand(id);
    if (!recursive) return;
    for (const child of this.children.get(id) ?? []) if (isExpandable(child)) await this.toggle(child.id, true);
  }

  /** Selects at once (so key repeats step from the new row), then loads details. */
  choose(id: number) {
    this.selectedID = id;
    void this.select(id);
  }

  async select(id: number, highlight = true) {
    this.selectedID = id;
    const result = await this.run<any>(`__wakeDT.details(${id})`);
    // Arrow keys fire faster than details arrive; drop answers for rows already left.
    if (this.selectedID !== id) return;
    runInAction(() => (this.details = result ? parseDetails(result, id) : null));
    if (highlight) await this.run(`__wakeDT.highlight(${id})`);
  }

  async reveal(id: number, path: number[]) {
    if (!this.roots.length) await this.loadDocument();
    for (const ancestor of path.slice(0, -1)) await this.expand(ancestor);
    await this.select(id, false);
  }

  hover(id: number | null) {
    if (this.hoveredID === id) return;
    this.hoveredID = id;
    void this.run(id != null ? `__wakeDT.highlight(${id})` : '__wakeDT.unhighlight()');
  }

  setPicking(on: boolean) {
    this.isPicking = on;
    this.setWakePickFlag(on);
    void this.run(`__wakeDT.pick(${on})`);
    if (on) this.page.focus();
  }

  /** Wake's link interceptor checks its own `__wakePick`, so a pick isn't also a link click. */
  private setWakePickFlag(on: boolean) {
    this.page.exec(`window.__wakePick = ${on};`);
  }

  async search(query: string) {
    const q = query.trim();
    if (!q) {
      this.searchMatches = [];
      return;
    }
    const result = await this.run<any[]>(`__wakeDT.search(${JSON.stringify(q)})`);
    if (!Array.isArray(result)) {
      runInAction(() => (this.searchMatches = []));
      return;
    }
    runInAction(() => {
      this.searchMatches = result.map((r) => r.id).filter((x) => typeof x === 'number');
      this.searchIndex = 0;
    });
    const first = result[0];
    if (first && typeof first.id === 'number') {
      await this.reveal(first.id, first.path ?? []);
      await this.run(`__wakeDT.scrollTo(${first.id})`);
    }
  }

  async nextMatch(delta: number) {
    if (!this.searchMatches.length) return;
    this.searchIndex = (this.searchIndex + delta + this.searchMatches.length) % this.searchMatches.length;
    const id = this.searchMatches[this.searchIndex];
    const path = (await this.run<number[]>(`__wakeDT.path(${id})`)) ?? [];
    await this.reveal(id, path);
    await this.run(`__wakeDT.scrollTo(${id})`);
  }

  private async edit(expression: string, id: number) {
    await this.run(expression);
    const parent = this.parentID(id);
    if (parent != null) await this.loadChildren(parent);
    if (this.selectedID === id) await this.select(id, false);
  }

  setAttribute(name: string, value: string, id: number) {
    return this.edit(`__wakeDT.setAttribute(${id}, ${JSON.stringify(name)}, ${JSON.stringify(value)})`, id);
  }

  removeAttribute(name: string, id: number) {
    return this.edit(`__wakeDT.removeAttribute(${id}, ${JSON.stringify(name)})`, id);
  }

  setInlineStyle(css: string, id: number) {
    return this.edit(`__wakeDT.setStyle(${id}, ${JSON.stringify(css)})`, id);
  }

  async remove(id: number) {
    const parent = this.parentID(id);
    // Like Safari: the next sibling takes the selection (else the previous, else the parent).
    const siblings = parent != null ? this.children.get(parent) ?? [] : [];
    const index = siblings.findIndex((s) => s.id === id);
    const neighbour = index >= 0 ? siblings[index + 1]?.id ?? siblings[index - 1]?.id ?? null : null;
    await this.run(`__wakeDT.remove(${id})`);
    if (parent != null) {
      await this.loadChildren(parent);
      const still = neighbour != null && this.children.get(parent)?.some((c) => c.id === neighbour) ? neighbour : null;
      await this.select(still ?? parent, false);
    }
  }

  duplicate(id: number) {
    return this.edit(`__wakeDT.duplicate(${id})`, id);
  }

  toggleHidden(id: number) {
    return this.edit(`__wakeDT.toggleHidden(${id})`, id);
  }

  scrollIntoView(id: number) {
    return this.run(`__wakeDT.scrollTo(${id})`);
  }

  async outerHTML(id: number): Promise<string> {
    return (await this.run<string>(`__wakeDT.outerHTML(${id})`)) ?? '';
  }

  async setOuterHTML(html: string, id: number) {
    const parent = this.parentID(id);
    const replaced = await this.run<any>(`__wakeDT.setOuterHTML(${id}, ${JSON.stringify(html)})`);
    if (parent != null) await this.loadChildren(parent);
    if (replaced && typeof replaced.id === 'number') await this.reveal(replaced.id, replaced.path ?? []);
    else if (parent != null) await this.select(parent, false);
  }

  parentID(id: number): number | null {
    for (const [parent, kids] of this.children) if (kids.some((k) => k.id === id)) return parent;
    return null;
  }

  node(id: number): DOMNode | null {
    return this.roots.find((r) => r.id === id) ?? [...this.children.values()].flat().find((c) => c.id === id) ?? null;
  }

  /** Rows for the tree, in document order, with closing tags after open elements. */
  get treeRows(): TreeRow[] {
    const rows: TreeRow[] = [];
    const add = (nodes: DOMNode[], depth: number) => {
      for (const node of nodes) {
        rows.push({ node, depth, isClosing: false, key: String(node.id) });
        const kids = this.children.get(node.id);
        if (this.expanded.has(node.id) && kids) {
          add(kids, depth + 1);
          if (isElement(node)) rows.push({ node, depth, isClosing: true, key: `/${node.id}` });
        }
      }
    };
    add(this.roots, 0);
    return rows;
  }

  // MARK: Console

  async evaluate(input: string) {
    const code = input.trim();
    if (!code) return;
    if (this.history[this.history.length - 1] !== code) this.history.push(code);
    if (this.history.length > 200) this.history.splice(0, this.history.length - 200);
    const log = this.page.devtools;
    log.addLocal('input', code);
    const result = await this.runScript<any>('async-devtools-evaluate', { code });
    if (!result) {
      log.addLocal('error', 'Couldn’t evaluate in this page.');
      return;
    }
    log.addLocal(result.ok ? 'result' : 'error', String(result.text ?? 'undefined'));
    if (result.ok && result.kind === 'node') await this.refreshSelectionFromPage();
  }

  async completions(code: string): Promise<string[]> {
    return (await this.runScript<string[]>('async-devtools-completions', { code })) ?? [];
  }

  /** An element returned in the console becomes `$0` and the Elements selection. */
  private async refreshSelectionFromPage() {
    const current = await this.run<any>('__wakeDT.current()');
    if (current && typeof current.id === 'number') await this.reveal(current.id, current.path ?? []);
  }

  // MARK: Network (resource timing)

  async pollResources() {
    const result = await this.run<any>(`__wakeDT.resources(${this.resourceCursor})`);
    if (!result) return;
    const total = Number(result.total) || 0;
    runInAction(() => {
      if (total < this.resourceCursor) {
        // The page cleared its buffer (or it's a new document).
        this.resourceCursor = 0;
        this.resources = [];
        return;
      }
      const base = this.resources.length;
      const entries: Resource[] = (result.entries ?? [])
        .filter((e: any) => typeof e.url === 'string')
        .map((e: any, offset: number) => ({
          id: base + offset,
          url: e.url,
          type: e.type ?? 'other',
          start: n(e.start),
          duration: n(e.duration),
          transferSize: n(e.transfer),
          encodedSize: n(e.encoded),
          decodedSize: n(e.decoded),
          protocolName: e.protocol ?? '',
          status: n(e.status),
          blocked: n(e.blocked),
          dns: n(e.dns),
          connect: n(e.connect),
          tls: n(e.tls),
          wait: n(e.wait),
          download: n(e.download),
        }));
      this.resourceCursor = total;
      if (entries.length) this.resources = [...this.resources, ...entries];
    });
  }

  clearResources() {
    this.resources = [];
  }

  // MARK: Storage

  async loadStorage() {
    const [local, session] = await Promise.all([this.items('local'), this.items('session')]);
    runInAction(() => {
      this.localItems = local;
      this.sessionItems = session;
    });
    await this.loadCookies();
    const result = await this.runScript<any>('async-devtools-storage');
    if (result) {
      runInAction(() => {
        this.asyncStorage = {
          databases: (result.databases ?? []).map((d: any) => ({ name: String(d.name ?? ''), version: n(d.version) })),
          caches: (result.caches ?? []).map((c: any) => ({ name: String(c.name ?? ''), count: n(c.count) })),
          workers: (result.workers ?? []).map((w: any) => ({ scope: String(w.scope ?? ''), script: String(w.script ?? ''), state: String(w.state ?? '') })),
        };
      });
    }
  }

  private async items(kind: 'local' | 'session'): Promise<StorageItem[]> {
    const rows = (await this.run<any[]>(`__wakeDT.storage('${kind}')`)) ?? [];
    return rows.filter((r) => Array.isArray(r) && r.length === 3).map((r) => ({ key: String(r[0]), value: String(r[1] ?? ''), length: n(r[2]) }));
  }

  async setStorage(kind: 'local' | 'session', key: string, value: string) {
    await this.run(`__wakeDT.storageSet('${kind}', ${JSON.stringify(key)}, ${JSON.stringify(value)})`);
    await this.reloadItems(kind);
  }

  async removeStorage(kind: 'local' | 'session', key: string) {
    await this.run(`__wakeDT.storageRemove('${kind}', ${JSON.stringify(key)})`);
    await this.reloadItems(kind);
  }

  async clearStorage(kind: 'local' | 'session') {
    await this.run(`__wakeDT.storageClear('${kind}')`);
    await this.reloadItems(kind);
  }

  private async reloadItems(kind: 'local' | 'session') {
    const items = await this.items(kind);
    runInAction(() => {
      if (kind === 'local') this.localItems = items;
      else this.sessionItems = items;
    });
  }

  async loadCookies() {
    try {
      const cookies = await host.call<Cookie[]>('page.cookies', { page: this.page.id });
      runInAction(() => (this.cookies = [...cookies].sort((a, b) => a.name.localeCompare(b.name))));
    } catch {
      runInAction(() => (this.cookies = []));
    }
  }

  async deleteCookie(cookie: Cookie) {
    await host.call('page.deleteCookie', { page: this.page.id, cookie }).catch(() => {});
    await this.loadCookies();
  }

  async setCookie(name: string, value: string, replacing: Cookie | null) {
    const cookie = { ...(replacing ?? { domain: '', path: '/', secure: false, httpOnly: false }), name, value };
    await host.call('page.setCookie', { page: this.page.id, cookie, old: replacing ?? undefined }).catch(() => {});
    await this.loadCookies();
  }

  async clearCookies() {
    for (const cookie of this.cookies) await host.call('page.deleteCookie', { page: this.page.id, cookie }).catch(() => {});
    await this.loadCookies();
  }

  /**
   * Limitation: a page can't close another script's IndexedDB connection, and the
   * engines have no API to force it. While the page holds the database open, the
   * delete is queued ("blocked") and completes once the page lets go.
   */
  async deleteDatabase(name: string) {
    const result = await this.runScript<string>('async-devtools-delete-database', { name });
    runInAction(() => (this.blockedDatabase = result === 'blocked' ? name : null));
    await this.loadStorage();
  }

  async deleteCache(name: string) {
    await this.runScript('async-devtools-delete-cache', { name });
    await this.loadStorage();
  }

  async unregisterWorker(scope: string) {
    await this.runScript('async-devtools-unregister-worker', { name: scope });
    await this.loadStorage();
  }

  /** Cookies, storage, caches and databases for the page's site, then a reload. */
  async clearSiteData() {
    await host.call('page.clearSiteData', { page: this.page.id }).catch(() => {});
    this.page.reload();
    this.documentChanged();
  }

  // MARK: Performance

  async loadMetrics() {
    const m = await this.run<any>('__wakeDT.metrics()');
    if (!m) return;
    const byType = Object.entries(m.byType ?? {})
      .map(([type, v]: [string, any]) => ({ type, count: n(v.count), transfer: n(v.transfer), decoded: n(v.decoded) }))
      .sort((a, b) => b.decoded - a.decoded);
    runInAction(() => {
      this.metrics = {
        ttfb: opt(m.ttfb), domInteractive: opt(m.domInteractive), dcl: opt(m.dcl), load: opt(m.load),
        fcp: opt(m.fcp), lcp: opt(m.lcp), cls: opt(m.cls), inp: opt(m.inp),
        support: m.support ?? {},
        requests: n(m.requests), transfer: n(m.transfer), decoded: n(m.decoded), documentTransfer: n(m.docTransfer),
        protocolName: m.protocol ?? '', navigationType: m.navType ?? '',
        byType,
        domNodes: n(m.domNodes), domDepth: n(m.domDepth), scripts: n(m.scripts), styleSheets: n(m.styleSheets),
        images: n(m.images), iframes: n(m.iframes), devicePixelRatio: n(m.dpr), viewport: m.viewport ?? '',
      };
    });
  }

  async runAudits() {
    const rows = (await this.run<any[]>('__wakeDT.audits()')) ?? [];
    runInAction(() => {
      this.audits = rows.map((a) => ({
        id: a.id ?? crypto.randomUUID(),
        title: a.title ?? '',
        state: ['pass', 'warn', 'fail'].includes(a.state) ? a.state : 'warn',
        detail: a.detail ?? '',
        count: n(a.count),
      }));
    });
  }

  async sampleFPS() {
    const value = await this.run<number>('__wakeDT.fps()');
    if (typeof value !== 'number') return;
    runInAction(() => {
      this.fpsSamples = [...this.fpsSamples, Math.min(value, 240)].slice(-60);
    });
  }

  stopFPS() {
    void this.run('__wakeDT.fpsStop()');
  }

  // MARK: Sources

  async loadSources() {
    const rows = (await this.run<any[]>('__wakeDT.sources()')) ?? [];
    const seen = new Set<string>();
    const inline: Record<string, number> = {};
    const sources: Source[] = [];
    for (const item of rows) {
      const kind = item.kind === 'style' ? 'style' : 'script';
      const url = typeof item.url === 'string' ? item.url : null;
      const index = n(item.index);
      const id = url ?? `${kind}#${index}`;
      if (seen.has(id)) continue;
      seen.add(id);
      let inlineNumber = 0;
      if (!url) inlineNumber = inline[kind] = (inline[kind] ?? 0) + 1;
      sources.push({ kind, url, index, isModule: !!item.module, inlineNumber, id });
    }
    runInAction(() => (this.sources = sources));
  }

  /** A script or stylesheet: inline ones from the DOM, the rest fetched with the page's cookies. */
  async text(source: Source): Promise<string> {
    if (!source.url) return (await this.run<string>(`__wakeDT.inlineSource('${source.kind}', ${source.index})`)) ?? '';
    return this.textOf(source.url);
  }

  async textOf(url: string): Promise<string> {
    const text = await this.runScript<string>('async-fetch-source', { url }, 'wake');
    if (typeof text === 'string') return text;
    // CORS refused: a plain request from the host instead.
    try {
      const response = await host.call<{ text: string }>('http.fetch', { url, maxBytes: 32 * 1024 * 1024 });
      return response.text;
    } catch {
      return '';
    }
  }

  /** The document as the server sent it (Ctrl+U). */
  documentSource(): Promise<string> {
    return this.page.url ? this.textOf(this.page.url) : Promise.resolve('');
  }

  // MARK: Page overrides

  async setColorScheme(scheme: ColorScheme): Promise<boolean> {
    try {
      await host.call('page.colorScheme', { page: this.page.id, scheme });
      runInAction(() => (this.colorScheme = scheme));
      return true;
    } catch {
      return false;
    }
  }

  /** null goes back to the engine's own user agent. Reloads, since servers read it on the first request. */
  setUserAgent(value: string | null) {
    this.userAgent = value;
    host.send('page.userAgent', { page: this.page.id, userAgent: value ?? '' });
    this.page.reload();
  }

  setJavaScriptDisabled(on: boolean) {
    this.page.setJavaScriptDisabled(on);
    this.page.reload();
  }

  setStylesDisabled(on: boolean) {
    this.stylesDisabled = on;
    void this.run(`__wakeDT.styles(${on})`);
  }

  setOutlines(on: boolean) {
    this.outlinesShown = on;
    void this.run(`__wakeDT.outlines(${on})`);
  }

  setDesignMode(on: boolean) {
    this.designMode = on;
    void this.run(`__wakeDT.designMode(${on})`);
  }
}

function parseDetails(o: any, id: number): ElementDetails {
  const box = o.box
    ? {
        x: n(o.box.x), y: n(o.box.y), width: n(o.box.width), height: n(o.box.height),
        margin: (o.box.margin ?? []).map(n), border: (o.box.border ?? []).map(n), padding: (o.box.padding ?? []).map(n),
        position: o.box.position ?? '', display: o.box.display ?? '', boxSizing: o.box.boxSizing ?? '',
      }
    : null;
  return {
    id,
    path: (o.path ?? []).filter((x: unknown) => typeof x === 'number'),
    node: parseNode(o.node),
    selector: o.selector ?? '',
    box,
    computed: (o.computed ?? []).filter((p: any) => Array.isArray(p) && p.length === 2).map((p: any) => [String(p[0]), String(p[1] ?? '')]),
    inlineStyle: o.inline ?? '',
    rules: (o.rules ?? []).map((r: any) => ({
      selector: r.selector ?? '',
      declarations: (r.decls ?? []).filter((p: any) => Array.isArray(p) && p.length === 2).map((p: any) => [String(p[0]), String(p[1])]),
      source: r.source ?? '',
      media: r.media ?? null,
    })),
    isHidden: !!o.hidden,
    htmlLength: n(o.html),
  };
}

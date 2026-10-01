// Every request the page made (NetworkPane.swift). fetch and XHR come from
// developer mode's hooks, with headers, bodies, replay and mocks; everything else
// comes from the page's Resource Timing buffer, on any page.
//
// Limitation: Resource Timing has no headers or bodies, and cross-origin entries
// without Timing-Allow-Origin report zero sizes and phases.

import { observer } from 'mobx-react-lite';
import { useEffect, useState } from 'react';
import { FileText, Braces, Paintbrush, Image as ImageIcon, Type, PlaySquare, ArrowLeftRight, Package, Network } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { inspector, type Resource, isCached } from '../../model/devtools-session';
import { curl, isFailure, type DevToolsLog, type NetworkEntry } from '../../model/devtools-log';
import { host } from '../../host/host';
import { MenuItem, MenuSeparator, useContextMenu } from '../common/Menu';
import { SearchField, CaptureBanner, Empty, DetailSection, DetailText, Sheet, bytes, milliseconds, prettyJSON } from './common';

type Category = 'all' | 'fetch' | 'document' | 'script' | 'style' | 'image' | 'font' | 'media' | 'other';
const CATEGORY_TITLES: Record<Category, string> = {
  all: 'All', fetch: 'Fetch/XHR', document: 'Doc', script: 'JS', style: 'CSS', image: 'Img', font: 'Font', media: 'Media', other: 'Other',
};

interface Item {
  id: string;
  method: string;
  url: string;
  status: number | null;
  category: Category;
  typeLabel: string;
  transferSize: number | null;
  size: number | null;
  duration: number | null;
  start: number | null;
  isCached: boolean;
  hooked: NetworkEntry | null;
  resource: Resource | null;
}

const itemFailed = (i: Item) => (i.hooked ? isFailure(i.hooked) : (i.status ?? 0) >= 400);
const pathOf = (url: string) => {
  try {
    return new URL(url).pathname;
  } catch {
    return url;
  }
};

function itemName(i: Item) {
  try {
    const u = new URL(i.url);
    const last = u.pathname.split('/').pop();
    const base = last || u.hostname;
    return u.search ? `${base}${u.search}` : base;
  } catch {
    return i.url;
  }
}

function statusText(i: Item) {
  if (i.hooked?.error) return 'ERR';
  if (i.status && i.status > 0) return String(i.status);
  if (i.hooked) return '…';
  return i.isCached ? 'cache' : '—';
}

const FETCH_LIKE = new Set(['fetch', 'xmlhttprequest', 'beacon']);

function extension(url: string) {
  return (pathOf(url).split('.').pop() ?? '').toLowerCase();
}

function categoryOf(r: Resource): Category {
  const ext = extension(r.url);
  if (['woff', 'woff2', 'ttf', 'otf', 'eot'].includes(ext)) return 'font';
  if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'svg', 'ico'].includes(ext)) return 'image';
  if (['mp4', 'webm', 'mp3', 'm4a', 'ogg', 'wav', 'm3u8', 'ts'].includes(ext)) return 'media';
  if (ext === 'css') return 'style';
  if (['js', 'mjs', 'cjs'].includes(ext)) return 'script';
  switch (r.type) {
    case 'navigation': case 'iframe': case 'frame': return 'document';
    case 'script': return 'script';
    case 'css': case 'link': return 'other';
    case 'img': case 'image': case 'input': return 'image';
    case 'video': case 'audio': case 'track': return 'media';
    case 'fetch': case 'xmlhttprequest': case 'beacon': return 'fetch';
    default: return 'other';
  }
}

function typeLabel(r: Resource, c: Category) {
  switch (c) {
    case 'document': return 'document';
    case 'script': return 'script';
    case 'style': return 'stylesheet';
    case 'image': return extension(r.url) || 'image';
    case 'font': return 'font';
    case 'media': return 'media';
    case 'fetch': return r.type === 'xmlhttprequest' ? 'xhr' : r.type;
    default: return r.type;
  }
}

function buildItems(log: DevToolsLog, resources: Resource[], hooked: boolean, documentStatus: number | null): Item[] {
  const items: Item[] = [];
  const claimed = new Set<number>();
  if (hooked) {
    for (const entry of log.network) {
      // Pair the hooked request with its timing entry, if the page reported one.
      const match = [...resources].reverse().find((r) => r.url === entry.url && FETCH_LIKE.has(r.type) && !claimed.has(r.id)) ?? null;
      if (match) claimed.add(match.id);
      const start = match?.start ?? entry.startedAt.getTime() - log.documentStart.getTime();
      items.push({
        id: `h${entry.id}`, method: entry.method, url: entry.url, status: entry.status ?? null, category: 'fetch', typeLabel: entry.initiator,
        transferSize: match?.transferSize ?? null, size: entry.responseSize ?? match?.decodedSize ?? null,
        duration: entry.duration != null ? entry.duration * 1000 : match?.duration ?? null, start, isCached: false, hooked: entry, resource: match,
      });
    }
  }
  for (const r of resources) {
    if (claimed.has(r.id) || (hooked && FETCH_LIKE.has(r.type))) continue;
    const category = categoryOf(r);
    // Resource Timing may have no status; for the document, Wake knows it.
    const status = r.status > 0 ? r.status : r.type === 'navigation' ? documentStatus : null;
    items.push({
      id: `r${r.id}`, method: 'GET', url: r.url, status, category, typeLabel: typeLabel(r, category),
      transferSize: r.transferSize, size: r.decodedSize, duration: r.duration, start: r.start, isCached: isCached(r), hooked: null, resource: r,
    });
  }
  return items.sort((a, b) => (a.start ?? Infinity) - (b.start ?? Infinity));
}

/**
 * The waterfall's time axis: linear, except that idle stretches (nothing in flight
 * for over a second) are shortened, so one late request doesn't squash everything
 * the page loaded into a sliver.
 */
class WaterfallScale {
  private busy: { start: number; end: number; axis: number }[] = [];
  private span = 1;
  isCompressed = false;
  private static idle = 1000;

  constructor(intervals: [number, number][]) {
    const merged: [number, number][] = [];
    for (const [s, e] of [...intervals].sort((a, b) => a[0] - b[0])) {
      const last = merged[merged.length - 1];
      if (last && s <= last[1] + WaterfallScale.idle) last[1] = Math.max(last[1], e);
      else merged.push([s, e]);
    }
    if (!merged.length) return;
    const busyTime = merged.reduce((t, [s, e]) => t + (e - s), 0);
    const gap = Math.max(WaterfallScale.idle / 4, busyTime / 20);
    let axis = merged[0][0];
    if (axis > WaterfallScale.idle) {
      axis = gap;
      this.isCompressed = true;
    }
    merged.forEach(([s, e], i) => {
      if (i > 0) {
        axis += gap;
        this.isCompressed = true;
      }
      this.busy.push({ start: s, end: e, axis });
      axis += e - s;
    });
    this.span = Math.max(axis, 0.001);
  }

  x(t: number, width: number) {
    const range = [...this.busy].reverse().find((b) => b.start <= t) ?? this.busy[0];
    if (!range) return (t / this.span) * width;
    return ((range.axis + Math.min(Math.max(t - range.start, 0), range.end - range.start)) / this.span) * width;
  }
}

const PHASES = (r: Resource) => [
  { name: 'Queued', value: r.blocked, color: '#8e8e93' },
  { name: 'DNS', value: r.dns, color: '#30b0c7' },
  { name: 'Connect', value: Math.max(0, r.connect - r.tls), color: '#ff9500' },
  { name: 'TLS', value: r.tls, color: '#af52de' },
  { name: 'Waiting (TTFB)', value: r.wait, color: '#34c759' },
  { name: 'Download', value: r.download, color: '#007aff' },
];

const ICONS: Record<Category, typeof FileText> = {
  all: Package, document: FileText, script: Braces, style: Paintbrush, image: ImageIcon, font: Type, media: PlaySquare, fetch: ArrowLeftRight, other: Package,
};

export const NetworkPane = observer(function NetworkPane({ page, browser }: { page: Page; browser: BrowserModel }) {
  const session = inspector(page);
  const log = page.devtools;
  const [selection, setSelection] = useState<string | null>(null);
  const [filter, setFilter] = useState<Category>('all');
  const [search, setSearch] = useState('');
  const [mockTarget, setMockTarget] = useState<NetworkEntry | null>(null);
  const [copiedHAR, setCopiedHAR] = useState(false);
  const menu = useContextMenu(browser);

  useEffect(() => {
    let live = true;
    const poll = async () => {
      while (live) {
        await session.pollResources();
        await new Promise((r) => setTimeout(r, 1000));
      }
    };
    void poll();
    return () => {
      live = false;
    };
  }, [session, page.url]);

  const all = buildItems(log, session.resources, page.isDeveloperMode, page.live.httpStatus ?? null);
  const q = search.trim().toLowerCase();
  const items = all.filter((i) => (filter === 'all' || i.category === filter) && (!q || i.url.toLowerCase().includes(q)));
  const scale = new WaterfallScale(items.filter((i) => i.start != null).map((i) => [i.start!, i.start! + (i.duration ?? 0)]));
  const selected = items.find((i) => i.id === selection) ?? null;
  const transferred = items.reduce((t, i) => t + (i.transferSize ?? 0), 0);
  const resourcesSize = items.reduce((t, i) => t + (i.size ?? 0), 0);
  const finishes = items.filter((i) => i.start != null).map((i) => i.start! + (i.duration ?? 0));
  const copy = (text: string) => host.send('clipboard.write', { text });

  return (
    <div className="pane">
      <div className="pane-toolbar">
        <SearchField value={search} onChange={setSearch} placeholder="Filter URLs" width={180} />
        <div className="category-bar">
          {(Object.keys(CATEGORY_TITLES) as Category[]).map((c) => (
            <button key={c} className={filter === c ? 'is-selected' : ''} onClick={() => setFilter(c)}>
              {CATEGORY_TITLES[c]}
            </button>
          ))}
        </div>
      </div>
      {!page.isDeveloperMode && <CaptureBanner page={page} message="Turn on developer mode for fetch/XHR headers, bodies, replay and mocks." />}
      {items.length === 0 ? (
        <Empty
          icon={<Network size={26} strokeWidth={1.2} className="tertiary" />}
          title={all.length ? 'Nothing matches' : 'No requests yet'}
          detail={all.length ? 'Try another filter.' : 'Requests appear here as the page makes them. Reload to see the page load.'}
        />
      ) : (
        <>
          <div className="net-header">
            <span className="net-name">Name</span>
            <span className="net-status">Status</span>
            <span className="net-type">Type</span>
            <span className="net-size">Size</span>
            <span className="net-time">Time</span>
            <span className="net-fall" title={scale.isCompressed ? 'Idle stretches over a second are shortened so every burst of requests stays readable.' : ''}>
              {scale.isCompressed ? 'Waterfall ⋯' : 'Waterfall'}
            </span>
          </div>
          <div className="net-list">
            {items.map((item) => {
              const Icon = ICONS[item.category];
              const mocked = !!log.mocks[pathOf(item.url)];
              const status = statusText(item);
              const statusColor = item.hooked?.error ? 'var(--red)' : item.status == null ? 'var(--text-2)' : item.status < 300 ? 'var(--green)' : item.status < 400 ? 'var(--text-2)' : 'var(--red)';
              return (
                <button
                  key={item.id}
                  className={`net-row ${item.id === selection ? 'is-selected' : ''}`}
                  onClick={() => setSelection(item.id === selection ? null : item.id)}
                  onContextMenu={menu.open(() => (
                    <>
                      <MenuItem onSelect={() => copy(item.url)}>Copy URL</MenuItem>
                      {item.hooked ? (
                        <>
                          <MenuItem onSelect={() => copy(curl(item.hooked!))}>Copy as cURL</MenuItem>
                          <MenuItem onSelect={() => copy(fetchSnippet(item.hooked!))}>Copy as fetch</MenuItem>
                          {item.hooked.responsePreview && <MenuItem onSelect={() => copy(item.hooked!.responsePreview!)}>Copy Response</MenuItem>}
                          <MenuSeparator />
                          <MenuItem onSelect={() => replay(page, item.hooked!)}>Replay</MenuItem>
                        </>
                      ) : (
                        <MenuItem onSelect={() => copy(`curl '${item.url.replace(/'/g, "'\\''")}'`)}>Copy as cURL</MenuItem>
                      )}
                      <MenuSeparator />
                      <MenuItem onSelect={() => browser.trail.open(item.url)}>Open in New Column</MenuItem>
                    </>
                  ))}
                >
                  <span className="net-name">
                    <Icon size={11} className="secondary" />
                    <span className={`truncate mono ${itemFailed(item) ? 'failed' : ''}`}>{itemName(item)}</span>
                    {mocked && <span className="mock-badge">MOCK</span>}
                  </span>
                  <span className="net-status mono" style={{ color: statusColor }}>
                    {status}
                  </span>
                  <span className="net-type secondary truncate">{item.typeLabel}</span>
                  <span className="net-size mono secondary">{item.isCached && !item.transferSize ? 'cache' : bytes(item.size)}</span>
                  <span className="net-time mono secondary">{item.duration != null ? milliseconds(item.duration) : '…'}</span>
                  <span className="net-fall">
                    <Waterfall item={item} scale={scale} />
                  </span>
                </button>
              );
            })}
          </div>
          {selected && <NetworkDetail item={selected} page={page} onMock={() => setMockTarget(selected.hooked)} />}
        </>
      )}
      <div className="net-footer">
        <span>{items.length === all.length ? `${all.length} requests` : `${items.length} / ${all.length} requests`}</span>
        <span>{bytes(transferred)} transferred</span>
        <span>{bytes(resourcesSize)} resources</span>
        {finishes.length > 0 && <span>Finish {milliseconds(Math.max(...finishes))}</span>}
        <span style={{ flex: 1 }} />
        <button
          className="link-button"
          disabled={!all.length}
          title="Copy every request as an HTTP Archive (HAR) for other tools"
          onClick={() => {
            copy(har(all, log.documentStart));
            setCopiedHAR(true);
          }}
        >
          {copiedHAR ? 'Copied' : 'Copy HAR'}
        </button>
      </div>
      {menu.element}
      {mockTarget && (
        <MockEditor
          entry={mockTarget}
          current={log.mocks[pathOf(mockTarget.url)] ?? null}
          onClose={() => setMockTarget(null)}
          onSave={(body) => {
            page.setMock(body, pathOf(mockTarget.url));
            setMockTarget(null);
          }}
        />
      )}
    </div>
  );
});

function Waterfall({ item, scale }: { item: Item; scale: WaterfallScale }) {
  const width = 90;
  const from = item.start ?? 0;
  const start = scale.x(from, width);
  const w = Math.max(2, scale.x(from + (item.duration ?? 0), width) - start);
  const r = item.resource;
  return (
    <span className="fall" style={{ left: Math.min(start, width - w), width: w }}>
      {r && r.duration > 0 ? (
        PHASES(r).map((p) => <span key={p.name} style={{ width: `${(p.value / r.duration) * 100}%`, background: p.color }} />)
      ) : (
        <span style={{ width: '100%', background: '#007aff' }} />
      )}
    </span>
  );
}

/** Re-sends a captured request from the page, so cookies and origin match. */
function replay(page: Page, entry: NetworkEntry) {
  const options: Record<string, unknown> = { method: entry.method, headers: entry.requestHeaders };
  if (entry.requestBody) options.body = entry.requestBody;
  page.exec(`fetch(${JSON.stringify(entry.url)}, ${JSON.stringify(options)}).catch(() => {});`, 'page');
}

function fetchSnippet(entry: NetworkEntry) {
  const options: Record<string, unknown> = { method: entry.method, headers: entry.requestHeaders };
  if (entry.requestBody) options.body = entry.requestBody;
  return `fetch(${JSON.stringify(entry.url)}, ${JSON.stringify(options, null, 2)});`;
}

function har(items: Item[], documentStart: Date) {
  const entries = items.map((item) => {
    const started = new Date(documentStart.getTime() + (item.start ?? 0));
    const h = item.hooked;
    const r = item.resource;
    let query: { name: string; value: string }[] = [];
    try {
      query = [...new URL(item.url).searchParams].map(([name, value]) => ({ name, value }));
    } catch {}
    const request: Record<string, unknown> = {
      method: item.method, url: item.url, httpVersion: r?.protocolName ?? '',
      headers: Object.entries(h?.requestHeaders ?? {}).map(([name, value]) => ({ name, value })), queryString: query, cookies: [],
      headersSize: -1, bodySize: h?.requestBody?.length ?? 0,
    };
    if (h?.requestBody) request.postData = { mimeType: h.requestHeaders['content-type'] ?? '', text: h.requestBody };
    return {
      startedDateTime: started.toISOString(),
      time: item.duration ?? 0,
      request,
      response: {
        status: item.status ?? 0, statusText: '', httpVersion: r?.protocolName ?? '',
        headers: Object.entries(h?.responseHeaders ?? {}).map(([name, value]) => ({ name, value })), cookies: [], redirectURL: '',
        headersSize: -1, bodySize: item.transferSize ?? -1,
        content: { size: item.size ?? 0, mimeType: h?.responseHeaders['content-type'] ?? item.typeLabel, text: h?.responsePreview ?? '' },
      },
      cache: {},
      timings: { blocked: r?.blocked ?? -1, dns: r?.dns ?? -1, connect: r?.connect ?? -1, ssl: r?.tls ?? -1, send: 0, wait: r?.wait ?? item.duration ?? 0, receive: r?.download ?? 0 },
    };
  });
  return JSON.stringify({ log: { version: '1.2', creator: { name: 'Wake', version: '0.1' }, entries } }, null, 2);
}

type DetailTab = 'Headers' | 'Payload' | 'Response' | 'Timing';

const NetworkDetail = observer(function NetworkDetail({ item, page, onMock }: { item: Item; page: Page; onMock: () => void }) {
  const [tab, setTab] = useState<DetailTab>('Headers');
  const [copied, setCopied] = useState(false);
  useEffect(() => setCopied(false), [item.id]);
  const entry = item.hooked;
  const mocked = entry ? !!page.devtools.mocks[pathOf(entry.url)] : false;
  return (
    <div className="net-detail">
      <div className="pane-toolbar">
        <div className="segmented small">
          {(['Headers', 'Payload', 'Response', 'Timing'] as DetailTab[]).map((t) => (
            <button key={t} className={tab === t ? 'is-selected' : ''} onClick={() => setTab(t)}>
              {t}
            </button>
          ))}
        </div>
        <span style={{ flex: 1 }} />
        {entry && (
          <>
            <button className="button small" onClick={() => replay(page, entry)}>
              Replay
            </button>
            <button
              className="button small"
              onClick={() => {
                host.send('clipboard.write', { text: curl(entry) });
                setCopied(true);
              }}
            >
              {copied ? 'Copied' : 'cURL'}
            </button>
            {mocked ? (
              <button className="button small" onClick={() => page.setMock(null, pathOf(entry.url))}>
                Remove Mock
              </button>
            ) : (
              <button className="button small" onClick={onMock}>
                Mock…
              </button>
            )}
          </>
        )}
      </div>
      <div className="dt-scroll pad selectable">
        {tab === 'Headers' && (
          <>
            <DetailSection
              title="General"
              rows={([
                ['URL', item.url],
                ['Method', item.method],
                ['Status', statusText(item)],
                ['Type', item.typeLabel],
                ['Protocol', item.resource?.protocolName ?? ''],
                ['Transferred', item.transferSize ? bytes(item.transferSize) : ''],
                ['Size', item.size ? bytes(item.size) : ''],
              ] as [string, string][]).filter(([, v]) => v)}
            />
            {entry ? (
              <>
                {Object.keys(entry.responseHeaders).length > 0 && <DetailSection title="Response headers" rows={Object.entries(entry.responseHeaders).sort()} />}
                {Object.keys(entry.requestHeaders).length > 0 && <DetailSection title="Request headers" rows={Object.entries(entry.requestHeaders).sort()} />}
              </>
            ) : (
              <div className="secondary small">Headers are only captured for fetch and XHR in developer mode.</div>
            )}
          </>
        )}
        {tab === 'Payload' && <Payload item={item} />}
        {tab === 'Response' && <ResponseView item={item} page={page} />}
        {tab === 'Timing' && <Timing item={item} />}
      </div>
    </div>
  );
});

function Payload({ item }: { item: Item }) {
  let query: [string, string][] = [];
  try {
    query = [...new URL(item.url).searchParams];
  } catch {}
  const body = item.hooked?.requestBody;
  return (
    <>
      {query.length > 0 && <DetailSection title="Query string" rows={query} />}
      {body && <DetailText title="Request body" text={prettyJSON(body)} />}
      {!query.length && !body && <div className="secondary small">No payload.</div>}
    </>
  );
}

function ResponseView({ item, page }: { item: Item; page: Page }) {
  const [text, setText] = useState<string | null>(null);
  const needsFetch = !item.hooked?.responsePreview && ['script', 'style', 'document'].includes(item.category);
  useEffect(() => {
    setText(null);
    if (needsFetch) void inspector(page).textOf(item.url).then(setText);
  }, [item.url, needsFetch, page]);
  return (
    <>
      {item.hooked?.error && <DetailText title="Error" text={item.hooked.error} />}
      {item.category === 'image' ? (
        <img src={item.url} alt="" style={{ maxWidth: 260, maxHeight: 200 }} />
      ) : item.hooked?.responsePreview ? (
        <DetailText title="Response" text={prettyJSON(item.hooked.responsePreview)} />
      ) : needsFetch ? (
        text == null ? <span className="spinner" /> : <DetailText title="Response" text={text.slice(0, 30000)} />
      ) : (
        <div className="secondary small">No response body captured.</div>
      )}
    </>
  );
}

function Timing({ item }: { item: Item }) {
  const r = item.resource;
  if (r && r.duration > 0) {
    return (
      <div className="timing">
        {PHASES(r)
          .filter((p) => p.value > 0.05)
          .map((p) => (
            <div key={p.name} className="timing-row">
              <span className="timing-name">{p.name}</span>
              <span className="timing-bar">
                <span style={{ width: `${Math.max(1, (p.value / r.duration) * 100)}%`, background: p.color }} />
              </span>
              <span className="mono secondary timing-value">{milliseconds(p.value)}</span>
            </div>
          ))}
        <div className="timing-total">
          <strong>Total</strong>
          <span className="mono">{milliseconds(r.duration)}</span>
        </div>
        <div className="secondary small">Started {milliseconds(r.start)} after navigation.</div>
      </div>
    );
  }
  if (item.duration != null) return <div className="secondary small">Took {milliseconds(item.duration)}. The server didn’t allow detailed timing (Timing-Allow-Origin).</div>;
  return <div className="secondary small">Pending…</div>;
}

/** Answer a route with JSON you write, without touching the server (fetch only). */
function MockEditor({ entry, current, onSave, onClose }: { entry: NetworkEntry; current: string | null; onSave: (body: string) => void; onClose: () => void }) {
  const [text, setText] = useState(current ?? prettyJSON(entry.responsePreview ?? '{}'));
  const [error, setError] = useState<string | null>(null);
  return (
    <Sheet title={`Mock ${pathOf(entry.url)}`} onClose={onClose}>
      <div className="secondary small">fetch calls to this path return this JSON with status 200 until you remove the mock.</div>
      <textarea className="code-editor" value={text} spellCheck={false} onChange={(e) => setText(e.target.value)} autoFocus />
      {error && <div className="small" style={{ color: 'var(--red)' }}>{error}</div>}
      <div className="confirm-actions">
        <button className="button" onClick={onClose}>
          Cancel
        </button>
        <button
          className="button primary"
          onClick={() => {
            try {
              JSON.parse(text);
              onSave(text);
            } catch {
              setError('That isn’t valid JSON.');
            }
          }}
        >
          Save Mock
        </button>
      </div>
    </Sheet>
  );
}

// The library's History section (HistoryView.swift): pages you visited, or things
// you searched for, newest first and grouped by day.

import { observer } from 'mobx-react-lite';
import { useEffect, useRef, useState } from 'react';
import { Search, XCircle, Ellipsis, History as HistoryIcon } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import { history, type Search as SearchRecord, type Visit } from '../../model/history';
import { hostOf } from '../../model/page';
import { host } from '../../host/host';
import { Favicon } from '../common/Favicon';
import { Menu, MenuItem, MenuSeparator, useContextMenu } from '../common/Menu';
import { historyDayTitle, timeLabel } from './format';

const PAGE_SIZE = 400;

type Item = Visit | SearchRecord;
const dateOf = (item: Item) => ('visitedAt' in item ? item.visitedAt : item.searchedAt);

export const HistoryContent = observer(function HistoryContent({ browser, kind }: { browser: BrowserModel; kind: 'pages' | 'searches' }) {
  const [query, setQuery] = useState('');
  const [limit, setLimit] = useState(PAGE_SIZE);
  const [items, setItems] = useState<Item[] | null>(null);
  const [confirming, setConfirming] = useState(false);
  const search = useRef<HTMLInputElement>(null);
  const menu = useContextMenu(browser);
  const version = history.version;

  useEffect(() => {
    requestAnimationFrame(() => search.current?.focus());
  }, []);
  useEffect(() => setLimit(PAGE_SIZE), [query]);
  useEffect(() => {
    let live = true;
    const load = kind === 'pages' ? history.visits(query, limit) : history.searches(query, limit);
    void load.then((rows) => live && setItems(rows));
    return () => {
      live = false;
    };
  }, [kind, query, limit, version]);

  const count = kind === 'pages' ? history.visitCount : history.searchCount;
  const noun = kind === 'pages' ? (count === 1 ? 'page' : 'pages') : count === 1 ? 'search' : 'searches';
  const total = `${count.toLocaleString()} ${noun}`;

  const days: { title: string; items: Item[] }[] = [];
  for (const item of items ?? []) {
    const title = historyDayTitle(dateOf(item));
    const last = days[days.length - 1];
    if (last && last.title === title) last.items.push(item);
    else days.push({ title, items: [item] });
  }

  return (
    <>
      <header className="library-header">
        <div className="library-title">
          <h2>{kind === 'pages' ? 'History' : 'Searches'}</h2>
          <span className="secondary small">{query ? `Searching ${total}` : total}</span>
        </div>
        <label className="library-search">
          <Search size={12} strokeWidth={2.5} className="secondary" />
          <input ref={search} placeholder={kind === 'pages' ? 'Search titles and addresses' : 'Search what you searched for'} value={query} onChange={(e) => setQuery(e.target.value)} />
          {query && (
            <button aria-label="Clear search" onClick={() => setQuery('')}>
              <XCircle size={14} className="tertiary" />
            </button>
          )}
        </label>
        <Menu browser={browser} className="icon-button" title="Import and clear" label={<Ellipsis size={16} />}>
          <MenuItem onSelect={() => (browser.isImportingBrowserData = true)}>Import from Another Browser…</MenuItem>
          <MenuSeparator />
          <MenuItem danger onSelect={() => setConfirming(true)}>
            {kind === 'pages' ? 'Clear History…' : 'Clear Searches…'}
          </MenuItem>
        </Menu>
      </header>
      {items && items.length === 0 ? (
        <div className="empty-shelf">
          {query ? <Search size={30} strokeWidth={1.2} className="tertiary" /> : <HistoryIcon size={30} strokeWidth={1.2} className="tertiary" />}
          <div className="empty-shelf-title">{query ? 'Nothing matches' : kind === 'pages' ? 'No history yet' : 'No searches yet'}</div>
          <div className="secondary small">
            {query
              ? 'Try fewer words, or part of the address.'
              : kind === 'pages'
                ? 'Pages you visit appear here, newest first.'
                : 'Searches from Ctrl+K and from any search engine’s own box appear here.'}
          </div>
          {!query && (
            <button className="link-button" onClick={() => (browser.isImportingBrowserData = true)}>
              Import from Another Browser…
            </button>
          )}
        </div>
      ) : (
        <div className="history-list">
          {days.map((day) => (
            <section key={day.title}>
              <div className="history-day">{day.title}</div>
              {day.items.map((item) =>
                'visitedAt' in item ? (
                  <VisitRow
                    key={item.url}
                    visit={item}
                    onOpen={() => browser.openFromLibrary(item.url)}
                    onContextMenu={menu.open(() => (
                      <>
                        <MenuItem onSelect={() => browser.openFromLibrary(item.url)}>Open</MenuItem>
                        <MenuItem onSelect={() => host.send('clipboard.write', { text: item.url })}>Copy Link</MenuItem>
                        <MenuSeparator />
                        <MenuItem danger onSelect={() => void history.deleteVisit(item.url)}>
                          Remove from History
                        </MenuItem>
                      </>
                    ))}
                  />
                ) : (
                  <SearchRow
                    key={item.id}
                    search={item}
                    onOpen={() => browser.openFromLibrary(item.url)}
                    onContextMenu={menu.open(() => (
                      <>
                        <MenuItem onSelect={() => browser.openFromLibrary(item.url)}>Search Again</MenuItem>
                        <MenuItem onSelect={() => host.send('clipboard.write', { text: item.query })}>Copy Search</MenuItem>
                        <MenuSeparator />
                        <MenuItem danger onSelect={() => void history.deleteSearch(item.id)}>
                          Remove from Searches
                        </MenuItem>
                      </>
                    ))}
                  />
                ),
              )}
            </section>
          ))}
          {items && items.length === limit && (
            <button className="link-button show-more" onClick={() => setLimit(limit + PAGE_SIZE)}>
              Show More
            </button>
          )}
        </div>
      )}
      {menu.element}
      {confirming && (
        <div className="confirm-backdrop" onPointerDown={() => setConfirming(false)}>
          <div className="confirm glass-strong" onPointerDown={(e) => e.stopPropagation()}>
            <div className="confirm-title">{kind === 'pages' ? 'Clear all history?' : 'Clear all searches?'}</div>
            <div className="secondary">
              {kind === 'pages' ? 'Forgets every visited page and search. Threads, moments and pinned apps stay.' : 'Forgets what you searched for. Visited pages stay.'}
            </div>
            <div className="confirm-actions">
              <button className="button" onClick={() => setConfirming(false)}>
                Cancel
              </button>
              <button
                className="button primary danger-fill"
                onClick={() => {
                  setConfirming(false);
                  void (kind === 'pages' ? history.clearAll() : history.clearSearches());
                }}
              >
                Clear
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
});

const displayAddress = (url: string) => url.replace(/^https?:\/\//, '').replace(/^www\./, '');

function VisitRow({ visit, onOpen, onContextMenu }: { visit: Visit; onOpen: () => void; onContextMenu: (e: React.MouseEvent) => void }) {
  const h = hostOf(visit.url);
  return (
    <button className="history-row" title={visit.url} onClick={onOpen} onContextMenu={onContextMenu}>
      <Favicon host={h} size={16} />
      <span className="history-text">
        <span className="truncate">{visit.title || h}</span>
        <span className="secondary small truncate">{displayAddress(visit.url)}</span>
      </span>
      {visit.source && <span className="source-badge">{visit.source}</span>}
      <span className="secondary small tabular">{timeLabel(visit.visitedAt)}</span>
    </button>
  );
}

function SearchRow({ search, onOpen, onContextMenu }: { search: SearchRecord; onOpen: () => void; onContextMenu: (e: React.MouseEvent) => void }) {
  return (
    <button className="history-row" onClick={onOpen} onContextMenu={onContextMenu}>
      <span className="search-glyph">
        <Search size={10} strokeWidth={2.6} />
      </span>
      <span className="history-text">
        <span className="truncate">{search.query}</span>
        <span className="secondary small">{search.engine}</span>
      </span>
      {search.source && <span className="source-badge">{search.source}</span>}
      <span className="secondary small tabular">{timeLabel(search.searchedAt)}</span>
    </button>
  );
}

// Moments over the whole window (MomentsLibrary.swift, MomentsSidebar.swift,
// MomentCard.swift, MomentTimeline.swift, ResolvedThreadDetail.swift): a sidebar
// of smart shelves, History and resolved threads, and a content pane with search
// and a card grid or timeline.

import { observer } from 'mobx-react-lite';
import { useEffect, useRef } from 'react';
import {
  Inbox, MapPin, Clock, RefreshCw, Hourglass, Archive, History, Search, ChevronLeft, LayoutGrid, List, XCircle, BadgeCheck,
} from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import {
  momentStore, momentHost, shelfContains, shelfKey, resurfaceDate, RESURFACE_LABELS, SHELF_TITLES, SMART_SHELVES, ARCHIVE_AFTER,
  type Moment, type MomentShelf, type ResurfaceChoice,
} from '../../model/moments';
import { threadStore } from '../../model/threads';
import { history } from '../../model/history';
import { momentThumbnails } from '../../model/deck';
import { hostOf } from '../../model/page';
import { host } from '../../host/host';
import { Favicon, monogramColor } from '../common/Favicon';
import { MenuItem, MenuSeparator, SubMenu, useContextMenu } from '../common/Menu';
import { usePresence } from '../motion';
import { groupTitle, savedLabel, searchScore, searchTokens, statusOf, timeLabel, type MomentStatus } from './format';
import { HistoryContent } from './HistoryContent';
import './moments.css';

const SHELF_ICONS: Record<string, typeof Inbox> = {
  everything: Inbox,
  relevant: MapPin,
  resurfacing: Clock,
  changed: RefreshCw,
  fading: Hourglass,
  archived: Archive,
  history: History,
  searches: Search,
};

export const MomentsLibrary = observer(function MomentsLibrary({ browser }: { browser: BrowserModel }) {
  const { mounted, visible } = usePresence(browser.isMomentsOpen, 220);
  if (!mounted) return null;
  const shelf = browser.momentsShelf;
  return (
    <div className={`library ${visible ? 'is-visible' : ''}`}>
      <Sidebar browser={browser} />
      <div className="library-content">
        {typeof shelf === 'object' ? (
          <ResolvedThreadDetail browser={browser} threadID={shelf.resolvedThread} />
        ) : shelf === 'history' || shelf === 'searches' ? (
          <HistoryContent key={shelf} browser={browser} kind={shelf === 'searches' ? 'searches' : 'pages'} />
        ) : (
          <MomentsContent browser={browser} />
        )}
      </div>
    </div>
  );
});

const Sidebar = observer(function Sidebar({ browser }: { browser: BrowserModel }) {
  const now = new Date();
  const site = browser.momentsHost;
  const all = momentStore.moments(true);
  const resolved = threadStore.resolvedThreads;
  const row = (shelf: MomentShelf, count: number) => {
    const key = shelfKey(shelf);
    const Icon = SHELF_ICONS[key] ?? Inbox;
    const selected = shelfKey(browser.momentsShelf) === key && !browser.momentsQuery;
    return (
      <button
        key={key}
        className={`shelf-row ${selected ? 'is-selected' : ''}`}
        onClick={() => {
          browser.momentsQuery = '';
          browser.momentsShelf = shelf;
        }}
      >
        <Icon size={14} className="accent" />
        <span className="truncate" style={{ flex: 1 }}>
          {SHELF_TITLES[key]}
        </span>
        {count > 0 && <span className="secondary tabular">{count.toLocaleString()}</span>}
      </button>
    );
  };
  return (
    <nav className="library-sidebar">
      <div className="section-label">Moments</div>
      {SMART_SHELVES.map((s) => row(s, all.filter((m) => shelfContains(s, m, site, now)).length))}
      {row('archived', all.filter((m) => m.isArchived).length)}
      <div className="section-label spaced">History</div>
      {row('history', history.visitCount)}
      {row('searches', history.searchCount)}
      {resolved.length > 0 && (
        <>
          <div className="section-label spaced">Resolved threads</div>
          <div className="resolved-list">
            {resolved.map((record) => {
              const selected = typeof browser.momentsShelf === 'object' && browser.momentsShelf.resolvedThread === record.id;
              return (
                <button
                  key={record.id}
                  className={`resolved-row ${selected ? 'is-selected' : ''}`}
                  onClick={() => {
                    browser.momentsQuery = '';
                    browser.momentsShelf = { resolvedThread: record.id };
                  }}
                >
                  <span className="truncate">{record.customTitle ?? record.title}</span>
                  {record.outcome && <span className="secondary small truncate">{record.outcome}</span>}
                </button>
              );
            })}
          </div>
        </>
      )}
      <span style={{ flex: 1 }} />
      <button className="back-button secondary" title="Back to the trail (Esc)" onClick={() => browser.hideMoments()}>
        <ChevronLeft size={13} /> Back to the trail
      </button>
    </nav>
  );
});

const MomentsContent = observer(function MomentsContent({ browser }: { browser: BrowserModel }) {
  const search = useRef<HTMLInputElement>(null);
  const menu = useContextMenu(browser);
  useEffect(() => {
    requestAnimationFrame(() => search.current?.focus());
  }, []);
  void momentStore.version;
  const now = new Date();
  const site = browser.momentsHost;
  const tokens = searchTokens(browser.momentsQuery);
  const shelf = browser.momentsShelf as Exclude<MomentShelf, { resolvedThread: string }>;
  const results = tokens.length
    ? // Search looks everywhere, archive included, best first.
      momentStore
        .moments(true)
        .map((m) => [m, searchScore(m, tokens)] as const)
        .filter(([, s]) => s > 0)
        .sort((a, b) => (a[1] !== b[1] ? b[1] - a[1] : b[0].createdAt - a[0].createdAt))
        .map(([m]) => m)
    : momentStore.moments(shelf === 'archived').filter((m) => shelfContains(shelf, m, site, now));
  const count = `${results.length} moment${results.length === 1 ? '' : 's'}`;
  const subtitle = tokens.length
    ? count
    : shelf === 'relevant'
      ? site
        ? `${count} on ${site}`
        : 'Open a page to see moments saved on its site'
      : shelf === 'fading'
        ? `${count} · unopened for a month; archived after ${ARCHIVE_AFTER / 86_400} days`
        : shelf === 'changed'
          ? `${count} · checked in the background while Wake is open`
          : count;
  const openMenu = (m: Moment) => menu.open(() => <MomentMenu browser={browser} moment={m} />);

  return (
    <>
      <header className="library-header">
        <div className="library-title">
          <h2>{tokens.length ? 'Search' : SHELF_TITLES[shelf]}</h2>
          <span className="secondary small">{subtitle}</span>
        </div>
        <label className="library-search">
          <Search size={12} strokeWidth={2.5} className="secondary" />
          <input ref={search} placeholder="Search moments" value={browser.momentsQuery} onChange={(e) => (browser.momentsQuery = e.target.value)} />
          {browser.momentsQuery && (
            <button aria-label="Clear search" onClick={() => (browser.momentsQuery = '')}>
              <XCircle size={14} className="tertiary" />
            </button>
          )}
        </label>
        <div className="segmented" role="radiogroup" aria-label="Layout">
          <button className={browser.momentsLayout === 'grid' ? 'is-selected' : ''} title="Grid" onClick={() => (browser.momentsLayout = 'grid')}>
            <LayoutGrid size={13} />
          </button>
          <button className={browser.momentsLayout === 'timeline' ? 'is-selected' : ''} title="Timeline" onClick={() => (browser.momentsLayout = 'timeline')}>
            <List size={13} />
          </button>
        </div>
      </header>
      {results.length === 0 ? (
        <EmptyShelf shelf={shelf} searching={tokens.length > 0} />
      ) : browser.momentsLayout === 'grid' ? (
        <div className="moment-grid">
          {results.map((m, i) => (
            <MomentCard key={m.id} moment={m} status={statusOf(m, site, now)} bestMatch={tokens.length > 0 && i === 0} onOpen={() => browser.openMoment(m)} onContextMenu={openMenu(m)} />
          ))}
        </div>
      ) : (
        <Timeline moments={results} site={site} groups={tokens.length === 0} browser={browser} onContextMenu={openMenu} />
      )}
      {menu.element}
    </>
  );
});

const EMPTY: Record<string, [string, string]> = {
  everything: ['No moments yet', 'Press Ctrl+D on any page to save a moment: where you were, what you selected, and why.'],
  relevant: ['Nothing saved on this site', ''],
  resurfacing: ['Nothing resurfacing today', ''],
  changed: ['No saved page has changed', ''],
  fading: ['Nothing is fading', 'Moments you don’t open for a month fade here, then move to the archive.'],
  archived: ['The archive is empty', ''],
};

function EmptyShelf({ shelf, searching }: { shelf: string; searching: boolean }) {
  const Icon = searching ? Search : SHELF_ICONS[shelf] ?? Inbox;
  const [title, detail] = searching ? ['No moments match', 'Search looks at titles, your notes, highlights, sites and page text.'] : EMPTY[shelf] ?? ['', ''];
  return (
    <div className="empty-shelf">
      <Icon size={30} strokeWidth={1.2} className="tertiary" />
      <div className="empty-shelf-title">{title}</div>
      {detail && <div className="secondary small">{detail}</div>}
    </div>
  );
}

export const MomentMenu = observer(function MomentMenu({ browser, moment }: { browser: BrowserModel; moment: Moment }) {
  return (
    <>
      <MenuItem onSelect={() => browser.openMoment(moment)}>Open</MenuItem>
      <MenuItem onSelect={() => host.send('clipboard.write', { text: moment.url })}>Copy Link</MenuItem>
      <MenuSeparator />
      <SubMenu label="Resurface">
        {(Object.keys(RESURFACE_LABELS) as ResurfaceChoice[]).map((c) => (
          <MenuItem key={c} onSelect={() => void momentStore.update(moment.id, { resurfaceAt: resurfaceDate(c) })}>
            {RESURFACE_LABELS[c]}
          </MenuItem>
        ))}
      </SubMenu>
      {moment.changedAt != null && <MenuItem onSelect={() => void momentStore.update(moment.id, { changedAt: null, changeSummary: null })}>Mark Change as Seen</MenuItem>}
      <MenuItem
        onSelect={() =>
          // Back from the archive it counts as seen, so it doesn't fade straight away.
          void momentStore.update(moment.id, moment.isArchived ? { isArchived: false, lastOpenedAt: Date.now() / 1000 } : { isArchived: true })
        }
      >
        {moment.isArchived ? 'Unarchive' : 'Archive'}
      </MenuItem>
      <MenuSeparator />
      <MenuItem danger onSelect={() => void momentStore.delete(moment)}>
        Delete
      </MenuItem>
    </>
  );
});

const MomentPreview = observer(function MomentPreview({ moment, className }: { moment: Moment; className: string }) {
  const url = momentThumbnails.url(moment.id);
  const h = momentHost(moment);
  return (
    <span className={className}>
      {url ? (
        <img src={url} alt="" draggable={false} onError={() => momentThumbnails.markMissing(moment.id)} />
      ) : (
        <span className="preview-empty" style={{ background: `color-mix(in srgb, ${monogramColor(h)} 14%, transparent)` }}>
          <Favicon host={h} size={className.includes('small') ? 16 : 28} />
        </span>
      )}
    </span>
  );
});

function StatusChip({ status }: { status: MomentStatus }) {
  return <span className={`status-chip status-${status.kind}`}>{status.text}</span>;
}

const MomentCard = observer(function MomentCard({
  moment, status, bestMatch, onOpen, onContextMenu,
}: {
  moment: Moment;
  status: MomentStatus | null;
  bestMatch?: boolean;
  onOpen: () => void;
  onContextMenu: (e: React.MouseEvent) => void;
}) {
  const h = momentHost(moment);
  return (
    <button className={`moment-card ${bestMatch ? 'is-best' : ''} ${status?.kind === 'fading' ? 'is-fading' : ''}`} onClick={onOpen} onContextMenu={onContextMenu} aria-label={`${moment.title}, ${h}`}>
      <span className="moment-preview-wrap">
        <MomentPreview moment={moment} className="moment-preview" />
        {bestMatch ? (
          <span className="preview-badge accent-fill">Best match</span>
        ) : moment.scrollFraction > 0.03 ? (
          <span className="preview-badge">{Math.round(moment.scrollFraction * 100)}% down</span>
        ) : null}
      </span>
      <span className="moment-body">
        <span className="secondary small truncate">
          {h} · {savedLabel(moment.createdAt)}
        </span>
        {moment.selectedText ? <span className="moment-selection highlight">{moment.selectedText}</span> : <span className="moment-title">{moment.title || h}</span>}
        <span className={`moment-note ${moment.note ? '' : 'tertiary'}`}>{moment.note || 'No reason given'}</span>
        {status && <StatusChip status={status} />}
      </span>
    </button>
  );
});

const Timeline = observer(function Timeline({
  moments, site, groups, browser, onContextMenu,
}: {
  moments: Moment[];
  site: string | null;
  groups: boolean;
  browser: BrowserModel;
  onContextMenu: (m: Moment) => (e: React.MouseEvent) => void;
}) {
  const now = new Date();
  const sections: { title: string; moments: Moment[] }[] = [];
  for (const m of moments) {
    const title = groups ? groupTitle(m.createdAt, now) : '';
    const last = sections[sections.length - 1];
    if (last && last.title === title) last.moments.push(m);
    else sections.push({ title, moments: [m] });
  }
  return (
    <div className="timeline">
      {sections.map((section) => (
        <section key={section.title || 'all'}>
          {groups && <div className="timeline-head">{section.title}</div>}
          {section.moments.map((m) => {
            const status = statusOf(m, site, now);
            return (
              <button key={m.id} className={`timeline-row ${status?.kind === 'fading' ? 'is-fading' : ''}`} onClick={() => browser.openMoment(m)} onContextMenu={onContextMenu(m)}>
                <MomentPreview moment={m} className="timeline-thumb small" />
                <span className="timeline-text">
                  <span className={`truncate-2 ${m.selectedText ? '' : 'strong'}`}>{m.selectedText ?? (m.title || momentHost(m))}</span>
                  <span className="secondary small truncate">{m.note || momentHost(m)}</span>
                  {status && <StatusChip status={status} />}
                </span>
                <span className="tertiary small tabular">{timeLabel(m.createdAt)}</span>
              </button>
            );
          })}
        </section>
      ))}
    </div>
  );
});

const ResolvedThreadDetail = observer(function ResolvedThreadDetail({ browser, threadID }: { browser: BrowserModel; threadID: string }) {
  void browser.threadListVersion;
  const record = threadStore.record(threadID);
  const menu = useContextMenu(browser);
  if (!record) return <div className="empty-shelf secondary">This thread no longer exists.</div>;
  const columns = [...record.columns].sort((a, b) => a.order - b.order);
  const saved = momentStore.moments(true).filter((m) => m.threadID === threadID);
  const when = new Date((record.resolvedAt ?? record.lastActiveAt) * 1000).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
  return (
    <>
      <header className="library-header">
        <div className="library-title">
          <h2 className="truncate">{record.customTitle ?? record.title}</h2>
          <span className="secondary small">
            Resolved {when} · {columns.length} page{columns.length === 1 ? '' : 's'}
          </span>
        </div>
        <button
          className="button danger"
          onClick={() => {
            browser.momentsShelf = 'everything';
            void threadStore.delete(record.id);
          }}
        >
          Delete
        </button>
        <button className="button primary" onClick={() => browser.reopenThread(record)}>
          Reopen Thread
        </button>
      </header>
      <div className="resolved-body">
        {record.outcome && (
          <div className="outcome">
            <span className="secondary small outcome-label">
              <BadgeCheck size={12} /> Outcome
            </span>
            <span className="outcome-text">{record.outcome}</span>
          </div>
        )}
        <div>
          <div className="secondary small section-caption">Pages</div>
          <div className="page-list">
            {columns.map((c) => (
              <button
                key={c.order}
                className="page-row"
                title="Open in the trail"
                onClick={() => {
                  browser.hideMoments();
                  browser.trail.open(c.url);
                }}
              >
                <Favicon host={hostOf(c.url)} size={16} />
                <span className="truncate" style={{ flex: 1 }}>
                  {c.title || c.url}
                </span>
                <span className="secondary small">{hostOf(c.url)}</span>
              </button>
            ))}
          </div>
        </div>
        {saved.length > 0 && (
          <div>
            <div className="secondary small section-caption">Moments saved in this thread</div>
            <div className="moment-grid inline">
              {saved.map((m) => (
                <MomentCard key={m.id} moment={m} status={statusOf(m, null)} onOpen={() => browser.openMoment(m)} onContextMenu={menu.open(() => <MomentMenu browser={browser} moment={m} />)} />
              ))}
            </div>
          </div>
        )}
      </div>
      {menu.element}
    </>
  );
});

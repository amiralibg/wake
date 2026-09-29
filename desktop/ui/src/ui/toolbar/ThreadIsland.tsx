// The thread island (ThreadIsland.swift, TrailStrip.swift, ThreadSwitcher.swift):
// the thread (opens the switcher) and its trail of columns as favicon chips.

import { observer } from 'mobx-react-lite';
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Layers, ChevronDown, Plus, Rows3 } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { chipsFor } from '../../model/live';
import { relativeTime } from '../../model/deck';
import { Favicon } from '../common/Favicon';
import { MenuItem, MenuSeparator, useContextMenu } from '../common/Menu';

const MAX_VISIBLE = 7;

export const ThreadIsland = observer(function ThreadIsland({ browser }: { browser: BrowserModel }) {
  const ref = useRef<HTMLDivElement>(null);
  const [switcher, setSwitcher] = useState<DOMRect | null>(null);
  // Narrow windows: the island gives up detail, widest first (ViewThatFits).
  const [detail, setDetail] = useState(0);
  const trail = browser.trail;
  const variants = [
    { threadWidth: 160, columnTitle: true, columns: true },
    { threadWidth: 110, columnTitle: false, columns: true },
    { threadWidth: 0, columnTitle: false, columns: true },
    { threadWidth: 0, columnTitle: false, columns: false },
  ];
  const variant = variants[detail];

  useLayoutEffect(() => {
    const el = ref.current;
    const parent = el?.parentElement;
    if (!el || !parent) return;
    const room = parent.getBoundingClientRect().width;
    const need = el.scrollWidth;
    if (need > room + 1 && detail < variants.length - 1) setDetail(detail + 1);
  });
  // Grow back when there's room again.
  useEffect(() => {
    const onResize = () => setDetail(0);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);
  useEffect(() => setDetail(0), [trail.columns.length, browser.thread.id]);

  return (
    <div className="thread-island glass capsule" ref={ref}>
      <button
        className="thread-button"
        title={variant.threadWidth ? 'Threads' : `Threads · ${browser.thread.title}`}
        onClick={() => setSwitcher(switcher ? null : ref.current!.getBoundingClientRect())}
      >
        <Layers size={13} className="secondary" />
        {variant.threadWidth > 0 && (
          <span className="thread-title truncate" style={{ maxWidth: variant.threadWidth }}>
            {browser.thread.title}
          </span>
        )}
        <ChevronDown size={10} strokeWidth={3} className="tertiary" />
      </button>
      {variant.columns && trail.columns.length > 0 && (
        <>
          <span className="toolbar-divider" />
          <TrailStrip browser={browser} showsTitle={variant.columnTitle} />
        </>
      )}
      {switcher && <ThreadSwitcher browser={browser} anchor={switcher} onClose={() => setSwitcher(null)} />}
    </div>
  );
});

const TrailStrip = observer(function TrailStrip({ browser, showsTitle }: { browser: BrowserModel; showsTitle: boolean }) {
  const trail = browser.trail;
  const columns = trail.columns;
  const focusedID = trail.focused?.id;
  const menu = useContextMenu(browser);
  // Keeps the focused column and its neighbours visible in long trails.
  let start = 0;
  let end = columns.length;
  if (columns.length > MAX_VISIBLE) {
    const focus = Math.max(0, trail.focusedIndex);
    start = Math.min(Math.max(0, focus - Math.floor(MAX_VISIBLE / 2)), columns.length - MAX_VISIBLE);
    end = start + MAX_VISIBLE;
  }
  return (
    <div className="trail-strip">
      {start > 0 && <span className="overflow-badge secondary">+{start}</span>}
      {columns.slice(start, end).map((page) => (
        <TrailChip
          key={page.id}
          page={page}
          focused={page.id === focusedID}
          showsTitle={showsTitle}
          onSelect={() => trail.focusID(page.id)}
          onContextMenu={menu.open(() => (
            <>
              {page.url && !page.isDevTools && <MenuItem onSelect={() => browser.pin(page)}>Pin as App</MenuItem>}
              {page.url && <MenuItem onSelect={() => page.url && trail.open(page.url, page)}>Duplicate Column</MenuItem>}
              <MenuSeparator />
              <MenuItem onSelect={() => trail.close(page)}>Close Column</MenuItem>
            </>
          ))}
        />
      ))}
      {end < columns.length && <span className="overflow-badge secondary">+{columns.length - end}</span>}
      {menu.element}
    </div>
  );
});

const TONE_COLORS: Record<string, string> = {
  accent: 'var(--accent)',
  good: 'var(--green)',
  bad: 'var(--red)',
  warning: 'var(--orange)',
};

const TrailChip = observer(function TrailChip({
  page, focused, showsTitle, onSelect, onContextMenu,
}: {
  page: Page;
  focused: boolean;
  showsTitle: boolean;
  onSelect: () => void;
  onContextMenu: (e: React.MouseEvent) => void;
}) {
  const chip = chipsFor(page)[0];
  const dot = chip && chip.tone !== 'neutral' ? TONE_COLORS[chip.tone] : null;
  const label = chip ? `${page.displayTitle} · ${chip.text}` : page.displayTitle;
  return (
    <button className={`trail-chip ${focused ? 'is-focused' : ''} ${focused && showsTitle ? 'has-title' : ''}`} title={label} aria-label={label} onClick={onSelect} onContextMenu={onContextMenu}>
      <span className="chip-icon">
        {page.isDevTools ? <Rows3 size={14} className="secondary" /> : <Favicon url={page.faviconURL} host={page.host} size={14} />}
        {page.isLoading && <span className="loading-dot" />}
        {dot && !page.isLoading && <span className="live-dot" style={{ background: dot }} />}
      </span>
      {focused && showsTitle && <span className="chip-title truncate">{page.displayTitle}</span>}
    </button>
  );
});

/** Rename or resolve the current thread, switch to another, or start a new one. */
const ThreadSwitcher = observer(function ThreadSwitcher({ browser, anchor, onClose }: { browser: BrowserModel; anchor: DOMRect; onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const [title, setTitle] = useState(browser.thread.customTitle ?? '');
  const [resolving, setResolving] = useState(false);
  const [outcome, setOutcome] = useState('');
  const menu = useContextMenu(browser);
  const count = browser.thread.pageCount;

  useEffect(() => {
    browser.menuOpened();
    return () => browser.menuClosed();
  }, [browser]);
  useEffect(() => {
    const down = (event: PointerEvent) => {
      if (ref.current?.contains(event.target as Node)) return;
      if ((event.target as HTMLElement).closest('.menu')) return;
      onClose();
    };
    const key = (event: KeyboardEvent) => event.key === 'Escape' && (event.stopPropagation(), onClose());
    const id = setTimeout(() => window.addEventListener('pointerdown', down, true));
    window.addEventListener('keydown', key, true);
    return () => {
      clearTimeout(id);
      window.removeEventListener('pointerdown', down, true);
      window.removeEventListener('keydown', key, true);
    };
  }, [onClose]);

  const resolve = () => {
    if (!outcome.trim()) return;
    onClose();
    void browser.resolveThread(outcome);
  };

  return createPortal(
    <div className="popover glass-strong thread-switcher" ref={ref} style={{ left: anchor.left, top: anchor.bottom + 8 }}>
      <div className="switcher-current">
        <input
          className="switcher-title"
          value={title}
          placeholder={browser.thread.title}
          aria-label="Thread name"
          onChange={(e) => {
            setTitle(e.target.value);
            browser.renameThread(e.target.value);
          }}
        />
        <div className="switcher-meta">
          <span className="secondary">{count === 1 ? '1 page' : `${count} pages`}</span>
          <span style={{ flex: 1 }} />
          {!resolving && count > 0 && (
            <button className="button small" onClick={() => setResolving(true)}>
              Resolve Thread…
            </button>
          )}
        </div>
      </div>
      <div className="popover-divider" />
      {resolving ? (
        <div className="resolve-form">
          <div className="resolve-title">What did you find out?</div>
          <input
            className="text-field"
            autoFocus
            value={outcome}
            placeholder="Booked Kōtoen for May 3–5"
            onChange={(e) => setOutcome(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') resolve();
              if (e.key === 'Escape') {
                e.stopPropagation();
                setResolving(false);
              }
            }}
          />
          <div className="secondary resolve-note">The thread closes and is kept in Moments with this line.</div>
          <div className="resolve-actions">
            <button className="button" onClick={() => setResolving(false)}>
              Cancel
            </button>
            <button className="button primary" disabled={!outcome.trim()} onClick={resolve}>
              Resolve
            </button>
          </div>
        </div>
      ) : (
        <>
          {browser.otherThreads.length === 0 ? (
            <div className="secondary switcher-empty">No other threads</div>
          ) : (
            <div className="switcher-list">
              {browser.otherThreads.map((record) => (
                <button
                  key={record.id}
                  className="switcher-row"
                  onClick={() => {
                    onClose();
                    void browser.switchToThread(record.id);
                  }}
                  onContextMenu={menu.open(() => (
                    <MenuItem danger onSelect={() => void browser.deleteThread(record.id)}>
                      Delete Thread
                    </MenuItem>
                  ))}
                >
                  <Layers size={14} className="secondary" />
                  <span className="switcher-row-text">
                    <span className="truncate switcher-row-title">{record.customTitle ?? record.title}</span>
                    <span className="secondary switcher-row-meta">
                      {record.columns.length} pages · {relativeTime(record.lastActiveAt)}
                    </span>
                  </span>
                </button>
              ))}
            </div>
          )}
          <div className="popover-divider" />
          <button
            className="switcher-new"
            title="New Thread (Ctrl+Shift+N)"
            onClick={() => {
              onClose();
              browser.newThread();
            }}
          >
            <Plus size={14} /> New Thread
          </button>
        </>
      )}
      {menu.element}
    </div>,
    document.body,
  );
});

// The toolbar (WakeToolbar.swift): three glass islands — thread + trail ·
// address (true centre) · actions — plus the window controls Windows and Linux
// need, since the window has no title bar. Empty toolbar space drags the window;
// double-click maximizes.

import { observer } from 'mobx-react-lite';
import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import {
  Plus, Bookmark, Copy, SquareArrowOutUpRight, Maximize2, Minimize2, Lock, Search, Minus, Square, X, Layers,
  ChevronDown, Wrench, Smartphone, ScanSearch, GitBranch, FolderPlus, Share2, Settings,
} from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import { host } from '../../host/host';
import { projects, projectFor, ENVIRONMENTS, ENVIRONMENT_COLORS, ENVIRONMENT_LABELS } from '../../model/developer';
import { PHONES, TABLETS, menuTitle } from '../../model/device';
import { shortcutLabel } from '../../model/keys';
import { Menu, MenuItem, MenuSeparator, MenuHeader, useContextMenu } from '../common/Menu';
import { ThreadIsland } from './ThreadIsland';
import { useWindowState } from '../window';
import './toolbar.css';

/** Below this the full dev island and a usable address bar don't both fit. */
const COMPACT_DEV_WIDTH = 1080;

export const Toolbar = observer(function Toolbar({ browser, floating = false }: { browser: BrowserModel; floating?: boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const leading = useRef<HTMLDivElement>(null);
  const trailing = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(1200);
  const [center, setCenter] = useState<{ left: number; width: number } | null>(null);
  const page = browser.webPage;

  // ToolbarLayout.swift: the address sits in the window's true centre while it
  // fits; when the sides are too uneven, in the middle of the room that's left.
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => {
      const bounds = el.getBoundingClientRect();
      setWidth(bounds.width);
      const leadingMin = leading.current?.scrollWidth ?? 0;
      const trailingWidth = trailing.current?.getBoundingClientRect().width ?? 0;
      const spacing = 12;
      const padding = 16;
      const inner = bounds.width - padding * 2;
      const side = Math.max(trailingWidth, leadingMin) + spacing;
      const ideal = 400;
      let w = Math.min(ideal, inner - side * 2);
      let mid = bounds.width / 2;
      if (w < 220) {
        const gapStart = padding + leadingMin + spacing;
        const gapEnd = bounds.width - padding - trailingWidth - spacing;
        w = Math.max(0, Math.min(ideal, gapEnd - gapStart));
        mid = gapStart + (gapEnd - gapStart) / 2;
      }
      setCenter((c) => (c && Math.abs(c.left - (mid - w / 2)) < 0.5 && Math.abs(c.width - w) < 0.5 ? c : { left: mid - w / 2, width: w }));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    if (leading.current) observer.observe(leading.current);
    if (trailing.current) observer.observe(trailing.current);
    return () => observer.disconnect();
  });

  const onDrag = (event: React.PointerEvent) => {
    if (event.button !== 0 || event.target !== event.currentTarget) return;
    if (event.detail === 2) host.send('window.toggleMaximize');
    else host.send('window.drag');
  };

  return (
    <div className={`toolbar ${floating ? 'is-floating' : ''}`} ref={ref} onPointerDown={onDrag}>
      <div className="toolbar-leading" ref={leading} onPointerDown={onDrag}>
        <ThreadIsland browser={browser} />
      </div>
      {center && center.width > 0 && (
        <div className="toolbar-center" style={{ left: center.left, width: center.width }}>
          <AddressCapsule browser={browser} />
        </div>
      )}
      <div className="toolbar-trailing" ref={trailing}>
        {page?.isDeveloperMode && <DevIsland browser={browser} compact={width < COMPACT_DEV_WIDTH} />}
        <ActionsCapsule browser={browser} />
        <WindowControls />
      </div>
    </div>
  );
});

// MARK: Address

const AddressCapsule = observer(function AddressCapsule({ browser }: { browser: BrowserModel }) {
  const page = browser.webPage;
  const project = projectFor(page?.url);
  const environment = page?.url ? project?.environment(page.url) : null;
  const label = page?.url ? page.host : 'Search or enter address';
  return (
    <div className="address glass capsule" title={page?.url ?? 'Search or enter address'}>
      {project && environment && Object.keys(project.data.origins).length > 1 && (
        <Menu
          browser={browser}
          className="env-switcher"
          title={`${project.name}: switch environment, keeping the path`}
          label={
            <span className="env-label" style={{ color: ENVIRONMENT_COLORS[environment], background: `color-mix(in srgb, ${ENVIRONMENT_COLORS[environment]} 16%, transparent)` }}>
              <span className="env-dot" style={{ background: ENVIRONMENT_COLORS[environment] }} />
              {ENVIRONMENT_LABELS[environment]}
            </span>
          }
        >
          {ENVIRONMENTS.filter((e) => project.data.origins[e]).map((e) => (
            <MenuItem key={e} checked={e === environment} onSelect={() => browser.switchEnvironment(e)}>
              {ENVIRONMENT_LABELS[e]}
            </MenuItem>
          ))}
        </Menu>
      )}
      <button className="address-button" onClick={() => browser.showPalette('currentColumn')}>
        {page?.isSecure ? <Lock size={11} strokeWidth={2.6} className="secondary" /> : <Search size={11} strokeWidth={2.6} className="secondary" />}
        <span className={`address-label truncate ${page?.url ? '' : 'secondary'}`}>{label}</span>
        <span className="address-key secondary">Ctrl+L</span>
      </button>
    </div>
  );
});

// MARK: Actions

export function ToolbarButton({ label, onClick, children, disabled, active }: { label: string; onClick: () => void; children: ReactNode; disabled?: boolean; active?: boolean }) {
  const shortcut = shortcutLabel(label.split(':')[0]);
  return (
    <button className={`icon-button ${active ? 'is-active' : ''}`} title={shortcut ? `${label} (${shortcut})` : label} aria-label={label} disabled={disabled} onClick={onClick}>
      {children}
    </button>
  );
}

const ActionsCapsule = observer(function ActionsCapsule({ browser }: { browser: BrowserModel }) {
  const page = browser.webPage;
  const isWeb = !!page?.url && /^https?:/.test(page.url);
  const moments = useContextMenu(browser);
  return (
    <div className="actions glass capsule">
      <ToolbarButton label="New Column" onClick={() => browser.showPalette('newColumn')}>
        <Plus size={16} />
      </ToolbarButton>
      <span
        onContextMenu={moments.open(() => (
          <>
            <MenuItem onSelect={() => browser.showMoments()} shortcut={shortcutLabel('Moments')}>
              Show Moments
            </MenuItem>
            <MenuItem onSelect={() => browser.showMoments('relevant')}>Moments Relevant Here</MenuItem>
          </>
        ))}
      >
        <ToolbarButton label="Save Moment" onClick={() => void browser.saveMoment()} disabled={!isWeb}>
          <Bookmark size={15} />
        </ToolbarButton>
      </span>
      {moments.element}
      <ToolbarButton label="Pop Out Element: pick part of the page to float it, live" onClick={() => browser.togglePopOutPicker()} disabled={!page?.url} active={page?.isPickingPopOut}>
        <SquareArrowOutUpRight size={15} />
      </ToolbarButton>
      <Menu browser={browser} className="icon-button" title="Share" label={<Share2 size={15} />} disabled={!page?.url}>
        <MenuItem onSelect={() => browser.copyPageURL()} icon={<Copy size={13} />}>
          Copy Address
        </MenuItem>
        <MenuItem onSelect={() => page?.url && host.send('open.external', { url: `mailto:?subject=${encodeURIComponent(page.displayTitle)}&body=${encodeURIComponent(page.url)}` })}>
          Email Link
        </MenuItem>
        <MenuItem onSelect={() => page?.url && host.send('open.external', { url: page.url })}>Open in Default Browser</MenuItem>
      </Menu>
      <ToolbarButton label={browser.isZen ? 'Leave Zen' : 'Zen: hide everything but pages'} onClick={() => browser.setZen(!browser.isZen)}>
        {browser.isZen ? <Minimize2 size={15} /> : <Maximize2 size={15} />}
      </ToolbarButton>
      <ToolbarButton label="Settings" onClick={() => browser.showSettings()}>
        <Settings size={15} />
      </ToolbarButton>
    </div>
  );
});

// MARK: Developer

const DevIsland = observer(function DevIsland({ browser, compact }: { browser: BrowserModel; compact: boolean }) {
  const page = browser.webPage!;
  const log = page.devtools;
  return (
    <div className="dev-island glass capsule">
      <BranchLabel browser={browser} compact={compact} />
      {log.hmr.state !== 'none' && (
        <span className={`hmr-badge ${log.hmr.state}`} title={log.hmr.state === 'connected' ? `${log.hmr.kind} connected` : `${log.hmr.kind} disconnected`}>
          <span className="hmr-dot" />
          {!compact && log.hmr.kind}
        </span>
      )}
      <span className="toolbar-divider" />
      <span className="badge-anchor">
        <ToolbarButton label="DevTools" onClick={() => browser.toggleDevTools()}>
          <Wrench size={15} />
        </ToolbarButton>
        {log.errorCount > 0 && <span className="count-badge">{Math.min(log.errorCount, 99)}</span>}
      </span>
      <Menu browser={browser} className="icon-button" title="Responsive preview" label={<Smartphone size={15} />}>
        <MenuHeader>Phones</MenuHeader>
        {PHONES.map((p) => (
          <MenuItem key={p.name} onSelect={() => browser.openResponsivePreview(p)}>
            {menuTitle(p)}
          </MenuItem>
        ))}
        <MenuSeparator />
        <MenuHeader>Tablets</MenuHeader>
        {TABLETS.map((p) => (
          <MenuItem key={p.name} onSelect={() => browser.openResponsivePreview(p)}>
            {menuTitle(p)}
          </MenuItem>
        ))}
      </Menu>
      <ToolbarButton label="Inspect Components" onClick={() => browser.toggleComponentInspector()} active={page.isInspectingComponents}>
        <ScanSearch size={15} />
      </ToolbarButton>
    </div>
  );
});

/** The project's checked-out branch, refreshed every few seconds; or "Link folder". */
const BranchLabel = observer(function BranchLabel({ browser, compact }: { browser: BrowserModel; compact: boolean }) {
  const page = browser.webPage!;
  const project = projectFor(page.url);
  const [branch, setBranch] = useState<string | null>(null);
  const folder = project?.data.folderPath;
  useLayoutEffect(() => {
    if (!project || !folder) return;
    let live = true;
    const read = async () => {
      const b = await projects.gitBranch(project.data);
      if (live) setBranch(b);
    };
    void read();
    const id = setInterval(read, 3000);
    return () => {
      live = false;
      clearInterval(id);
    };
  }, [project?.data.id, folder]);

  if (project && folder) {
    return (
      <span className="branch-label" title={compact ? `${branch ?? '—'} · ${folder}` : folder}>
        <GitBranch size={13} />
        {!compact && <span className="truncate">{branch ?? '—'}</span>}
      </span>
    );
  }
  return (
    <button
      className="branch-label link"
      title="Link this project's folder to see its git branch and open files in your editor"
      onClick={() => {
        const base = project?.data ?? (page.url ? projects.makeProject(page.url) : null);
        if (base) void projects.chooseFolder(base);
      }}
    >
      <FolderPlus size={13} />
      {!compact && 'Link folder'}
    </button>
  );
});

// MARK: Window

export const WindowControls = observer(function WindowControls() {
  const state = useWindowState();
  return (
    <div className="window-controls">
      <button className="window-button" title="Minimize" aria-label="Minimize" onClick={() => host.send('window.minimize')}>
        <Minus size={14} />
      </button>
      <button className="window-button" title={state.maximized ? 'Restore' : 'Maximize'} aria-label="Maximize" onClick={() => host.send('window.toggleMaximize')}>
        {state.maximized ? <Layers size={12} /> : <Square size={11} />}
      </button>
      <button className="window-button close" title="Close window" aria-label="Close window" onClick={() => host.send('window.closeRequest')}>
        <X size={15} />
      </button>
    </div>
  );
});

export { ChevronDown };

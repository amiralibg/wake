// The app capsule and the pinned-app panel (AppCapsule.swift, AppPanel.swift,
// DevServerIcon.swift): pinned web apps with unread badges, local dev servers,
// and Moments, in a slim glass capsule on the left. A pinned app opens in a large
// card beside the capsule, over the trail.

import { observer } from 'mobx-react-lite';
import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Pin, Bookmark, Zap, Triangle, BookOpen, Server, Network, Circle } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { PinnedApp } from '../../model/apps';
import type { DevServer, Framework } from '../../model/developer';
import { momentStore, rules } from '../../model/moments';
import { Metrics } from '../../model/geometry';
import { host } from '../../host/host';
import { Favicon } from '../common/Favicon';
import { MenuItem, MenuSeparator, useContextMenu } from '../common/Menu';
import { LoadingLine } from '../stage/PageCard';
import type { LayoutEngine } from '../stage/engine';
import { usePresence } from '../motion';
import './apps.css';

export const AppCapsule = observer(function AppCapsule({ browser }: { browser: BrowserModel }) {
  const [hovering, setHovering] = useState(false);
  const menu = useContextMenu(browser);
  const { mounted, visible } = usePresence(browser.showsAppCapsule && !browser.isOnboarding, 220);
  if (!mounted) return null;
  const apps = browser.apps.apps;
  const servers = browser.devServers;
  const page = browser.webPage;
  const pinnable = page?.url && /^https?:/.test(page.url) && !browser.apps.isPinned(page.url) ? page : null;
  const showsPin = !!pinnable && (hovering || servers.length === 0);
  const top = browser.isZen && !browser.isChromeRevealed ? Metrics.stageInset : Metrics.toolbarHeight + 4;

  return (
    <div
      className={`app-capsule glass capsule ${visible ? 'is-visible' : ''} ${browser.capsuleFloats ? 'is-floating' : ''}`}
      style={{ top }}
      onPointerEnter={() => {
        setHovering(true);
        browser.capsuleHovered(true);
      }}
      onPointerLeave={() => {
        setHovering(false);
        browser.capsuleHovered(false);
      }}
    >
      {apps.map((app, index) => (
        <AppIcon
          key={app.id}
          app={app}
          active={browser.apps.activeID === app.id}
          title={index < 9 ? `${app.title} (Alt+${index + 1})` : app.title}
          onClick={() => browser.toggleApp(app)}
          onContextMenu={menu.open(() => (
            <>
              <MenuItem onSelect={() => app.page.reload()}>Reload</MenuItem>
              <MenuItem onSelect={() => browser.trail.open(app.page.url ?? app.url)}>Open in Trail</MenuItem>
              <MenuSeparator />
              <MenuItem danger onSelect={() => browser.unpin(app)}>
                Unpin
              </MenuItem>
            </>
          ))}
        />
      ))}
      {showsPin && pinnable && (
        <button className="capsule-pin" title={`Pin ${pinnable.host} here as an app (Ctrl+Shift+P)`} aria-label={`Pin ${pinnable.host} as an app`} onClick={() => browser.pin(pinnable)}>
          <Pin size={13} strokeWidth={2.4} />
        </button>
      )}
      {servers.length > 0 && (
        <>
          {(apps.length > 0 || showsPin) && <span className="capsule-divider" />}
          {servers.map((server) => (
            <DevServerIcon
              key={server.port}
              server={server}
              onClick={() => browser.openDevServer(server)}
              onContextMenu={menu.open(() => (
                <>
                  <MenuItem onSelect={() => browser.openDevServer(server)}>Open</MenuItem>
                  <MenuItem onSelect={() => host.send('clipboard.write', { text: server.url })}>Copy URL</MenuItem>
                </>
              ))}
            />
          ))}
        </>
      )}
      {(apps.length > 0 || showsPin || servers.length > 0) && <span className="capsule-divider" />}
      <MomentsButton browser={browser} />
      {menu.element}
    </div>
  );
});

const AppIcon = observer(function AppIcon({
  app, active, title, onClick, onContextMenu,
}: {
  app: PinnedApp;
  active: boolean;
  title: string;
  onClick: () => void;
  onContextMenu: (e: React.MouseEvent) => void;
}) {
  const badge = app.badge;
  return (
    <button
      className={`app-icon ${active ? 'is-active' : ''}`}
      title={title}
      aria-label={badge ? `${app.title}, ${badge} unread` : app.title}
      onClick={onClick}
      onContextMenu={onContextMenu}
    >
      <span className="app-tile">
        <Favicon url={app.page.faviconURL ?? `https://${app.host}/favicon.ico`} host={app.host} size={18} />
      </span>
      {badge && <span className="app-badge">{badge > 99 ? '99+' : badge}</span>}
    </button>
  );
});

const FRAMEWORK: Record<Framework, { icon: typeof Zap; tint: string }> = {
  Vite: { icon: Zap, tint: 'linear-gradient(135deg, #8a5cf6, #6d3ee6)' },
  'Next.js': { icon: Triangle, tint: 'linear-gradient(135deg, #2a2a2a, #111)' },
  Storybook: { icon: BookOpen, tint: 'linear-gradient(135deg, #ff5a8c, #ff3a74)' },
  Angular: { icon: Circle, tint: 'linear-gradient(135deg, #e33245, #c21830)' },
  Django: { icon: Server, tint: 'linear-gradient(135deg, #0f6b44, #0b4f33)' },
  Rails: { icon: Server, tint: 'linear-gradient(135deg, #d4231f, #b01414)' },
  Express: { icon: Network, tint: 'linear-gradient(135deg, #9a9aa0, #7a7a80)' },
  Server: { icon: Network, tint: 'linear-gradient(135deg, #9a9aa0, #7a7a80)' },
};

function DevServerIcon({ server, onClick, onContextMenu }: { server: DevServer; onClick: () => void; onContextMenu: (e: React.MouseEvent) => void }) {
  const { icon: Icon, tint } = FRAMEWORK[server.framework];
  return (
    <button
      className={`dev-server ${server.isRunning ? '' : 'is-stopped'}`}
      title={`${server.framework} · localhost:${server.port}${server.isRunning ? '' : ' (stopped)'}\n${server.title}`}
      aria-label={`${server.framework} on port ${server.port}, ${server.isRunning ? 'running' : 'stopped'}`}
      onClick={onClick}
      onContextMenu={onContextMenu}
    >
      <span className="dev-server-tile" style={{ background: tint }}>
        <Icon size={11} strokeWidth={2.6} />
        <span className="dev-server-port">{server.port}</span>
      </span>
      <span className="dev-server-dot" />
    </button>
  );
}

/** Opens Moments; a count shows what's waiting (resurfacing, changed) or saved on this site. */
const MomentsButton = observer(function MomentsButton({ browser }: { browser: BrowserModel }) {
  const now = new Date();
  const moments = momentStore.moments();
  const waiting = moments.filter((m) => rules.isResurfacing(m, now) || m.changedAt != null).length;
  const relevant = moments.filter((m) => rules.isRelevant(m, browser.momentsHost)).length;
  const parts = ['Moments (Ctrl+Shift+B)'];
  if (waiting) parts.push(`${waiting} resurfacing or changed`);
  if (relevant && browser.momentsHost) parts.push(`${relevant} saved on ${browser.momentsHost}`);
  return (
    <button
      className={`moments-button ${browser.isMomentsOpen ? 'is-active' : ''}`}
      title={parts.join(' · ')}
      aria-label="Moments"
      onClick={() => (relevant > 0 && waiting === 0 ? browser.showMoments('relevant') : browser.showMoments())}
    >
      <Bookmark size={15} fill={browser.isMomentsOpen ? 'currentColor' : 'none'} />
      {(waiting > 0 || relevant > 0) && <span className={`moments-count ${waiting ? 'is-waiting' : ''}`}>{waiting || relevant}</span>}
    </button>
  );
});

/** The showing pinned app: a large card beside the capsule, over the trail. */
export const AppPanel = observer(function AppPanel({ browser, engine }: { browser: BrowserModel; engine: LayoutEngine }) {
  const app = browser.apps.active;
  const { mounted, visible } = usePresence(!!app, 220);
  const [shown, setShown] = useState<PinnedApp | null>(app);
  const card = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (app) setShown(app);
  }, [app]);

  // The app's webview sits on the card once it has slid in.
  useLayoutEffect(() => {
    const page = app?.page;
    if (!page || !visible) {
      if (shown) engine.setExtra('app', null);
      return;
    }
    const place = () => {
      const r = card.current?.getBoundingClientRect();
      if (r) engine.setExtra('app', { page, rect: { x: r.left, y: r.top, w: r.width, h: r.height } });
    };
    const id = setTimeout(place, 230);
    window.addEventListener('resize', place);
    return () => {
      clearTimeout(id);
      window.removeEventListener('resize', place);
      engine.setExtra('app', null);
    };
  }, [app, visible, engine, shown]);

  if (!mounted || !shown) return null;
  const left = 8 + Metrics.capsuleWidth + 10;
  const top = (browser.isZen ? Metrics.stageInset : Metrics.toolbarHeight + 4);
  return (
    <div className={`app-panel-layer ${visible ? 'is-visible' : ''}`} onPointerDown={() => browser.dismissOverlays()}>
      <div
        ref={card}
        className="app-panel card"
        style={{ left, top, bottom: Metrics.stageInset, width: `min(1100px, calc((100vw - ${left}px) * 0.72))` }}
        onPointerDown={(e) => e.stopPropagation()}
      >
        {shown.page.snapshot && <img className="card-snapshot" src={shown.page.snapshot} alt="" />}
        <LoadingLine progress={shown.page.progress} loading={shown.page.isLoading} />
      </div>
    </div>
  );
});

// DevTools as a trail column beside the page it inspects (DevToolsColumn.swift):
// Elements, Console, Network, Sources, Storage and Performance, a Tools menu of
// page overrides, and a button for the engine's own inspector.

import { observer } from 'mobx-react-lite';
import { useLayoutEffect, useRef, useState } from 'react';
import { Code2, Terminal, Network, FileText, Database, Gauge, Trash2, Wrench, SquareArrowOutUpRight, X } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { inspector, TABS, USER_AGENTS, type Tab } from '../../model/devtools-session';
import { isFailure } from '../../model/devtools-log';
import { PHONES, TABLETS, menuTitle } from '../../model/device';
import { settings } from '../../model/settings';
import { host } from '../../host/host';
import { Menu, MenuHeader, MenuItem, MenuSeparator, SubMenu } from '../common/Menu';
import { ElementsPane } from './ElementsPane';
import { ConsolePane } from './ConsolePane';
import { NetworkPane } from './NetworkPane';
import { SourcesPane } from './SourcesPane';
import { StoragePane } from './StoragePane';
import { PerformancePane } from './PerformancePane';
import { HMRBadge } from './common';
import './devtools.css';

const TAB_INFO: Record<Tab, { title: string; icon: typeof Code2 }> = {
  elements: { title: 'Elements', icon: Code2 },
  console: { title: 'Console', icon: Terminal },
  network: { title: 'Network', icon: Network },
  sources: { title: 'Sources', icon: FileText },
  storage: { title: 'Storage', icon: Database },
  performance: { title: 'Performance', icon: Gauge },
};

export const DevToolsColumn = observer(function DevToolsColumn({ page, browser }: { page: Page; browser: BrowserModel }) {
  const target = page.inspectedPage;
  if (!target) return <div className="devtools" />;
  const session = inspector(target);
  return (
    <div className="devtools">
      <Header target={target} browser={browser} onClose={() => browser.trail.close(page)} />
      <div className="devtools-body">
        {session.tab === 'elements' && <ElementsPane page={target} browser={browser} />}
        {session.tab === 'console' && <ConsolePane page={target} browser={browser} />}
        {session.tab === 'network' && <NetworkPane page={target} browser={browser} />}
        {session.tab === 'sources' && <SourcesPane page={target} browser={browser} />}
        {session.tab === 'storage' && <StoragePane page={target} browser={browser} />}
        {session.tab === 'performance' && <PerformancePane page={target} />}
      </div>
    </div>
  );
});

const Header = observer(function Header({ target, browser, onClose }: { target: Page; browser: BrowserModel; onClose: () => void }) {
  const session = inspector(target);
  const log = target.devtools;
  const ref = useRef<HTMLDivElement>(null);
  const [titles, setTitles] = useState(true);
  // Titles while they fit; icons (with tooltips) in a narrow column.
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const check = () => setTitles(el.getBoundingClientRect().width > 560);
    check();
    const observer = new ResizeObserver(check);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const badge = (tab: Tab): [string, string] | null => {
    if (tab === 'console') {
      if (log.errorCount) return [String(log.errorCount), 'var(--red)'];
      if (log.warningCount) return [String(log.warningCount), 'var(--orange)'];
    }
    if (tab === 'network') {
      const failures = log.network.filter(isFailure).length;
      if (failures) return [String(failures), 'var(--red)'];
    }
    return null;
  };

  return (
    <div className="devtools-header" ref={ref}>
      <div className="devtools-tabs">
        {TABS.map((tab) => {
          const { title, icon: Icon } = TAB_INFO[tab];
          const b = badge(tab);
          return (
            <button key={tab} className={`devtools-tab ${session.tab === tab ? 'is-selected' : ''}`} title={title} aria-label={title} onClick={() => session.setTab(tab)}>
              <Icon size={12} />
              {titles && <span>{title}</span>}
              {b && (
                <span className="tab-badge" style={{ background: b[1] }}>
                  {b[0]}
                </span>
              )}
            </button>
          );
        })}
      </div>
      <HMRBadge log={log} />
      {(session.tab === 'console' || session.tab === 'network') && (
        <button
          className="icon-button small"
          title="Clear"
          onClick={() => {
            if (session.tab === 'console') log.clearConsole();
            else {
              log.clearNetwork();
              session.clearResources();
            }
          }}
        >
          <Trash2 size={12} />
        </button>
      )}
      <ToolsMenu target={target} browser={browser} />
      {settings.webInspectorEnabled && (
        <button className="icon-button small" title="Open the engine's own inspector: debugger, profiler, layers (F12)" onClick={() => host.send('page.inspector', { page: target.id })}>
          <SquareArrowOutUpRight size={12} />
        </button>
      )}
      <button className="icon-button small" title="Close DevTools (Ctrl+Shift+I)" onClick={onClose}>
        <X size={13} />
      </button>
    </div>
  );
});

/** Page overrides and one-off actions, like Safari's Develop menu. */
const ToolsMenu = observer(function ToolsMenu({ target, browser }: { target: Page; browser: BrowserModel }) {
  const session = inspector(target);
  const copy = (text: string) => host.send('clipboard.write', { text });
  return (
    <Menu browser={browser} className="icon-button small" title="Tools: emulation, page overrides, caches, screenshots" label={<Wrench size={12} />} minWidth={240}>
      <MenuHeader>Inspect</MenuHeader>
      <MenuItem disabled={!settings.webInspectorEnabled} onSelect={() => host.send('page.inspector', { page: target.id })}>
        Engine Inspector
      </MenuItem>
      <MenuItem
        onSelect={() => {
          session.setTab('elements');
          session.setPicking(true);
        }}
      >
        Pick Element in Page
      </MenuItem>
      <MenuSeparator />
      <MenuHeader>Emulate</MenuHeader>
      <SubMenu label="Appearance">
        {(['system', 'light', 'dark'] as const).map((scheme) => (
          <MenuItem
            key={scheme}
            checked={session.colorScheme === scheme}
            onSelect={() => void session.setColorScheme(scheme).then((ok) => !ok && browser.showToast('This engine can’t override the color scheme for one page.'))}
          >
            {scheme[0].toUpperCase() + scheme.slice(1)}
          </MenuItem>
        ))}
      </SubMenu>
      <SubMenu label="User Agent">
        <MenuItem checked={session.userAgent == null} onSelect={() => session.setUserAgent(null)}>
          Default (Wake)
        </MenuItem>
        <MenuSeparator />
        {USER_AGENTS.map((ua) => (
          <MenuItem key={ua.id} checked={session.userAgent === ua.value} onSelect={() => session.setUserAgent(ua.value)}>
            {ua.title}
          </MenuItem>
        ))}
      </SubMenu>
      <SubMenu label="Preview on Device">
        {[...PHONES, ...TABLETS].map((p) => (
          <MenuItem key={p.name} onSelect={() => browser.openResponsivePreview(p)}>
            {menuTitle(p)}
          </MenuItem>
        ))}
      </SubMenu>
      <MenuSeparator />
      <MenuHeader>Page</MenuHeader>
      <MenuItem checked={target.isJavaScriptDisabled} onSelect={() => session.setJavaScriptDisabled(!target.isJavaScriptDisabled)}>
        Disable JavaScript
      </MenuItem>
      <MenuItem checked={session.stylesDisabled} onSelect={() => session.setStylesDisabled(!session.stylesDisabled)}>
        Disable Styles
      </MenuItem>
      <MenuItem checked={session.outlinesShown} onSelect={() => session.setOutlines(!session.outlinesShown)}>
        Show Layout Outlines
      </MenuItem>
      <MenuItem checked={session.designMode} onSelect={() => session.setDesignMode(!session.designMode)}>
        Edit Page Text
      </MenuItem>
      <MenuItem
        checked={target.isDeveloperMode}
        onSelect={() => {
          target.setDeveloperModeOverride(!target.isDeveloperMode);
          target.reload();
        }}
      >
        Developer Mode
      </MenuItem>
      <MenuSeparator />
      <MenuHeader>Caches</MenuHeader>
      <MenuItem onSelect={() => target.reloadFromOrigin()}>Reload Without Cache</MenuItem>
      <MenuItem onSelect={() => browser.emptyCaches()}>Empty Caches</MenuItem>
      <MenuItem onSelect={() => void session.clearSiteData()}>Clear Site Data and Reload</MenuItem>
      <MenuSeparator />
      <MenuHeader>Capture</MenuHeader>
      <MenuItem
        onSelect={() =>
          void host.call('page.copySnapshot', { page: target.id }).then(
            () => browser.showToast('Screenshot copied'),
            () => browser.showToast('Couldn’t copy a screenshot'),
          )
        }
      >
        Copy Screenshot
      </MenuItem>
      <MenuItem onSelect={() => host.send('page.print', { page: target.id })}>Print or Save as PDF…</MenuItem>
      <MenuItem onSelect={() => void session.documentSource().then((text) => (copy(text), browser.showToast('Page source copied')))}>Copy Page Source</MenuItem>
    </Menu>
  );
});

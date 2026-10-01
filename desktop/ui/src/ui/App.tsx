// A browser window (MainWindowView.swift): backdrop, toolbar, stage, the app
// capsule, and every overlay.

import { observer } from 'mobx-react-lite';
import { useEffect, useMemo, useRef } from 'react';
import { reaction } from 'mobx';
import type { BrowserModel } from '../model/browser';
import { settings } from '../model/settings';
import { handleKeyDown, runAccelerator, syncKeys } from '../model/keys';
import { host } from '../host/host';
import { devServers } from '../model/developer';
import { Toolbar } from './toolbar/Toolbar';
import { Stage } from './stage/Stage';
import { LayoutEngine } from './stage/engine';
import { PaletteOverlay } from './palette/Palette';
import { DeckLayer } from './deck/DeckLayer';
import { SettingsOverlay } from './settings/SettingsOverlay';
import { MomentsLibrary } from './moments/MomentsLibrary';
import { SaveMomentIsland } from './moments/SaveMomentIsland';
import { AppCapsule, AppPanel } from './apps/AppCapsule';
import { ColumnModeIsland } from './islands/ColumnModeIsland';
import { Toast } from './islands/Toast';
import { ZenChrome, EdgeZones } from './islands/Zen';
import { Onboarding } from './onboarding/Onboarding';
import { ImportSheet } from './import/ImportSheet';
import { ResizeEdges, windowState } from './window';
import { usePresence } from './motion';
import './app.css';

function useTheme() {
  useEffect(
    () =>
      reaction(
        () => [settings.theme, settings.accentColor, settings.glass, settings.cornerRadius] as const,
        ([theme, accent, glass, radius]) => {
          const root = document.documentElement;
          const dark = theme === 'dark' || (theme === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
          root.dataset.theme = dark ? 'dark' : 'light';
          root.dataset.glass = glass;
          root.style.setProperty('--accent', accent);
          root.style.setProperty('--radius', `${radius}px`);
        },
        { fireImmediately: true },
      ),
    [],
  );
  useEffect(() => {
    const media = matchMedia('(prefers-color-scheme: dark)');
    const update = () => {
      if (settings.theme === 'auto') document.documentElement.dataset.theme = media.matches ? 'dark' : 'light';
    };
    media.addEventListener('change', update);
    return () => media.removeEventListener('change', update);
  }, []);
}

export const App = observer(function App({ browser }: { browser: BrowserModel }) {
  const engine = useMemo(() => new LayoutEngine(), []);
  useTheme();

  useEffect(() => {
    const disposers = [
      syncKeys(browser),
      host.on('key', ({ accel }) => runAccelerator(browser, accel)),
      host.on('window.closeRequested', () => void browser.closeWindow()),
      host.on('page.download', (p) => browser.noteDownload(p)),
      host.on('page.fullscreen', (p) => {
        const page = browser.trail.columns.find((c) => c.id === p.page) ?? null;
        browser.setFullscreen(p.on ? page : null);
      }),
      host.on('popout.openLink', ({ url }) => {
        browser.trail.open(url);
        host.send('window.focusID', { id: browser.windowID });
      }),
      reaction(
        () => settings.scansPorts,
        (on) => (on ? devServers.start() : devServers.stop()),
        { fireImmediately: true },
      ),
      reaction(
        () => windowState.focused,
        (focused) => (devServers.windowFocused = focused),
      ),
      reaction(
        () => browser.page?.displayTitle ?? browser.thread.title,
        (title) => host.send('window.title', { title: `${title} — Wake` }),
        { fireImmediately: true },
      ),
    ];
    const keydown = (event: KeyboardEvent) => handleKeyDown(browser, event);
    window.addEventListener('keydown', keydown);
    return () => {
      disposers.forEach((d) => d());
      window.removeEventListener('keydown', keydown);
      engine.dispose();
    };
  }, [browser, engine]);

  const zen = usePresence(!browser.isZen, 240);

  return (
    <div className={`window ${windowState.focused ? '' : 'is-inactive'} ${browser.isZen ? 'is-zen' : ''}`}>
      <div className="backdrop" />
      <div className="window-content">
        {zen.mounted && (
          <div className={`toolbar-slot ${zen.visible ? 'is-visible' : ''}`}>
            <Toolbar browser={browser} />
          </div>
        )}
        <Stage browser={browser} engine={engine} />
      </div>
      <AppPanel browser={browser} engine={engine} />
      <AppCapsule browser={browser} />
      {browser.isZen && <ZenChrome browser={browser} />}
      <EdgeZones browser={browser} />
      <DeckLayer browser={browser} />
      <ColumnModeIsland browser={browser} />
      <SaveMomentIsland browser={browser} />
      <MomentsLibrary browser={browser} />
      <PaletteOverlay browser={browser} />
      <SettingsOverlay browser={browser} />
      <ImportSheet browser={browser} />
      {browser.isOnboarding && <Onboarding browser={browser} />}
      <Toast browser={browser} />
      <ResizeEdges />
      <FocusKeeper browser={browser} />
    </div>
  );
});

/**
 * When the UI covers the pages it takes keyboard focus (so Esc and typing reach
 * it); when it stops covering them, focus goes back to the focused page.
 */
const FocusKeeper = observer(function FocusKeeper({ browser }: { browser: BrowserModel }) {
  const covered = useRef(false);
  useEffect(
    () =>
      reaction(
        () => browser.coversPages && !browser.isColumnModeActive,
        (covers) => {
          if (covers && !covered.current) host.send('shell.focus');
          covered.current = covers;
        },
      ),
    [browser],
  );
  return null;
});

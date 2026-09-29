// Zen mode and the window edges (ZenChrome.swift, WindowEdgeMonitor.swift).
// In Zen the toolbar lives off-screen; touching the top edge floats it in over the
// pages. The bottom edge raises the Deck; the left edge the floating app capsule.
//
// Limitation: Wake's UI only sees the pointer where no page webview is, so the
// edges are the window's margins around the pages (with Zen's gap set to None
// there's no margin left, and only shortcuts reveal the chrome).

import { observer } from 'mobx-react-lite';
import { useRef } from 'react';
import type { BrowserModel } from '../../model/browser';
import { settings } from '../../model/settings';
import { Toolbar } from '../toolbar/Toolbar';
import { usePresence } from '../motion';
import './islands.css';

export const ZenChrome = observer(function ZenChrome({ browser }: { browser: BrowserModel }) {
  const { mounted, visible } = usePresence(browser.isChromeRevealed, 240);
  const timer = useRef(0);
  if (!mounted) return null;
  return (
    <div
      className={`zen-chrome ${visible ? 'is-visible' : ''}`}
      onPointerEnter={() => clearTimeout(timer.current)}
      onPointerLeave={() => {
        clearTimeout(timer.current);
        timer.current = window.setTimeout(() => browser.concealZenChrome(), 450);
      }}
    >
      <Toolbar browser={browser} floating />
    </div>
  );
});

export const EdgeZones = observer(function EdgeZones({ browser }: { browser: BrowserModel }) {
  const covered = browser.isDeckOpen || browser.isSettingsOpen || browser.isMomentsOpen || browser.isPaletteOpen || browser.isOnboarding;
  if (covered) return null;
  return (
    <>
      {settings.deckPeeksFromEdge && <div className="edge-zone edge-bottom" onPointerEnter={() => browser.peekDeck()} />}
      {browser.isZen && !browser.isChromeRevealed && <div className="edge-zone edge-top" onPointerEnter={() => browser.revealZenChrome()} />}
      {browser.capsuleFloats && !browser.isCapsuleRevealed && <div className="edge-zone edge-left" onPointerEnter={() => browser.revealCapsule()} />}
    </>
  );
});

// The area below the toolbar: the trail of page cards (TrailView.swift,
// StageView.swift, PageCard.swift). Positions come from the LayoutEngine, which
// also places the native webviews over the cards.

import { observer } from 'mobx-react-lite';
import { reaction } from 'mobx';
import { createContext, useContext, useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { TrailGeometry, Metrics } from '../../model/geometry';
import { settings } from '../../model/settings';
import { deviceColumnWidth, DEVICE_MIN_COLUMN } from '../../model/device';
import { LayoutEngine } from './engine';
import { PageCard } from './PageCard';
import { DevToolsColumn } from '../devtools/DevToolsColumn';
import { DevicePreviewColumn, deviceContentRect } from './DevicePreviewColumn';
import { EdgeHandles } from './EdgeHandles';
import './stage.css';

export const EngineContext = createContext<LayoutEngine | null>(null);
export const useEngine = () => useContext(EngineContext)!;

/** Snapshot the pages that are showing, then let the UI cover them. */
async function snapshotThenCover(engine: LayoutEngine, cover: () => boolean) {
  const pages = engine.visiblePages();
  await Promise.race([
    Promise.all(pages.map((p) => p.takeSnapshot(Math.min(1600, Math.round(engine.stage.w))))),
    new Promise((r) => setTimeout(r, 350)),
  ]);
  if (cover()) {
    engine.covered = true;
    engine.kick();
  }
}

export const Stage = observer(function Stage({ browser, engine }: { browser: BrowserModel; engine: LayoutEngine }) {
  const ref = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ x: 0, y: 0, w: 0, h: 0 });
  const trail = browser.trail;
  const outerInset = browser.isZen ? settings.gap / 2 : Metrics.stageInset;

  // Stage size and position in the window.
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => {
      const r = el.getBoundingClientRect();
      setSize((s) => (s.x === r.left && s.y === r.top && s.w === r.width && s.h === r.height ? s : { x: r.left, y: r.top, w: r.width, h: r.height }));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    window.addEventListener('resize', measure);
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, []);

  // Covering and uncovering the pages.
  useEffect(
    () =>
      reaction(
        () => browser.coversPages,
        (covers) => {
          if (covers) void snapshotThenCover(engine, () => browser.coversPages);
          else {
            engine.covered = false;
            engine.kick();
          }
        },
        { fireImmediately: true },
      ),
    [browser, engine],
  );

  useEffect(
    () =>
      reaction(
        () => browser.fullscreenPage,
        (page) => {
          engine.fullscreen = page;
          engine.kick();
        },
      ),
    [browser, engine],
  );

  const columns = trail.columns;
  const usable = Math.max(1, size.w - outerInset * 2);

  const fraction = (page: Page): number | null => {
    if (page.device) {
      // Leaves room for the page it previews, so the two always fit side by side.
      const room = Math.max(DEVICE_MIN_COLUMN, usable - Metrics.minColumnWidth - settings.gap);
      return deviceColumnWidth(page.device, size.h, room) / usable;
    }
    const custom = trail.widthFraction(page);
    if (custom != null) return custom;
    // A page with DevTools or a preview beside it takes the rest of the stage.
    const companions = trail.companions(page);
    if (!companions.length) return null;
    const taken = companions.reduce((total, c) => total + (fraction(c) ?? 0.5) * usable + settings.gap, 0);
    const rest = usable - taken;
    return rest >= Metrics.minColumnWidth ? rest / usable : null;
  };

  const geometry = new TrailGeometry(size.w, settings.gap, outerInset, settings.columnsPerScreen, columns.map(fraction));
  trail.geometry = geometry;
  const offset =
    trail.dragOffset ?? (trail.restingOffset != null ? geometry.clamped(trail.restingOffset) : geometry.targetOffset(trail.focusedIndex, trail.focusSpan));

  // Hand the targets to the engine.
  const seen = useRef(new Set<string>());
  useLayoutEffect(() => {
    engine.stage = size;
    engine.immediate = trail.isResizing || trail.dragOffset != null;
    const targets = new Map<string, { x: number; w: number }>();
    const fresh = new Set<string>();
    columns.forEach((page, index) => {
      targets.set(page.id, { x: geometry.x(index), w: geometry.width(index) });
      if (!seen.current.has(page.id)) fresh.add(page.id);
    });
    seen.current = new Set(columns.map((c) => c.id));
    engine.clipLeft = browser.showsAppCapsule && !browser.capsuleFloats ? size.x : -Infinity;
    engine.setTargets(
      columns.map((c) => c.id),
      targets,
      offset,
      fresh,
    );
  });

  // Swipes over the glass between and around the cards.
  const onWheel = (event: React.WheelEvent) => {
    if (browser.coversPages || !columns.length) return;
    const dx = event.deltaMode === 1 ? event.deltaX * 16 : event.deltaX;
    const dy = event.deltaMode === 1 ? event.deltaY * 16 : event.deltaY;
    if (event.shiftKey && settings.shiftScrollMovesColumns && Math.abs(dy) >= Math.abs(dx)) {
      wheelStep(dy);
      return;
    }
    if (Math.abs(dx) > Math.abs(dy)) {
      browser.trailWheel({ type: 'trailPan', dx });
      clearTimeout(panEnd.current);
      panEnd.current = window.setTimeout(() => browser.trailWheel({ type: 'trailPanEnd' }), 140);
    }
  };
  const panEnd = useRef(0);
  const lastStep = useRef(0);
  const wheelStep = (dy: number) => {
    const now = performance.now();
    if (now - lastStep.current < 180) return;
    lastStep.current = now;
    browser.trailWheel({ type: 'trailStep', direction: dy > 0 ? 1 : -1 });
  };

  return (
    <EngineContext.Provider value={engine}>
      <div
        className="stage-area"
        style={{
          paddingTop: browser.isZen ? outerInset : 4,
          paddingBottom: outerInset,
          paddingLeft: browser.showsAppCapsule && !browser.capsuleFloats ? Metrics.capsuleWidth + 6 + 8 : 0,
        }}
        onWheel={onWheel}
      >
        <div className="stage" ref={ref}>
          <div className="trail">
            {columns.map((page, index) => (
              <Column key={page.id} page={page} browser={browser} index={index} engine={engine} />
            ))}
          </div>
          {columns.length > 1 && <EdgeHandles browser={browser} engine={engine} outerInset={outerInset} />}
          {!columns.length && !browser.isOnboarding && <EmptyStage browser={browser} />}
        </div>
      </div>
    </EngineContext.Provider>
  );
});

const Column = observer(function Column({ page, browser, index, engine }: { page: Page; browser: BrowserModel; index: number; engine: LayoutEngine }) {
  const ref = useRef<HTMLDivElement>(null);
  const focused = index === browser.trail.focusedIndex;
  useLayoutEffect(() => {
    engine.register(page, ref.current, page.device ? (card) => deviceContentRect(page, card) : undefined);
  });
  useEffect(() => () => engine.unregister(page), [engine, page]);
  const onFocus = () => {
    if (!focused) browser.trail.focus(index);
  };
  return (
    <div className={`column ${focused ? 'is-focused' : ''}`} ref={ref} onPointerDown={onFocus}>
      {page.isDevTools ? (
        <DevToolsColumn page={page} browser={browser} />
      ) : page.device ? (
        <DevicePreviewColumn page={page} browser={browser} />
      ) : (
        <PageCard page={page} focused={focused} onClose={() => browser.trail.close(page)} />
      )}
    </div>
  );
});

const EmptyStage = observer(function EmptyStage({ browser }: { browser: BrowserModel }) {
  return (
    <div className="empty-stage" style={{ opacity: browser.isPaletteOpen || browser.isDeckOpen ? 0 : 1 }}>
      <div className="empty-title">Wake</div>
      <button className="empty-hint secondary" onClick={() => browser.showPalette()}>
        Press Ctrl+K to go somewhere
      </button>
    </div>
  );
});

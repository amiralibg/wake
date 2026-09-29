// Column edges (ColumnEdgeHandle in TrailView.swift): drag one to make just that
// column wider or narrower — its neighbours slide, the trail scrolls; double-click
// to go back to the default width. The zones sit in the gaps between cards (the
// cards themselves are covered by native webviews), so each side of a gap belongs
// to the column it touches.

import { observer } from 'mobx-react-lite';
import { useEffect, useRef } from 'react';
import type { BrowserModel } from '../../model/browser';
import type { Edge } from '../../model/trail';
import { settings } from '../../model/settings';
import type { LayoutEngine, Rect } from './engine';

export const EdgeHandles = observer(function EdgeHandles({ browser, engine, outerInset }: { browser: BrowserModel; engine: LayoutEngine; outerInset: number }) {
  const container = useRef<HTMLDivElement>(null);
  const trail = browser.trail;
  const columns = trail.columns;

  useEffect(() => {
    const place = (rects: Map<string, Rect>) => {
      const root = container.current;
      if (!root) return;
      for (const el of root.querySelectorAll<HTMLElement>('[data-page]')) {
        const rect = rects.get(el.dataset.page!);
        if (!rect) continue;
        const leading = el.dataset.edge === 'leading';
        const x = (leading ? rect.x : rect.x + rect.w) - engine.stage.x;
        el.style.transform = `translate3d(${x}px, 0, 0)`;
      }
    };
    engine.onFrame = place;
    return () => {
      if (engine.onFrame === place) engine.onFrame = () => {};
    };
  }, [engine]);

  return (
    <div className="edge-handles" ref={container}>
      {columns.map((page, index) =>
        page.device
          ? null
          : (['leading', 'trailing'] as Edge[]).map((edge) => {
              const outside = (edge === 'leading' ? index === 0 : index === columns.length - 1) ? outerInset : settings.gap / 2;
              // Keeps clear of the window's own resize zone at the stage ends.
              const reach = Math.max(3, Math.min(outside, 12) - 1);
              return (
                <Handle
                  key={`${page.id}-${edge}`}
                  pageID={page.id}
                  edge={edge}
                  reach={reach}
                  onBegin={() => trail.beginResize(page, edge)}
                  onDrag={(delta) => trail.resize(delta)}
                  onEnd={() => trail.endResize()}
                  onReset={() => trail.resetWidth(page)}
                />
              );
            }),
      )}
    </div>
  );
});

function Handle(props: {
  pageID: string;
  edge: Edge;
  reach: number;
  onBegin: () => void;
  onDrag: (delta: number) => void;
  onEnd: () => void;
  onReset: () => void;
}) {
  const start = useRef<number | null>(null);
  const leading = props.edge === 'leading';
  return (
    <div
      className={`edge-handle ${leading ? 'leading' : 'trailing'}`}
      data-page={props.pageID}
      data-edge={props.edge}
      style={{ width: props.reach, marginLeft: leading ? -props.reach : 0 }}
      title="Drag to resize this column · double-click to reset"
      onPointerDown={(event) => {
        if (event.button !== 0) return;
        event.stopPropagation();
        (event.target as HTMLElement).setPointerCapture(event.pointerId);
        start.current = event.clientX;
      }}
      onPointerMove={(event) => {
        if (start.current == null) return;
        const delta = event.clientX - start.current;
        if (!event.currentTarget.classList.contains('is-dragging')) {
          if (Math.abs(delta) < 1) return;
          event.currentTarget.classList.add('is-dragging');
          props.onBegin();
        }
        props.onDrag(delta);
      }}
      onPointerUp={(event) => {
        if (start.current == null) return;
        start.current = null;
        if (event.currentTarget.classList.contains('is-dragging')) {
          event.currentTarget.classList.remove('is-dragging');
          props.onEnd();
        }
      }}
      onDoubleClick={props.onReset}
    >
      <div className="edge-pill" />
    </div>
  );
}

// The Deck (DeckLayer.swift, DeckCard.swift, DeckIslands.swift): threads as live
// cards. Hidden while you read; reaching the bottom edge raises a peek island;
// Ctrl+K opens it: the pages frost over, search and arrangement appear, and the
// cards fan out. Cold threads sink behind the waterline island.

import { observer } from 'mobx-react-lite';
import { useEffect, useRef, useState } from 'react';
import { Volume2 } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import {
  DeckLayout, DeckMetrics, footnote, threadThumbnails, ARRANGEMENT_LABELS, type DeckArrangement, type DeckItem, type DeckState, type Placement,
} from '../../model/deck';
import { CommandPalette } from '../palette/Palette';
import { Favicon, monogramColor } from '../common/Favicon';
import { LiveChipView } from '../common/LiveChipView';
import { Metrics } from '../../model/geometry';
import { usePresence } from '../motion';
import './deck.css';

export const DeckLayer = observer(function DeckLayer({ browser }: { browser: BrowserModel }) {
  const state: DeckState = browser.isDeckOpen ? 'open' : browser.isDeckPeeking ? 'peek' : 'hidden';
  const [width, setWidth] = useState(window.innerWidth);
  const [hovered, setHovered] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [, tick] = useState(0);
  const shown = usePresence(state !== 'hidden', 360);

  useEffect(() => {
    const onResize = () => setWidth(window.innerWidth);
    window.addEventListener('resize', onResize);
    // Heat changes with time: re-read every minute.
    const id = setInterval(() => tick((n) => n + 1), 60_000);
    return () => {
      window.removeEventListener('resize', onResize);
      clearInterval(id);
    };
  }, []);

  if (!shown.mounted) return null;

  // Typing in the Deck's search narrows the cards; matching sunk ones float up.
  const query = browser.palette.trimmedQuery.toLowerCase();
  let items = browser.deckItems;
  if (browser.isDeckOpen && query) {
    items = items
      .filter((i) => i.title.toLowerCase().includes(query) || i.host.toLowerCase().includes(query))
      .map((i) => ({ ...i, heat: Math.max(i.heat, 0.3), isSunk: false }));
  }
  const afloat = DeckLayout.fanOrder(items.filter((i) => !i.isSunk));
  const sunk = items.filter((i) => i.isSunk);
  // Before the first frame the cards stand below the edge, then rise.
  const layout = new DeckLayout(shown.visible ? state : 'hidden', width);
  const peek = layout.peekIslandSize(afloat.length);

  return (
    <div className={`deck deck-${state} ${shown.visible ? 'is-visible' : ''}`}>
      {state === 'open' && (
        <>
          <div className="deck-backdrop" style={{ top: browser.isZen ? 0 : Metrics.toolbarHeight }} onPointerDown={() => browser.hidePalette()} />
          <div className="deck-header" style={{ top: (browser.isZen ? 0 : Metrics.toolbarHeight) + 28 }}>
            <CommandPalette model={browser.palette} onChoose={(item) => browser.choose(item)} onDismiss={() => browser.hidePalette()} />
            <div className="segmented" role="radiogroup" aria-label="Arrange">
              {(Object.keys(ARRANGEMENT_LABELS) as DeckArrangement[]).map((a) => (
                <button key={a} role="radio" aria-checked={browser.deckArrangement === a} className={browser.deckArrangement === a ? 'is-selected' : ''} onClick={() => (browser.deckArrangement = a)}>
                  {ARRANGEMENT_LABELS[a]}
                </button>
              ))}
            </div>
            {!browser.palette.query && <div className="deck-hint secondary">Hotter tabs float higher. Untouched ones slowly sink.</div>}
          </div>
        </>
      )}
      {state === 'peek' && (
        <div
          className="peek-island glass-strong"
          style={{ width: peek.width, height: peek.height }}
          onPointerEnter={() => browser.holdDeckPeek()}
          onPointerLeave={() => browser.endDeckPeek()}
        >
          <div className="peek-footer">
            <strong>Deck</strong>
            <span className="secondary truncate">{sunk.length ? `${afloat.length} afloat · ${sunk.length} sunk` : `${afloat.length} afloat`}</span>
            <span style={{ flex: 1 }} />
            <button className="peek-open" onClick={() => browser.openDeck()} title="Open the Deck">
              Open <span className="secondary">Ctrl+K</span>
            </button>
          </div>
        </div>
      )}
      <div className="deck-cards" onPointerLeave={() => state === 'peek' && browser.endDeckPeek()}>
        {sunk.map((item, index) => (
          <Card key={item.id} item={item} layout={layout} placement={layout.sunkPlacement(index, sunk.length)} hovered={hovered === item.id} setHovered={setHovered} browser={browser} state={state} />
        ))}
        {afloat.map((item, rank) => (
          <Card key={item.id} item={item} layout={layout} placement={layout.placement(rank, item.heat, afloat.length)} hovered={hovered === item.id} setHovered={setHovered} browser={browser} state={state} />
        ))}
      </div>
      {state === 'open' && (
        <div className="waterline glass-strong">
          <div className="waterline-text">
            <strong>Below the waterline</strong>
            <span className="secondary">
              {sunk.length === 0 ? 'Nothing has sunk yet.' : sunk.length === 1 ? '1 tab you stopped using. Still searchable.' : `${sunk.length} tabs you stopped using. Still searchable.`}
            </span>
          </div>
          <span style={{ flex: 1 }} />
          {sunk.length > 0 && (
            <>
              <span className="secondary">Drag a card up to revive it</span>
              <button className="button capsule" onClick={() => setConfirming(true)}>
                Let them go
              </button>
            </>
          )}
        </div>
      )}
      {confirming && (
        <div className="confirm-backdrop" onPointerDown={() => setConfirming(false)}>
          <div className="confirm glass-strong" onPointerDown={(e) => e.stopPropagation()}>
            <div className="confirm-title">{sunk.length === 1 ? 'Let 1 tab go?' : `Let ${sunk.length} tabs go?`}</div>
            <div className="secondary">Threads below the waterline are closed and removed from the Deck.</div>
            <div className="confirm-actions">
              <button className="button" onClick={() => setConfirming(false)}>
                Cancel
              </button>
              <button
                className="button primary danger-fill"
                onClick={() => {
                  setConfirming(false);
                  void browser.letGo(sunk.map((s) => s.threadID));
                }}
              >
                Let Them Go
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
});

const Card = observer(function Card({
  item, layout, placement, hovered, setHovered, browser, state,
}: {
  item: DeckItem;
  layout: DeckLayout;
  placement: Placement;
  hovered: boolean;
  setHovered: (id: string | null) => void;
  browser: BrowserModel;
  state: DeckState;
}) {
  const size = layout.cardSize;
  const open = state === 'open';
  const lift = hovered ? (open ? 14 : 8) : 0;
  const rotation = hovered ? placement.rotation * 0.4 : placement.rotation;
  const drag = useRef<{ y: number; moved: boolean } | null>(null);
  return (
    <button
      className={`deck-card ${item.isActive ? 'is-active' : ''} ${item.isSunk ? 'is-sunk' : ''} ${item.heat < 0.4 ? 'is-cool' : ''}`}
      style={{
        width: size.width,
        height: size.height,
        transform: `translate(calc(-50% + ${placement.x}px), ${-(placement.bottom + lift)}px) rotate(${rotation}deg) scale(${hovered ? 1.05 : 1})`,
        zIndex: hovered ? 150 : Math.round(placement.zIndex),
        filter: item.isSunk ? 'blur(1.5px) saturate(0.3)' : undefined,
      }}
      aria-label={`${item.title}, ${footnote(item)}`}
      onPointerEnter={() => {
        if (state === 'peek') browser.holdDeckPeek();
        setHovered(item.id);
      }}
      onPointerLeave={() => setHovered(null)}
      onPointerDown={(e) => {
        drag.current = { y: e.clientY, moved: false };
        (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
      }}
      onPointerMove={(e) => {
        if (drag.current && Math.abs(e.clientY - drag.current.y) > 8) drag.current.moved = true;
      }}
      onPointerUp={(e) => {
        const d = drag.current;
        drag.current = null;
        // Drag a sunk card up to bring it back above the waterline.
        if (d?.moved) {
          if (item.isSunk && e.clientY - d.y < -50) void browser.revive(item.threadID);
          return;
        }
        browser.selectDeckItem(item);
      }}
    >
      {item.pageCount > 1 && (
        <>
          <span className="deck-ghost" style={{ inset: `-12px 10px auto 10px`, opacity: 0.5 }} />
          <span className="deck-ghost" style={{ inset: `-6px 5px auto 5px`, opacity: 0.75 }} />
        </>
      )}
      <span className={`deck-face ${open ? 'is-large' : ''}`}>
        <span className="deck-card-header">
          <Favicon host={item.host} size={open ? 14 : 12} />
          <span className="deck-card-title truncate">{item.title}</span>
          {item.chip && <DeckChipView chip={item.chip} />}
        </span>
        <Thumbnail item={item} open={open} />
        <span className="deck-card-foot secondary truncate">{footnote(item)}</span>
      </span>
    </button>
  );
});

const Thumbnail = observer(function Thumbnail({ item, open }: { item: DeckItem; open: boolean }) {
  const url = threadThumbnails.url(item.threadID);
  return (
    <span className="deck-thumb" style={{ borderRadius: open ? 8 : 6 }}>
      {url ? (
        <img src={url} alt="" draggable={false} onError={() => threadThumbnails.markMissing(item.threadID)} />
      ) : (
        <span className="deck-thumb-empty" style={{ background: `color-mix(in srgb, ${monogramColor(item.host)} 18%, transparent)` }}>
          <Favicon host={item.host} size={open ? 28 : 20} />
        </span>
      )}
    </span>
  );
});

function DeckChipView({ chip }: { chip: NonNullable<DeckItem['chip']> }) {
  switch (chip.kind) {
    case 'playing':
      return (
        <span className="chip tone-accent" title="Playing">
          <Volume2 size={10} />
        </span>
      );
    case 'unsaved':
      return <span className="chip chip-unsaved">Unsaved</span>;
    case 'live':
      return <LiveChipView chip={chip.chip} />;
  }
}

export { DeckMetrics };

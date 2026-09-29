// Shows column mode is on (ColumnModeIsland.swift): where you are in the trail
// and the keys that work.

import { observer } from 'mobx-react-lite';
import type { BrowserModel } from '../../model/browser';
import { usePresence } from '../motion';
import './islands.css';

const HINTS: [string, string][] = [
  ['h l', 'focus'],
  ['H L', 'move'],
  ['1–9', 'jump'],
  ['< > =', 'width'],
  ['x', 'close'],
  ['esc', 'done'],
];

export const ColumnModeIsland = observer(function ColumnModeIsland({ browser }: { browser: BrowserModel }) {
  const { mounted, visible } = usePresence(browser.isColumnModeActive, 200);
  if (!mounted) return null;
  const trail = browser.trail;
  return (
    <div
      className={`bottom-island column-mode glass-strong capsule ${visible ? 'is-visible' : ''}`}
      role="status"
      aria-label={`Column mode, column ${trail.focusedIndex + 1} of ${trail.columns.length}`}
    >
      {trail.columns.length <= 12 ? (
        <span className="column-dots">
          {trail.columns.map((c, i) => (
            <span key={c.id} className={`column-dot ${i === trail.focusedIndex ? 'is-focused' : ''}`} />
          ))}
        </span>
      ) : (
        <span className="column-count">
          {trail.focusedIndex + 1} / {trail.columns.length}
        </span>
      )}
      <span className="island-divider" />
      {HINTS.map(([keys, label]) => (
        <span key={keys} className="column-hint">
          <span className="hint-keys">{keys}</span>
          <span className="secondary">{label}</span>
        </span>
      ))}
    </div>
  );
});

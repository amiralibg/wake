// The palette (CommandPalette.swift, PaletteResultsList.swift, PaletteRow.swift,
// PaletteOverlay.swift): address bar, search and results in one place.

import { observer } from 'mobx-react-lite';
import { useEffect, useRef } from 'react';
import { Search } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import { itemID, type PaletteItem, type PaletteModel } from '../../model/palette';
import { settings } from '../../model/settings';
import { hostOf } from '../../model/page';
import { Favicon } from '../common/Favicon';
import { usePresence } from '../motion';
import './palette.css';

export const CommandPalette = observer(function CommandPalette({
  model, onChoose, onDismiss, className = '',
}: {
  model: PaletteModel;
  onChoose: (item: PaletteItem) => void;
  onDismiss: () => void;
  className?: string;
}) {
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const id = requestAnimationFrame(() => input.current?.focus());
    return () => cancelAnimationFrame(id);
  }, []);
  const sections = model.sections;
  const placeholder =
    model.target === 'currentColumn' ? 'Go to… (replaces this page)' : 'Search or enter address — opens a new column';
  return (
    <div className={`palette glass-strong ${className}`} onPointerDown={(e) => e.stopPropagation()}>
      <div className="palette-field">
        <Search size={17} strokeWidth={2.2} className="secondary" />
        <input
          ref={input}
          value={model.query}
          placeholder={placeholder}
          spellCheck={false}
          autoComplete="off"
          onChange={(e) => model.setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              model.moveSelection(1);
            } else if (e.key === 'ArrowUp') {
              e.preventDefault();
              model.moveSelection(-1);
            } else if (e.key === 'Enter') {
              e.preventDefault();
              const item = model.selectedItem;
              if (item) onChoose(item);
            } else if (e.key === 'Escape') {
              e.preventDefault();
              e.stopPropagation();
              onDismiss();
            } else if (e.key === 'Tab') {
              e.preventDefault();
              const item = model.selectedItem;
              if (item?.kind === 'suggestion') model.setQuery(item.text);
            }
          }}
        />
        {model.isSearching && <span className="spinner" />}
        <span className="key-hint">esc</span>
      </div>
      {sections.length > 0 && (
        <div className="palette-results">
          {sections.map((section, s) => (
            <div key={section.title ?? `s${s}`}>
              {section.title && <div className="palette-section">{section.title}</div>}
              {section.items.map((item) => (
                <PaletteRow key={itemID(item)} item={item} model={model} onChoose={onChoose} />
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
});

const PaletteRow = observer(function PaletteRow({ item, model, onChoose }: { item: PaletteItem; model: PaletteModel; onChoose: (item: PaletteItem) => void }) {
  const ref = useRef<HTMLButtonElement>(null);
  const selected = model.selectedItem ? itemID(model.selectedItem) === itemID(item) : false;
  useEffect(() => {
    if (selected) ref.current?.scrollIntoView({ block: 'nearest' });
  }, [selected]);
  const { icon, title, subtitle } = describe(item);
  return (
    <button
      ref={ref}
      className={`palette-row ${selected ? 'is-selected' : ''}`}
      onPointerMove={() => {
        if (selected) return;
        const index = model.items.findIndex((i) => itemID(i) === itemID(item));
        if (index >= 0) model.select(index);
      }}
      onClick={() => onChoose(item)}
    >
      <span className="palette-icon">{icon}</span>
      <span className="palette-text">
        <span className="palette-title truncate">{title}</span>
        {subtitle && <span className="palette-subtitle secondary">{subtitle}</span>}
      </span>
      {selected && <span className="key-hint">{item.kind === 'suggestion' && settings.braveAPIKey ? 'tab' : '↵'}</span>}
    </button>
  );
});

function describe(item: PaletteItem) {
  switch (item.kind) {
    case 'open':
      return { icon: <Favicon host={hostOf(item.url)} url={null} size={22} />, title: `Open ${hostOf(item.url) || item.url}`, subtitle: item.url };
    case 'result': {
      const h = hostOf(item.result.url);
      return {
        icon: <Favicon host={h} size={22} />,
        title: item.result.title,
        subtitle: item.result.snippet ? `${h} — ${item.result.snippet}` : h,
      };
    }
    case 'recent': {
      const h = hostOf(item.page.url);
      return { icon: <Favicon host={h} size={22} />, title: item.page.title || h, subtitle: h };
    }
    case 'suggestion':
      return { icon: <Search size={14} className="secondary" />, title: item.text, subtitle: null };
    case 'searchOnWeb':
      return {
        icon: <Favicon host={settings.searchHost} size={22} />,
        title: `Search ${settings.searchName} for “${item.query}”`,
        subtitle: null,
      };
  }
}

/** Ctrl+L: dims the page and floats the palette near the top third of the window. */
export const PaletteOverlay = observer(function PaletteOverlay({ browser }: { browser: BrowserModel }) {
  const { mounted, visible } = usePresence(browser.isPaletteOpen, 200);
  if (!mounted) return null;
  return (
    <div className={`palette-overlay ${visible ? 'is-visible' : ''}`} onPointerDown={() => browser.hidePalette()}>
      <CommandPalette model={browser.palette} onChoose={(item) => browser.choose(item)} onDismiss={() => browser.hidePalette()} className="palette-floating" />
    </div>
  );
});

// The page's scripts and stylesheets, plus the document itself (SourcesPane.swift):
// read-only with line numbers and a pretty-printer for minified files.
//
// Limitation: breakpoints and stepping need the engine's debugger; the inspector
// button in the header opens it.

import { observer } from 'mobx-react-lite';
import { useEffect, useMemo, useRef, useState } from 'react';
import { FileCode, Braces, Paintbrush, Copy, Hammer, SquareArrowOutUpRight, FileText } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { inspector, sourceGroup, sourceName, type Source } from '../../model/devtools-session';
import { openLocation } from '../../model/editor';
import { host } from '../../host/host';
import { SearchField, CodeView, Empty, prettyCode } from './common';
import { Divider } from './ElementsPane';

const DOCUMENT = '__document__';

export const SourcesPane = observer(function SourcesPane({ page, browser }: { page: Page; browser: BrowserModel }) {
  const session = inspector(page);
  const [selection, setSelection] = useState<string | null>(null);
  const [text, setText] = useState('');
  const [loading, setLoading] = useState(false);
  const [pretty, setPretty] = useState(false);
  const [filter, setFilter] = useState('');
  const [listWidth, setListWidth] = useState(170);
  const root = useRef<HTMLDivElement>(null);

  useEffect(() => {
    void session.loadSources().then(() => setSelection((s) => s ?? DOCUMENT));
  }, [session, session.documentLoads]);

  const selected = session.sources.find((s) => s.id === selection) ?? null;
  const selectedURL = selection === DOCUMENT ? page.url : selected?.url ?? null;

  useEffect(() => {
    if (!selection) return;
    let live = true;
    setLoading(true);
    const load = selection === DOCUMENT ? session.documentSource() : selected ? session.text(selected) : Promise.resolve('');
    void load.then((t) => {
      if (!live) return;
      setText(t);
      setLoading(false);
      // Minified files are one enormous line: pretty-print them by default.
      const lines = t.split('\n').length;
      setPretty(t.length > 2000 && t.length / lines > 400);
    });
    return () => {
      live = false;
    };
  }, [selection, selected?.id, session]);

  const shown = useMemo(() => (pretty ? prettyCode(text) : text), [pretty, text]);
  const q = filter.trim().toLowerCase();
  const sources = session.sources.filter((s) => !q || sourceName(s).toLowerCase().includes(q) || (s.url ?? '').toLowerCase().includes(q));
  const pageHost = (() => {
    try {
      return new URL(page.url ?? '').hostname;
    } catch {
      return '';
    }
  })();
  const groups = new Map<string, Source[]>();
  for (const s of sources) groups.set(sourceGroup(s), [...(groups.get(sourceGroup(s)) ?? []), s]);
  const ordered = [...groups].sort(([a], [b]) => (a === pageHost ? -1 : b === pageHost ? 1 : a.localeCompare(b)));
  const docName = (() => {
    try {
      return new URL(page.url ?? '').pathname.split('/').pop() || '(document)';
    } catch {
      return '(document)';
    }
  })();

  return (
    <div className="hsplit" ref={root}>
      <div className="file-list" style={{ width: listWidth }}>
        <div className="pane-toolbar">
          <SearchField value={filter} onChange={setFilter} placeholder="Filter files" />
        </div>
        <div className="dt-scroll">
          <button className={`file-row ${selection === DOCUMENT ? 'is-selected' : ''}`} onClick={() => setSelection(DOCUMENT)}>
            <FileText size={12} className="secondary" />
            <span className="truncate">{docName}</span>
          </button>
          {ordered.map(([group, items]) => (
            <div key={group}>
              <div className="file-group">{group}</div>
              {items.map((s) => (
                <button key={s.id} className={`file-row ${selection === s.id ? 'is-selected' : ''}`} title={s.url ?? sourceName(s)} onClick={() => setSelection(s.id)}>
                  {s.kind === 'script' ? <Braces size={12} className="secondary" /> : <Paintbrush size={12} className="secondary" />}
                  <span className="truncate">{sourceName(s)}</span>
                </button>
              ))}
            </div>
          ))}
        </div>
      </div>
      <Divider
        vertical
        onDrag={(x) => {
          const r = root.current?.getBoundingClientRect();
          if (r) setListWidth(Math.min(260, Math.max(110, x - r.left)));
        }}
      />
      <div className="editor-area">
        <div className="pane-toolbar">
          <span className="mono secondary small truncate" style={{ flex: 1 }}>
            {selection === DOCUMENT ? page.url : selected?.url ?? (selected ? sourceName(selected) : '')}
          </span>
          <button className={`button small ${pretty ? 'is-on' : ''}`} title="Pretty-print minified code" onClick={() => setPretty(!pretty)}>
            {'{ }'} Pretty
          </button>
          <button className="icon-button small" title="Copy" onClick={() => host.send('clipboard.write', { text })}>
            <Copy size={12} />
          </button>
          {selectedURL && (
            <>
              <button className="icon-button small" title="Open in Editor (through source maps)" onClick={() => void openLocation({ url: selectedURL, line: 1, column: 1 })}>
                <Hammer size={12} />
              </button>
              <button className="icon-button small" title="Open in a new column" onClick={() => browser.trail.open(selectedURL)}>
                <SquareArrowOutUpRight size={12} />
              </button>
            </>
          )}
        </div>
        {loading ? (
          <div className="dt-empty">
            <span className="spinner" />
          </div>
        ) : !selection ? (
          <Empty icon={<FileCode size={26} strokeWidth={1.2} className="tertiary" />} title="Pick a file" detail="Scripts and stylesheets the page loaded." />
        ) : (
          <CodeView text={shown} />
        )}
      </div>
    </div>
  );
});

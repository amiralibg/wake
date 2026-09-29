// Appears under the toolbar after Ctrl+D (SaveMomentIsland.swift). The moment is
// already saved; this island only adds the "why" and when it should come back.

import { observer } from 'mobx-react-lite';
import { useEffect, useRef, useState } from 'react';
import { Bookmark } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import { momentStore, momentHost, resurfaceDate, RESURFACE_LABELS, type Moment, type ResurfaceChoice } from '../../model/moments';
import { Metrics } from '../../model/geometry';
import { usePresence } from '../motion';
import './moments.css';

export const SaveMomentIsland = observer(function SaveMomentIsland({ browser }: { browser: BrowserModel }) {
  const moment = browser.savedMoment;
  const [shown, setShown] = useState<Moment | null>(moment);
  const { mounted, visible } = usePresence(!!moment, 200);
  useEffect(() => {
    if (moment) setShown(moment);
  }, [moment]);
  if (!mounted || !shown) return null;
  return (
    <div className={`save-island glass-strong ${visible ? 'is-visible' : ''}`} style={{ top: browser.isZen ? Metrics.stageInset : Metrics.toolbarHeight + 2 }}>
      <IslandContent key={shown.id} moment={shown} browser={browser} />
    </div>
  );
});

function IslandContent({ moment, browser }: { moment: Moment; browser: BrowserModel }) {
  const [note, setNote] = useState(moment.note ?? '');
  const [resurface, setResurface] = useState<ResurfaceChoice>('nextWeek');
  const field = useRef<HTMLTextAreaElement>(null);
  const noteRef = useRef(note);
  noteRef.current = note;

  useEffect(() => {
    requestAnimationFrame(() => field.current?.focus());
    // Esc and clicks elsewhere close the island too; keep what was typed.
    return () => saveNote(noteRef.current);
  }, []);

  function saveNote(text: string) {
    const current = momentStore.moment(moment.id);
    if (!current) return; // Undone.
    const value = text.trim() || null;
    if (current.note !== value) void momentStore.update(moment.id, { note: value });
  }

  const done = () => {
    saveNote(note);
    browser.finishSavingMoment();
  };

  return (
    <>
      <div className="save-head">
        <Bookmark size={14} fill="currentColor" className="accent" />
        <strong>Moment saved</strong>
        <span style={{ flex: 1 }} />
        <button className="link-button" onClick={() => browser.undoSaveMoment()}>
          Undo
        </button>
      </div>
      <div className="secondary truncate small">
        {momentHost(moment)} · {moment.title}
      </div>
      {moment.selectedText && <div className="save-selection highlight">{moment.selectedText}</div>}
      <textarea
        ref={field}
        className="save-note"
        rows={1}
        placeholder="Why are you saving this?"
        value={note}
        onChange={(e) => setNote(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            done();
          }
        }}
      />
      <div className="save-foot">
        <span className="secondary small">Bring it back</span>
        <select
          className="select"
          value={resurface}
          onChange={(e) => {
            const choice = e.target.value as ResurfaceChoice;
            setResurface(choice);
            void momentStore.update(moment.id, { resurfaceAt: resurfaceDate(choice, new Date(moment.createdAt * 1000)) });
          }}
        >
          {(Object.keys(RESURFACE_LABELS) as ResurfaceChoice[]).map((c) => (
            <option key={c} value={c}>
              {RESURFACE_LABELS[c]}
            </option>
          ))}
        </select>
        <span style={{ flex: 1 }} />
        <button className="button primary" onClick={done}>
          Done
        </button>
      </div>
    </>
  );
}

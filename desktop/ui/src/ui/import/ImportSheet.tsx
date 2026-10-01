// File ▸ Import from Another Browser (ImportSheet.swift): pick a browser profile
// and what to bring over.

import { observer } from 'mobx-react-lite';
import { useEffect, useState } from 'react';
import { Check, Clock, Cookie, HardDrive, Info, Loader2, Search } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import { BrowserImporter, type ImportOptions, type ImportReport } from '../../model/importer';
import { usePresence } from '../motion';
import { BrowserMark } from './BrowserMark';
import './import.css';

export const ImportSheet = observer(function ImportSheet({ browser }: { browser: BrowserModel }) {
  const { mounted, visible } = usePresence(browser.isImportingBrowserData, 200);
  if (!mounted) return null;
  return (
    <div className={`import-backdrop ${visible ? 'is-visible' : ''}`} onMouseDown={(e) => e.target === e.currentTarget && close(browser)}>
      <Sheet browser={browser} />
    </div>
  );
});

function close(browser: BrowserModel) {
  browser.isImportingBrowserData = false;
}

const Sheet = observer(function Sheet({ browser }: { browser: BrowserModel }) {
  const [importer] = useState(() => new BrowserImporter());
  useEffect(() => {
    void importer.refresh();
  }, [importer]);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && importer.phase.kind !== 'running') close(browser);
      if (e.key === 'Enter') {
        if (importer.phase.kind === 'idle' && importer.canStart) void importer.start();
        else if (importer.phase.kind === 'finished') close(browser);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [importer, browser]);

  const phase = importer.phase;
  return (
    <div className="import-sheet" role="dialog" aria-label="Import from Another Browser">
      <div>
        <h2>Import from Another Browser</h2>
        <p className="secondary">Copies what you choose into Wake. The other browser isn't changed.</p>
      </div>
      {phase.kind === 'idle' && <Chooser importer={importer} onCancel={() => close(browser)} />}
      {phase.kind === 'running' && (
        <div className="import-progress">
          <Loader2 size={16} className="spin" />
          <span className="secondary">{phase.step}</span>
        </div>
      )}
      {phase.kind === 'finished' && <Summary report={phase.report} onAnother={() => importer.reset()} onDone={() => close(browser)} />}
    </div>
  );
});

const Chooser = observer(function Chooser({ importer, onCancel }: { importer: BrowserImporter; onCancel: () => void }) {
  const selected = importer.selected;
  const option = (key: keyof ImportOptions, title: string, detail?: string) => (
    <label className="import-option">
      <input type="checkbox" checked={importer.options[key]} onChange={(e) => importer.setOption(key, e.target.checked)} />
      <span>
        <span>{title}</span>
        {detail && <span className="import-option-detail secondary">{detail}</span>}
      </span>
    </label>
  );
  return (
    <>
      <div className="import-profiles">
        {importer.profiles.length === 0 && <div className="import-empty secondary">No other browsers found.</div>}
        {importer.profiles.map((p) => (
          <button key={p.id} className={`import-profile ${p.id === importer.selection ? 'is-selected' : ''}`} onClick={() => (importer.selection = p.id)}>
            <BrowserMark browser={p.browser} />
            <span className="import-profile-title">{p.title}</span>
            {p.id === importer.selection && <Check size={14} className="accent" />}
          </button>
        ))}
      </div>
      <div className="import-options">
        {option('history', 'History')}
        {option('searches', 'Searches')}
        {option('cookies', 'Cookies', cookieNote(selected?.engine))}
        {option('siteData', 'Site storage', 'Local storage, so sites remember your settings.')}
      </div>
      <div className="import-buttons">
        <span className="spacer" />
        <button className="button" onClick={onCancel}>Cancel</button>
        <button className="button primary" disabled={!importer.canStart} onClick={() => void importer.start()}>Import</button>
      </div>
    </>
  );
});

function cookieNote(engine: string | undefined) {
  if (engine === 'firefox') return 'Keeps you signed in. Container-tab cookies stay behind.';
  return 'Keeps you signed in to sites.';
}

function Summary({ report, onAnother, onDone }: { report: ImportReport; onAnother: () => void; onDone: () => void }) {
  const n = (v: number) => v.toLocaleString();
  return (
    <>
      <div className="import-summary">
        {report.options.history && <div><Clock size={15} /> {n(report.pages)} new pages in History</div>}
        {report.options.searches && <div><Search size={15} /> {n(report.searches)} searches</div>}
        {report.options.cookies && <div><Cookie size={15} /> {n(report.cookies)} cookies</div>}
        {report.options.siteData && <div><HardDrive size={15} /> Site storage for {n(report.sites)} {report.sites === 1 ? 'site' : 'sites'}</div>}
      </div>
      {report.notes.map((note) => (
        <div key={note} className="import-note secondary">
          <Info size={14} />
          <span>{note}</span>
        </div>
      ))}
      <div className="import-buttons">
        <button className="button" onClick={onAnother}>Import Another…</button>
        <span className="spacer" />
        <button className="button primary" onClick={onDone}>Done</button>
      </div>
    </>
  );
}

/** "Brought over 1,204 pages, 88 searches and 312 cookies from Chrome." */
export function importHeadline(report: ImportReport) {
  const parts: string[] = [];
  const n = (v: number) => v.toLocaleString();
  if (report.options.history) parts.push(`${n(report.pages)} pages`);
  if (report.options.searches) parts.push(`${n(report.searches)} searches`);
  if (report.options.cookies) parts.push(`${n(report.cookies)} cookies`);
  if (report.options.siteData && report.sites > 0) parts.push(`settings for ${n(report.sites)} ${report.sites === 1 ? 'site' : 'sites'}`);
  if (!parts.length) return 'Done.';
  const list = parts.length > 1 ? `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}` : parts[0];
  return `Brought over ${list} from ${report.source}.`;
}

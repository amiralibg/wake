// What the page keeps (StoragePane.swift): local and session storage, cookies,
// IndexedDB databases, Cache Storage and service workers. Everything can be
// edited or cleared.
//
// Limitation: IndexedDB contents can't be listed from outside the page without
// knowing its schema, so databases are listed by name and version.

import { observer } from 'mobx-react-lite';
import { useEffect, useState } from 'react';
import { HardDrive, Clock, Cookie as CookieIcon, Cylinder, Archive, Cog, Plus, Minus, RefreshCw, TriangleAlert, Inbox } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { inspector, type Cookie, type DevToolsSession, type StorageItem } from '../../model/devtools-session';
import { host } from '../../host/host';
import { MenuItem, MenuSeparator, useContextMenu } from '../common/Menu';
import { SearchField, Empty, Sheet, prettyJSON } from './common';

type Kind = 'local' | 'session' | 'cookies' | 'indexedDB' | 'caches' | 'workers';
const KINDS: { id: Kind; title: string; icon: typeof HardDrive }[] = [
  { id: 'local', title: 'Local', icon: HardDrive },
  { id: 'session', title: 'Session', icon: Clock },
  { id: 'cookies', title: 'Cookies', icon: CookieIcon },
  { id: 'indexedDB', title: 'IndexedDB', icon: Cylinder },
  { id: 'caches', title: 'Caches', icon: Archive },
  { id: 'workers', title: 'Workers', icon: Cog },
];

export const StoragePane = observer(function StoragePane({ page, browser }: { page: Page; browser: BrowserModel }) {
  const session = inspector(page);
  const [kind, setKind] = useState<Kind>('local');
  const [confirming, setConfirming] = useState(false);
  useEffect(() => {
    void session.loadStorage();
  }, [session, session.documentLoads]);
  const count = (k: Kind) =>
    ({
      local: session.localItems.length,
      session: session.sessionItems.length,
      cookies: session.cookies.length,
      indexedDB: session.asyncStorage.databases.length,
      caches: session.asyncStorage.caches.length,
      workers: session.asyncStorage.workers.length,
    })[k];
  return (
    <div className="hsplit">
      <div className="file-list" style={{ width: 150 }}>
        <div className="dt-scroll">
          {KINDS.map(({ id, title, icon: Icon }) => (
            <button key={id} className={`file-row ${kind === id ? 'is-selected' : ''}`} onClick={() => setKind(id)}>
              <Icon size={12} className="secondary" />
              <span style={{ flex: 1 }}>{title}</span>
              <span className="secondary tabular">{count(id)}</span>
            </button>
          ))}
        </div>
        <button className="button small clear-site" onClick={() => setConfirming(true)}>
          Clear Site Data…
        </button>
      </div>
      <div className="editor-area">
        {kind === 'local' || kind === 'session' ? (
          <KeyValueTable session={session} browser={browser} kind={kind} items={kind === 'local' ? session.localItems : session.sessionItems} />
        ) : kind === 'cookies' ? (
          <CookiesTable session={session} browser={browser} />
        ) : kind === 'indexedDB' ? (
          <>
            {session.blockedDatabase && (
              <div className="warning-banner">
                <TriangleAlert size={13} color="var(--yellow)" />
                <span>“{session.blockedDatabase}” is open in the page, so the engine deletes it once the page closes it.</span>
                <button
                  className="button small"
                  onClick={() => {
                    session.blockedDatabase = null;
                    page.reload();
                  }}
                >
                  Reload to Finish
                </button>
              </div>
            )}
            <SimpleList empty="No IndexedDB databases" rows={session.asyncStorage.databases.map((d) => [d.name, `version ${d.version}`])} onAction={(name) => void session.deleteDatabase(name)} />
          </>
        ) : kind === 'caches' ? (
          <SimpleList empty="No caches" rows={session.asyncStorage.caches.map((c) => [c.name, `${c.count} ${c.count === 1 ? 'entry' : 'entries'}`])} onAction={(name) => void session.deleteCache(name)} />
        ) : (
          <SimpleList empty="No service workers" rows={session.asyncStorage.workers.map((w) => [w.scope, `${w.state} · ${w.script}`])} action="Unregister" onAction={(scope) => void session.unregisterWorker(scope)} />
        )}
      </div>
      {confirming && (
        <div className="confirm-backdrop" onPointerDown={() => setConfirming(false)}>
          <div className="confirm glass-strong" onPointerDown={(e) => e.stopPropagation()}>
            <div className="confirm-title">Clear everything {page.host} stores?</div>
            <div className="secondary">Cookies, storage, caches, databases and service workers for this site. You’ll be signed out.</div>
            <div className="confirm-actions">
              <button className="button" onClick={() => setConfirming(false)}>
                Cancel
              </button>
              <button
                className="button primary danger-fill"
                onClick={() => {
                  setConfirming(false);
                  void session.clearSiteData();
                }}
              >
                Clear and Reload
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
});

const sizeLabel = (length: number) => (length < 1024 ? `${length} B` : `${(length / 1024).toFixed(1)} KB`);

const KeyValueTable = observer(function KeyValueTable({ session, browser, kind, items }: { session: DevToolsSession; browser: BrowserModel; kind: 'local' | 'session'; items: StorageItem[] }) {
  const [selection, setSelection] = useState<string | null>(null);
  const [editing, setEditing] = useState<{ original: string | null; key: string; value: string } | null>(null);
  const [filter, setFilter] = useState('');
  const menu = useContextMenu(browser);
  const q = filter.trim().toLowerCase();
  const rows = items.filter((i) => !q || i.key.toLowerCase().includes(q) || i.value.toLowerCase().includes(q));
  const selected = items.find((i) => i.key === selection);
  return (
    <>
      <div className="pane-toolbar">
        <SearchField value={filter} onChange={setFilter} />
        <button className="icon-button small" title="Add item" onClick={() => setEditing({ original: null, key: '', value: '' })}>
          <Plus size={12} />
        </button>
        <button className="icon-button small" title="Delete selected" disabled={!selection} onClick={() => selection && void session.removeStorage(kind, selection)}>
          <Minus size={12} />
        </button>
        <button className="icon-button small" title="Refresh" onClick={() => void session.loadStorage()}>
          <RefreshCw size={11} />
        </button>
        <button className="button small" disabled={!items.length} onClick={() => void session.clearStorage(kind)}>
          Clear
        </button>
      </div>
      <div className="table">
        <div className="table-head">
          <span style={{ flex: '1 1 40%' }}>Key</span>
          <span style={{ flex: '1 1 60%' }}>Value</span>
          <span style={{ width: 56, textAlign: 'right' }}>Size</span>
        </div>
        <div className="dt-scroll">
          {rows.map((item) => (
            <div
              key={item.key}
              className={`table-row ${selection === item.key ? 'is-selected' : ''}`}
              onClick={() => setSelection(item.key)}
              onDoubleClick={() => setEditing({ original: item.key, key: item.key, value: item.value })}
              onContextMenu={menu.open(() => (
                <>
                  <MenuItem onSelect={() => setEditing({ original: item.key, key: item.key, value: item.value })}>Edit…</MenuItem>
                  <MenuItem onSelect={() => host.send('clipboard.write', { text: item.value })}>Copy Value</MenuItem>
                  <MenuSeparator />
                  <MenuItem danger onSelect={() => void session.removeStorage(kind, item.key)}>
                    Delete
                  </MenuItem>
                </>
              ))}
            >
              <span className="mono truncate" style={{ flex: '1 1 40%' }}>{item.key}</span>
              <span className="mono truncate" style={{ flex: '1 1 60%' }}>{item.value}</span>
              <span className="secondary tabular" style={{ width: 56, textAlign: 'right' }}>{sizeLabel(item.length)}</span>
            </div>
          ))}
        </div>
      </div>
      {selected && <pre className="value-preview selectable">{prettyJSON(selected.value)}</pre>}
      {menu.element}
      {editing && (
        <ValueEditor
          title={editing.original == null ? 'Add Item' : 'Edit Item'}
          name={editing.key}
          value={editing.value}
          onClose={() => setEditing(null)}
          onSave={async (key, value) => {
            const original = editing.original;
            setEditing(null);
            if (original != null && original !== key) await session.removeStorage(kind, original);
            await session.setStorage(kind, key, value);
          }}
        />
      )}
    </>
  );
});

const CookiesTable = observer(function CookiesTable({ session, browser }: { session: DevToolsSession; browser: BrowserModel }) {
  const id = (c: Cookie) => `${c.domain}|${c.path}|${c.name}`;
  const [selection, setSelection] = useState<string | null>(null);
  const [editing, setEditing] = useState<Cookie | null | 'new'>(null);
  const menu = useContextMenu(browser);
  const selected = session.cookies.find((c) => id(c) === selection) ?? null;
  return (
    <>
      <div className="pane-toolbar">
        <span className="secondary small">{session.cookies.length} cookies</span>
        <span style={{ flex: 1 }} />
        <button className="icon-button small" title="Add cookie" onClick={() => setEditing('new')}>
          <Plus size={12} />
        </button>
        <button className="icon-button small" title="Delete selected" disabled={!selected} onClick={() => selected && void session.deleteCookie(selected)}>
          <Minus size={12} />
        </button>
        <button className="icon-button small" title="Refresh" onClick={() => void session.loadCookies()}>
          <RefreshCw size={11} />
        </button>
        <button className="button small" disabled={!session.cookies.length} onClick={() => void session.clearCookies()}>
          Clear
        </button>
      </div>
      <div className="table">
        <div className="table-head">
          <span style={{ flex: '1 1 22%' }}>Name</span>
          <span style={{ flex: '1 1 30%' }}>Value</span>
          <span style={{ flex: '1 1 18%' }}>Domain</span>
          <span style={{ width: 40 }}>Path</span>
          <span style={{ flex: '1 1 16%' }}>Expires</span>
          <span style={{ flex: '1 1 14%' }}>Flags</span>
        </div>
        <div className="dt-scroll">
          {session.cookies.map((c) => (
            <div
              key={id(c)}
              className={`table-row ${selection === id(c) ? 'is-selected' : ''}`}
              onClick={() => setSelection(id(c))}
              onDoubleClick={() => setEditing(c)}
              onContextMenu={menu.open(() => (
                <>
                  <MenuItem onSelect={() => setEditing(c)}>Edit…</MenuItem>
                  <MenuItem onSelect={() => host.send('clipboard.write', { text: c.value })}>Copy Value</MenuItem>
                  <MenuSeparator />
                  <MenuItem danger onSelect={() => void session.deleteCookie(c)}>
                    Delete
                  </MenuItem>
                </>
              ))}
            >
              <span className="mono truncate" style={{ flex: '1 1 22%' }}>{c.name}</span>
              <span className="mono truncate" style={{ flex: '1 1 30%' }}>{c.value}</span>
              <span className="truncate small" style={{ flex: '1 1 18%' }}>{c.domain}</span>
              <span className="truncate small" style={{ width: 40 }}>{c.path}</span>
              <span className="truncate small" style={{ flex: '1 1 16%' }}>{c.expires ? new Date(c.expires * 1000).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }) : 'Session'}</span>
              <span className="truncate small secondary" style={{ flex: '1 1 14%' }}>{[c.httpOnly && 'HttpOnly', c.secure && 'Secure', c.sameSite].filter(Boolean).join(' ')}</span>
            </div>
          ))}
        </div>
      </div>
      {menu.element}
      {editing && (
        <ValueEditor
          title={editing === 'new' ? 'Add Cookie' : 'Edit Cookie'}
          name={editing === 'new' ? '' : editing.name}
          value={editing === 'new' ? '' : editing.value}
          onClose={() => setEditing(null)}
          onSave={(name, value) => {
            const old = editing === 'new' ? null : editing;
            setEditing(null);
            void session.setCookie(name, value, old);
          }}
        />
      )}
    </>
  );
});

function SimpleList({ empty, rows, action = 'Delete', onAction }: { empty: string; rows: [string, string][]; action?: string; onAction: (name: string) => void }) {
  if (!rows.length) return <Empty icon={<Inbox size={26} strokeWidth={1.2} className="tertiary" />} title={empty} />;
  return (
    <div className="dt-scroll">
      {rows.map(([name, detail]) => (
        <div key={name} className="simple-row">
          <div className="simple-text">
            <span className="mono selectable">{name}</span>
            <span className="secondary small truncate">{detail}</span>
          </div>
          <button className="button small danger" onClick={() => onAction(name)}>
            {action}
          </button>
        </div>
      ))}
    </div>
  );
}

function ValueEditor({ title, name, value, onSave, onClose }: { title: string; name: string; value: string; onSave: (name: string, value: string) => void; onClose: () => void }) {
  const [key, setKey] = useState(name);
  const [text, setText] = useState(value);
  return (
    <Sheet title={title} onClose={onClose}>
      <input className="text-field mono" placeholder="Name" value={key} onChange={(e) => setKey(e.target.value)} autoFocus />
      <textarea className="code-editor" value={text} spellCheck={false} onChange={(e) => setText(e.target.value)} />
      <div className="confirm-actions">
        <button className="button" style={{ marginRight: 'auto' }} onClick={() => setText(prettyJSON(text))}>
          Format JSON
        </button>
        <button className="button" onClick={onClose}>
          Cancel
        </button>
        <button className="button primary" disabled={!key.trim()} onClick={() => onSave(key.trim(), text)}>
          Save
        </button>
      </div>
    </Sheet>
  );
}

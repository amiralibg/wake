// The console (ConsolePane.swift): the page's messages with filters, "open in
// editor" through source maps, "Copy for AI", and a JavaScript prompt.

import { observer } from 'mobx-react-lite';
import { useEffect, useRef, useState } from 'react';
import { OctagonX, TriangleAlert, Info, Circle, ChevronRight, CornerDownLeft, ListFilter, MessageSquare } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { inspector, type DevToolsSession } from '../../model/devtools-session';
import { componentOf, fileName, firstFrame, isFailure, pathAndQuery, type ConsoleEntry, type ConsoleLevel } from '../../model/devtools-log';
import { settings } from '../../model/settings';
import { openLocation } from '../../model/editor';
import { host } from '../../host/host';
import { Menu, MenuItem, MenuSeparator, useContextMenu } from '../common/Menu';
import { SearchField, CaptureBanner, Empty } from './common';

type Filter = 'All' | 'Errors' | 'Warnings' | 'Info' | 'Logs';
const includes = (filter: Filter, level: ConsoleLevel) =>
  filter === 'All' ||
  (filter === 'Errors' && level === 'error') ||
  (filter === 'Warnings' && level === 'warn') ||
  (filter === 'Info' && level === 'info') ||
  (filter === 'Logs' && ['log', 'debug', 'input', 'result'].includes(level));

export const ConsolePane = observer(function ConsolePane({ page, browser }: { page: Page; browser: BrowserModel }) {
  const log = page.devtools;
  const [filter, setFilter] = useState<Filter>('All');
  const [search, setSearch] = useState('');
  const timestamps = settings.get<boolean>('devtools.console.timestamps', false);
  const list = useRef<HTMLDivElement>(null);
  const q = search.trim().toLowerCase();
  const entries = log.console.filter((e) => includes(filter, e.level) && (!q || e.message.toLowerCase().includes(q)));
  const lastID = entries[entries.length - 1]?.id;

  useEffect(() => {
    const el = list.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [lastID]);

  const label = (f: Filter) => (f === 'Errors' && log.errorCount ? `Errors ${log.errorCount}` : f === 'Warnings' && log.warningCount ? `Warnings ${log.warningCount}` : f);

  return (
    <div className="pane">
      <div className="pane-toolbar">
        <div className="segmented small">
          {(['All', 'Errors', 'Warnings', 'Info', 'Logs'] as Filter[]).map((f) => (
            <button key={f} className={filter === f ? 'is-selected' : ''} onClick={() => setFilter(f)}>
              {label(f)}
            </button>
          ))}
        </div>
        <SearchField value={search} onChange={setSearch} />
        <Menu browser={browser} className="icon-button small" title="Console options" label={<ListFilter size={13} />}>
          <MenuItem checked={timestamps} onSelect={() => settings.set('devtools.console.timestamps', !timestamps)}>
            Show Timestamps
          </MenuItem>
          <MenuItem checked={log.preservesLog} onSelect={() => (log.preservesLog = !log.preservesLog)}>
            Preserve Log on Navigation
          </MenuItem>
        </Menu>
      </div>
      {!page.isDeveloperMode && <CaptureBanner page={page} />}
      {entries.length === 0 ? (
        <Empty
          icon={<MessageSquare size={26} strokeWidth={1.2} className="tertiary" />}
          title={log.console.length ? 'Nothing matches' : 'No messages'}
          detail={log.console.length ? 'Try another filter.' : 'Console output from the page appears here. Type JavaScript below to run it in the page.'}
        />
      ) : (
        <div className="console-list" ref={list}>
          {entries.map((entry) => (
            <ConsoleRow key={entry.id} entry={entry} page={page} browser={browser} timestamps={timestamps} />
          ))}
        </div>
      )}
      <Prompt session={inspector(page)} />
    </div>
  );
});

const TINT: Partial<Record<ConsoleLevel, string>> = { error: 'var(--red)', warn: 'var(--orange)', input: 'var(--accent)' };

function LevelIcon({ level }: { level: ConsoleLevel }) {
  const color = TINT[level] ?? 'var(--text-3)';
  switch (level) {
    case 'error':
      return <OctagonX size={12} color={color} />;
    case 'warn':
      return <TriangleAlert size={12} color={color} />;
    case 'info':
      return <Info size={12} color={color} />;
    case 'input':
      return <ChevronRight size={12} color={color} strokeWidth={3} />;
    case 'result':
      return <CornerDownLeft size={11} color={color} />;
    default:
      return <Circle size={5} fill={color} color={color} />;
  }
}

const ConsoleRow = observer(function ConsoleRow({ entry, page, browser, timestamps }: { entry: ConsoleEntry; page: Page; browser: BrowserModel; timestamps: boolean }) {
  const [expanded, setExpanded] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const menu = useContextMenu(browser);
  const source = firstFrame(entry.stack);
  const open = async () => {
    if (!source) return;
    setStatus('Resolving…');
    const ok = await openLocation(source);
    setStatus(ok ? null : 'Link the project folder to open files');
  };
  const copyForAI = () => {
    host.send('clipboard.write', { text: aiReport(entry, page) });
    setStatus('Copied');
  };
  return (
    <div
      className={`console-row level-${entry.level}`}
      onClick={() => setExpanded(!expanded)}
      onContextMenu={menu.open(() => (
        <>
          {source && <MenuItem onSelect={() => void open()}>Open in Editor</MenuItem>}
          <MenuItem onSelect={copyForAI}>Copy for AI</MenuItem>
          <MenuSeparator />
          <MenuItem onSelect={() => host.send('clipboard.write', { text: entry.message })}>Copy Message</MenuItem>
        </>
      ))}
    >
      <span className="console-icon">
        <LevelIcon level={entry.level} />
      </span>
      <div className="console-body">
        <div className={`console-message selectable ${expanded ? '' : 'clamped'}`}>{entry.message}</div>
        {expanded && entry.stack && <pre className="console-stack selectable">{entry.stack}</pre>}
        <div className="console-meta">
          {source && (
            <button
              className="link-button"
              title="Open in Editor"
              onClick={(e) => {
                e.stopPropagation();
                void open();
              }}
            >
              {fileName(source)}:{source.line}
            </button>
          )}
          {status && <span className="secondary">{status}</span>}
          <span style={{ flex: 1 }} />
          {timestamps && <span className="tertiary mono">{entry.date.toLocaleTimeString(undefined, { hour12: false, fractionalSecondDigits: 3 } as Intl.DateTimeFormatOptions)}</span>}
          {(entry.level === 'error' || entry.level === 'warn') && (
            <button
              className="link-button copy-ai"
              onClick={(e) => {
                e.stopPropagation();
                copyForAI();
              }}
            >
              Copy for AI
            </button>
          )}
        </div>
      </div>
      {entry.repeatCount > 1 && (
        <span className="repeat" style={{ background: TINT[entry.level] ?? '#8e8e93' }}>
          {entry.repeatCount}
        </span>
      )}
      {menu.element}
    </div>
  );
});

/** "Copy for AI": the error, where it happened, the component, and the failing request around it. */
function aiReport(entry: ConsoleEntry, page: Page) {
  const first = entry.message.split('\n')[0];
  const lines = [`## ${entry.level === 'warn' ? 'Warning' : 'Error'}: ${first}`, ''];
  if (page.url) lines.push(`- **Page:** ${page.url}`);
  const component = componentOf(entry);
  if (component) lines.push(`- **Component:** \`<${component}>\``);
  const source = firstFrame(entry.stack);
  if (source) {
    let path = source.url;
    try {
      path = new URL(source.url).pathname;
    } catch {}
    lines.push(`- **Location:** \`${path}:${source.line}:${source.column}\``);
  }
  const failure = [...page.devtools.network].reverse().find((n) => isFailure(n) && n.startedAt.getTime() <= entry.date.getTime() + 1000);
  if (failure) {
    lines.push(`- **Failing request:** \`${failure.method} ${pathAndQuery(failure)}\` → ${failure.status ?? 'no response'}${failure.error ? ` (${failure.error})` : ''}`);
    if (failure.responsePreview) lines.push('', 'Response:', '```', failure.responsePreview.slice(0, 1200), '```');
  }
  lines.push('', 'Message:', '```', entry.message, '```');
  if (entry.stack) lines.push('', 'Stack:', '```', entry.stack, '```');
  return lines.join('\n');
}

/** The prompt: Enter runs, Shift+Enter adds a line, ↑/↓ walk history, Tab completes. */
const Prompt = observer(function Prompt({ session }: { session: DevToolsSession }) {
  const [code, setCode] = useState('');
  const [historyIndex, setHistoryIndex] = useState<number | null>(null);
  const [completions, setCompletions] = useState<string[]>([]);
  const field = useRef<HTMLTextAreaElement>(null);

  const complete = (name: string) => {
    const match = /[\w$]*$/.exec(code);
    setCode(code.slice(0, code.length - (match?.[0].length ?? 0)) + name);
    setCompletions([]);
    field.current?.focus();
  };

  return (
    <div className="console-prompt" onClick={() => field.current?.focus()}>
      {completions.length > 0 && (
        <div className="completions">
          {completions.map((c) => (
            <button key={c} className="completion mono" onClick={() => complete(c)}>
              {c}
            </button>
          ))}
        </div>
      )}
      <div className="prompt-line">
        <ChevronRight size={11} strokeWidth={3} className="accent" />
        <textarea
          ref={field}
          rows={Math.min(8, code.split('\n').length)}
          value={code}
          spellCheck={false}
          placeholder="Run JavaScript in the page ($0 is the selected element)"
          onChange={(e) => {
            setCode(e.target.value);
            if (completions.length) setCompletions([]);
          }}
          onKeyDown={async (e) => {
            if (e.key === 'Enter' && !e.shiftKey && !e.altKey) {
              e.preventDefault();
              const input = code;
              setCode('');
              setHistoryIndex(null);
              setCompletions([]);
              await session.evaluate(input);
            } else if ((e.key === 'ArrowUp' || e.key === 'ArrowDown') && (!code.includes('\n') || historyIndex != null)) {
              const history = session.history;
              if (!history.length) return;
              e.preventDefault();
              const next = (historyIndex ?? history.length) + (e.key === 'ArrowUp' ? -1 : 1);
              if (next >= history.length) {
                setHistoryIndex(null);
                setCode('');
              } else {
                const index = Math.max(0, next);
                setHistoryIndex(index);
                setCode(history[index]);
              }
            } else if (e.key === 'Tab') {
              e.preventDefault();
              const found = await session.completions(code);
              if (found.length === 1) complete(found[0]);
              else setCompletions(found);
            }
          }}
        />
      </div>
    </div>
  );
});

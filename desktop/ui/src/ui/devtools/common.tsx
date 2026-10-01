// Small pieces shared by the DevTools panes.

import { observer } from 'mobx-react-lite';
import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { Search, XCircle, Info } from 'lucide-react';
import type { DevToolsLog } from '../../model/devtools-log';
import type { Page } from '../../model/page';
import { relativeTime } from '../../model/deck';

export function SearchField({
  value, onChange, placeholder = 'Filter', onSubmit, onStep, width,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  onSubmit?: (shift: boolean) => void;
  onStep?: (delta: number) => void;
  width?: number;
}) {
  return (
    <label className="dt-search" style={width ? { maxWidth: width } : undefined}>
      <Search size={10} className="secondary" />
      <input
        value={value}
        placeholder={placeholder}
        spellCheck={false}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') onSubmit?.(e.shiftKey);
          else if (onStep && e.key === 'ArrowUp') {
            e.preventDefault();
            onStep(-1);
          } else if (onStep && e.key === 'ArrowDown') {
            e.preventDefault();
            onStep(1);
          }
        }}
      />
      {value && (
        <button aria-label="Clear" onClick={() => onChange('')}>
          <XCircle size={11} className="secondary" />
        </button>
      )}
    </label>
  );
}

export const HMRBadge = observer(function HMRBadge({ log }: { log: DevToolsLog }) {
  if (log.hmr.state === 'none') return null;
  const connected = log.hmr.state === 'connected';
  return (
    <span className="hmr" title={log.lastHotUpdate ? `Last hot update ${relativeTime(log.lastHotUpdate.getTime() / 1000)}` : 'Hot reload'}>
      <span className="hmr-dot" style={{ background: connected ? 'var(--green)' : '#8e8e93' }} />
      <span className="secondary">{connected ? log.hmr.kind : `${log.hmr.kind} offline`}</span>
    </span>
  );
});

/** Page logs need developer mode's hooks; the prompt works without them. */
export function CaptureBanner({ page, message = 'Page logs are captured in developer mode.' }: { page: Page; message?: string }) {
  return (
    <div className="capture-banner">
      <Info size={13} className="secondary" />
      <span className="secondary">{message}</span>
      <span style={{ flex: 1 }} />
      <button
        className="button small"
        onClick={() => {
          page.setDeveloperModeOverride(true);
          page.reload();
        }}
      >
        Turn On and Reload
      </button>
    </div>
  );
}

export function Empty({ icon, title, detail }: { icon: ReactNode; title: string; detail?: string }) {
  return (
    <div className="dt-empty">
      {icon}
      <div className="dt-empty-title">{title}</div>
      {detail && <div className="secondary">{detail}</div>}
    </div>
  );
}

export function DetailSection({ title, rows }: { title: string; rows: [string, string][] }) {
  return (
    <div className="detail-section">
      <div className="detail-title">{title}</div>
      {rows.map(([k, v], i) => (
        <div key={i} className="detail-row">
          <span className="detail-key">{k}</span>
          <span className="detail-value">{v}</span>
        </div>
      ))}
    </div>
  );
}

export function DetailText({ title, text }: { title: string; text: string }) {
  return (
    <div className="detail-section">
      <div className="detail-title">{title}</div>
      <pre className="detail-pre">{text}</pre>
    </div>
  );
}

/** Pretty-printed JSON when `text` parses; otherwise `text` unchanged. */
export function prettyJSON(text: string) {
  try {
    return JSON.stringify(JSON.parse(text), null, 2);
  } catch {
    return text;
  }
}

/**
 * Read-only code with line numbers, drawn in slices (virtualized) so megabytes of
 * minified code stay responsive. Find with the filter field above it.
 */
export function CodeView({ text }: { text: string }) {
  const lines = useMemo(() => text.split('\n'), [text]);
  const ref = useRef<HTMLDivElement>(null);
  const [scroll, setScroll] = useState({ top: 0, height: 600 });
  const lineHeight = 17;
  useEffect(() => {
    ref.current?.scrollTo(0, 0);
  }, [text]);
  const first = Math.max(0, Math.floor(scroll.top / lineHeight) - 20);
  const last = Math.min(lines.length, Math.ceil((scroll.top + scroll.height) / lineHeight) + 20);
  const gutter = String(lines.length).length * 7.5 + 16;
  return (
    <div
      className="code-view"
      ref={ref}
      onScroll={(e) => {
        const el = e.currentTarget;
        setScroll({ top: el.scrollTop, height: el.clientHeight });
      }}
    >
      <div style={{ height: lines.length * lineHeight + 12, position: 'relative', minWidth: 'max-content' }}>
        {lines.slice(first, last).map((line, i) => {
          const number = first + i + 1;
          return (
            <div key={number} className="code-line" style={{ top: (number - 1) * lineHeight + 6, height: lineHeight }}>
              <span className="code-number" style={{ width: gutter }}>
                {number}
              </span>
              <span className="code-text">{line.length > 20000 ? line.slice(0, 20000) + ' …' : line}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

/** A modal sheet over the column (HTML, mocks, storage values). */
export function Sheet({ title, children, onClose }: { title: string; children: ReactNode; onClose: () => void }) {
  return (
    <div className="confirm-backdrop" onPointerDown={onClose}>
      <div className="confirm glass-strong dt-sheet" onPointerDown={(e) => e.stopPropagation()} onKeyDown={(e) => e.key === 'Escape' && (e.stopPropagation(), onClose())}>
        <div className="confirm-title">{title}</div>
        {children}
      </div>
    </div>
  );
}

/** Byte counts: "519 B", "12.4 kB". Zero means "not reported". */
export function bytes(value: number | null | undefined) {
  if (!value || value <= 0) return '—';
  if (value < 1000) return `${value} B`;
  if (value < 1_000_000) return `${(value / 1000).toFixed(1)} kB`;
  return `${(value / 1_000_000).toFixed(1)} MB`;
}

export function milliseconds(value: number) {
  return value >= 1000 ? `${(value / 1000).toFixed(2)} s` : `${Math.round(value)} ms`;
}

/** Swatches for rgb()/hex values in Computed. */
export function cssColor(value: string): string | null {
  const v = value.trim();
  if (/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(v)) return v;
  if (/^rgba?\(/.test(v)) return v;
  return null;
}

/**
 * Indents minified JavaScript and CSS for reading (CodeFormatter.swift). It tracks
 * strings, template literals and comments so it doesn't break them, but it isn't a
 * parser: regex literals containing braces can throw the indentation off.
 */
export function prettyCode(code: string): string {
  if (code.length > 3_000_000) return code;
  let out = '';
  let depth = 0;
  let quote: string | null = null;
  let lineComment = false;
  let blockComment = false;
  let parens = 0;
  let previous = ' ';
  const newline = () => {
    out = out.replace(/ +$/, '');
    if (!out.endsWith('\n')) out += '\n';
    out += '  '.repeat(Math.max(0, depth));
  };
  const continuesBlock = (rest: string) =>
    ['else', 'catch', 'finally'].some((w) => rest.startsWith(w) && !/[\w$]/.test(rest[w.length] ?? ''));
  for (let i = 0; i < code.length; i++) {
    const c = code[i];
    const next = code[i + 1];
    if (lineComment) {
      out += c;
      if (c === '\n') {
        lineComment = false;
        out += '  '.repeat(Math.max(0, depth));
      }
    } else if (blockComment) {
      out += c;
      if (c === '*' && next === '/') {
        out += '/';
        i++;
        blockComment = false;
      }
    } else if (quote) {
      out += c;
      if (c === '\\' && next !== undefined) {
        out += next;
        i++;
      } else if (c === quote) quote = null;
    } else {
      switch (c) {
        case '"':
        case "'":
        case '`':
          quote = c;
          out += c;
          break;
        case '/':
          if (next === '/' && previous !== '\\' && previous !== ':') {
            lineComment = true;
          } else if (next === '*') {
            blockComment = true;
          }
          out += c;
          break;
        case '{': {
          const hadSpace = out.endsWith(' ');
          out = out.replace(/ +$/, '');
          const last = out[out.length - 1];
          if (last && !'([\n'.includes(last) && (hadSpace || !'=:'.includes(last))) out += ' ';
          out += '{';
          depth++;
          newline();
          break;
        }
        case '}': {
          depth--;
          newline();
          out += '}';
          let j = i + 1;
          while (j < code.length && /\s/.test(code[j])) j++;
          if (continuesBlock(code.slice(j, j + 8))) {
            out += ' ';
            i = j - 1;
          } else if (j < code.length && !';,)]'.includes(code[j])) newline();
          break;
        }
        case ';':
          out += ';';
          if (parens === 0) newline();
          break;
        case '(':
          parens++;
          out += c;
          break;
        case ')':
          parens = Math.max(0, parens - 1);
          out += c;
          break;
        case '\n':
        case '\r':
          if (!out.endsWith('\n') && !out.endsWith(' ')) newline();
          break;
        default:
          if (c === ' ' && (out.endsWith(' ') || out.endsWith('\n'))) break;
          out += c;
      }
    }
    if (!/\s/.test(c)) previous = c;
  }
  return out;
}

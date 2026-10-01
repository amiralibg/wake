// The page's live DOM as a tree (ElementsPane.swift), with a picker, search,
// editing, and the selected element's styles, computed values, box model and
// attributes.

import { observer } from 'mobx-react-lite';
import { useEffect, useRef, useState } from 'react';
import { MousePointerClick, RefreshCw, ChevronUp, ChevronDown, ChevronRight, Pencil, MinusCircle, MousePointer } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { inspector, isElement, isExpandable, nodeLabel, type DOMNode, type DevToolsSession, type ElementDetails } from '../../model/devtools-session';
import { settings } from '../../model/settings';
import { host } from '../../host/host';
import { MenuItem, MenuSeparator, useContextMenu } from '../common/Menu';
import { SearchField, Empty, DetailSection, Sheet, cssColor } from './common';

type DetailTab = 'styles' | 'computed' | 'layout' | 'attributes';

export const ElementsPane = observer(function ElementsPane({ page, browser }: { page: Page; browser: BrowserModel }) {
  const session = inspector(page);
  const [search, setSearch] = useState('');
  const [searchedFor, setSearchedFor] = useState('');
  const [editing, setEditing] = useState<{ id: number; html: string } | null>(null);
  const [split, setSplit] = useState(0.55);
  const body = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!session.roots.length) void session.loadDocument();
  }, [session, session.documentLoads]);
  useEffect(() => {
    if (page.devtoolsPickRequest > 0) session.setPicking(true);
  }, [page.devtoolsPickRequest, session]);
  useEffect(
    () => () => {
      session.hover(null);
      if (session.isPicking) session.setPicking(false);
    },
    [session],
  );

  const editHTML = async (id: number) => setEditing({ id, html: await session.outerHTML(id) });

  return (
    <div className="pane">
      <div className="pane-toolbar">
        <button className={`icon-button small ${session.isPicking ? 'is-active' : ''}`} title="Select an element in the page (Esc to cancel)" onClick={() => session.setPicking(!session.isPicking)}>
          <MousePointerClick size={13} />
        </button>
        <button className="icon-button small" title="Refresh the tree" onClick={() => void session.refreshTree()}>
          <RefreshCw size={12} />
        </button>
        <SearchField
          value={search}
          onChange={setSearch}
          placeholder="Search by selector or text"
          onSubmit={(shift) => {
            // Enter again on the same query steps to the next match, like Safari.
            if (search === searchedFor && session.searchMatches.length) void session.nextMatch(shift ? -1 : 1);
            else {
              setSearchedFor(search);
              void session.search(search);
            }
          }}
          onStep={(d) => void session.nextMatch(d)}
        />
        {session.searchMatches.length > 0 && (
          <>
            <span className="secondary tabular small nowrap">
              {session.searchIndex + 1} of {session.searchMatches.length}
            </span>
            <button className="icon-button small" onClick={() => void session.nextMatch(-1)}>
              <ChevronUp size={12} />
            </button>
            <button className="icon-button small" onClick={() => void session.nextMatch(1)}>
              <ChevronDown size={12} />
            </button>
          </>
        )}
      </div>
      <div className="vsplit" ref={body}>
        <div style={{ flex: `${split} 1 0` }} className="vsplit-top">
          <ElementTree session={session} browser={browser} onEditHTML={editHTML} />
        </div>
        <Divider onDrag={(y) => {
          const r = body.current?.getBoundingClientRect();
          if (r) setSplit(Math.min(0.85, Math.max(0.15, (y - r.top) / r.height)));
        }} />
        <div style={{ flex: `${1 - split} 1 0` }} className="vsplit-bottom">
          <DetailsView session={session} onEditHTML={editHTML} />
        </div>
      </div>
      {session.details && <Breadcrumbs session={session} path={session.details.path} />}
      {editing && (
        <Sheet title="Edit as HTML" onClose={() => setEditing(null)}>
          <HTMLEditor
            html={editing.html}
            onCancel={() => setEditing(null)}
            onSave={(html) => {
              const id = editing.id;
              setEditing(null);
              void session.setOuterHTML(html, id);
            }}
          />
        </Sheet>
      )}
    </div>
  );
});

function HTMLEditor({ html, onSave, onCancel }: { html: string; onSave: (html: string) => void; onCancel: () => void }) {
  const [text, setText] = useState(html);
  return (
    <>
      <textarea className="code-editor" value={text} spellCheck={false} onChange={(e) => setText(e.target.value)} autoFocus />
      <div className="confirm-actions">
        <span className="secondary small" style={{ marginRight: 'auto' }}>
          Replaces the element in the page. Reload to undo.
        </span>
        <button className="button" onClick={onCancel}>
          Cancel
        </button>
        <button className="button primary" onClick={() => onSave(text)}>
          Apply
        </button>
      </div>
    </>
  );
}

export function Divider({ onDrag, vertical = false }: { onDrag: (position: number) => void; vertical?: boolean }) {
  const dragging = useRef(false);
  return (
    <div
      className={vertical ? 'hsplit-divider' : 'vsplit-divider'}
      onPointerDown={(e) => {
        dragging.current = true;
        e.currentTarget.setPointerCapture(e.pointerId);
      }}
      onPointerMove={(e) => dragging.current && onDrag(vertical ? e.clientX : e.clientY)}
      onPointerUp={() => (dragging.current = false)}
    />
  );
}

// MARK: Tree

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);

function Markup({ node, closing, collapsed }: { node: DOMNode; closing: boolean; collapsed: boolean }) {
  switch (node.type) {
    case 1: {
      const name = node.tag ?? '';
      if (closing) return <span className="m-tag">&lt;/{name}&gt;</span>;
      const open = (
        <>
          <span className="m-tag">&lt;{name}</span>
          {node.attributes.map((a) => (
            <span key={a.name}>
              {' '}
              <span className="m-attr">{a.name}</span>
              {a.value && (
                <>
                  <span className="secondary">="</span>
                  <span className="m-value">{a.value.length > 120 ? a.value.slice(0, 120) + '…' : a.value}</span>
                  <span className="secondary">"</span>
                </>
              )}
            </span>
          ))}
          <span className="m-tag">&gt;</span>
        </>
      );
      if (node.text != null) return (<>{open}{node.text}<span className="m-tag">&lt;/{name}&gt;</span></>);
      if (isExpandable(node) && collapsed) return (<>{open}<span className="secondary">…</span><span className="m-tag">&lt;/{name}&gt;</span></>);
      if (!isExpandable(node) && !VOID.has(name)) return (<>{open}<span className="m-tag">&lt;/{name}&gt;</span></>);
      return open;
    }
    case 3:
      return <span>"{node.text ?? ''}"</span>;
    case 8:
      return <span className="m-comment">&lt;!-- {node.text ?? ''} --&gt;</span>;
    case 10:
      return <span className="secondary">&lt;!DOCTYPE {node.text ?? 'html'}&gt;</span>;
    case 11:
      return <span className="secondary">#shadow-root ({node.text ?? 'open'})</span>;
    default:
      return <span>{node.text ?? ''}</span>;
  }
}

const ElementTree = observer(function ElementTree({ session, browser, onEditHTML }: { session: DevToolsSession; browser: BrowserModel; onEditHTML: (id: number) => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const menu = useContextMenu(browser);
  const rows = session.treeRows;

  useEffect(() => {
    if (session.selectedID == null) return;
    ref.current?.querySelector(`[data-row="${session.selectedID}"]`)?.scrollIntoView({ block: 'nearest' });
  }, [session.selectedID]);

  const move = (delta: number) => {
    const open = session.treeRows.filter((r) => !r.isClosing);
    const current = open.findIndex((r) => r.node.id === session.selectedID);
    if (current < 0) return;
    session.choose(open[Math.min(Math.max(0, current + delta), open.length - 1)].node.id);
  };

  return (
    <div
      className="dom-tree"
      ref={ref}
      tabIndex={0}
      onPointerLeave={() => session.hover(null)}
      onKeyDown={(e) => {
        const id = session.selectedID;
        if (e.key === 'ArrowUp') move(-1);
        else if (e.key === 'ArrowDown') move(1);
        else if (e.key === 'ArrowRight' && id != null) {
          // Like Safari: → on an open element steps into its first child.
          if (session.expanded.has(id)) {
            const child = session.children.get(id)?.[0];
            if (child) session.choose(child.id);
          } else void session.expand(id);
        } else if (e.key === 'ArrowLeft' && id != null) {
          if (session.expanded.has(id)) session.collapse(id);
          else {
            const parent = session.parentID(id);
            if (parent != null) session.choose(parent);
          }
        } else if ((e.key === 'Delete' || e.key === 'Backspace') && id != null) void session.remove(id);
        else return;
        e.preventDefault();
      }}
    >
      {rows.map((row) => {
        const node = row.node;
        const selected = !row.isClosing && node.id === session.selectedID;
        return (
          <div
            key={row.key}
            data-row={row.isClosing ? undefined : node.id}
            className={`dom-row ${selected ? 'is-selected' : ''} ${session.hoveredID === node.id ? 'is-hovered' : ''}`}
            style={{ paddingLeft: row.depth * 14 + 6 }}
            onPointerEnter={() => session.hover(node.id)}
            onClick={() => session.choose(node.id)}
            onDoubleClick={() => isExpandable(node) && void session.toggle(node.id)}
            onContextMenu={
              row.isClosing
                ? undefined
                : menu.open(() => (
                    <>
                      {isElement(node) && (
                        <>
                          <MenuItem onSelect={() => onEditHTML(node.id)}>Edit as HTML…</MenuItem>
                          <MenuItem onSelect={() => void session.setAttribute('data-new', '', node.id)}>Add Attribute</MenuItem>
                          <MenuSeparator />
                          <MenuItem onSelect={async () => {
                            await session.select(node.id, false);
                            host.send('clipboard.write', { text: session.details?.selector ?? '' });
                          }}>Copy Selector</MenuItem>
                          <MenuItem onSelect={async () => host.send('clipboard.write', { text: await session.outerHTML(node.id) })}>Copy HTML</MenuItem>
                          <MenuSeparator />
                          <MenuItem onSelect={() => void session.scrollIntoView(node.id)}>Scroll into View</MenuItem>
                          <MenuItem onSelect={() => void session.toggleHidden(node.id)}>Hide / Show Element</MenuItem>
                          <MenuItem onSelect={() => void session.duplicate(node.id)}>Duplicate Element</MenuItem>
                          <MenuSeparator />
                          <MenuItem onSelect={() => void session.toggle(node.id, true)}>Expand All</MenuItem>
                          <MenuItem onSelect={() => session.collapse(node.id)}>Collapse</MenuItem>
                          <MenuSeparator />
                        </>
                      )}
                      <MenuItem danger onSelect={() => void session.remove(node.id)}>
                        Delete Node
                      </MenuItem>
                    </>
                  ))
            }
          >
            {!row.isClosing && isExpandable(node) ? (
              <button
                className="disclosure"
                title="Alt-click to expand everything inside"
                onClick={(e) => {
                  e.stopPropagation();
                  void session.toggle(node.id, e.altKey);
                }}
              >
                {session.expanded.has(node.id) ? <ChevronDown size={9} strokeWidth={3} /> : <ChevronRight size={9} strokeWidth={3} />}
              </button>
            ) : (
              <span className="disclosure" />
            )}
            <span className="dom-markup">
              <Markup node={node} closing={row.isClosing} collapsed={!session.expanded.has(node.id)} />
            </span>
          </div>
        );
      })}
      {menu.element}
    </div>
  );
});

const Breadcrumbs = observer(function Breadcrumbs({ session, path }: { session: DevToolsSession; path: number[] }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    ref.current?.scrollTo({ left: ref.current.scrollWidth });
  }, [path]);
  return (
    <div className="breadcrumbs" ref={ref}>
      {path.map((id, i) => (
        <span key={id} className="crumb-wrap">
          {i > 0 && <ChevronRight size={10} className="tertiary" />}
          <button
            className={`crumb ${id === session.selectedID ? 'is-selected' : ''}`}
            onPointerEnter={() => session.hover(id)}
            onPointerLeave={() => session.hover(null)}
            onClick={() => void session.reveal(id, path.slice(0, i + 1))}
          >
            {session.node(id) ? nodeLabel(session.node(id)!) : '…'}
          </button>
        </span>
      ))}
    </div>
  );
});

// MARK: Details

const DetailsView = observer(function DetailsView({ session, onEditHTML }: { session: DevToolsSession; onEditHTML: (id: number) => void }) {
  const tab = settings.get<DetailTab>('devtools.elements.detailTab', 'styles');
  const details = session.details;
  return (
    <div className="element-details">
      <div className="pane-toolbar">
        <div className="segmented small">
          {(['styles', 'computed', 'layout', 'attributes'] as DetailTab[]).map((t) => (
            <button key={t} className={tab === t ? 'is-selected' : ''} onClick={() => settings.set('devtools.elements.detailTab', t)}>
              {t[0].toUpperCase() + t.slice(1)}
            </button>
          ))}
        </div>
        <span style={{ flex: 1 }} />
        {details && (
          <>
            <span className="mono secondary small truncate">{details.node ? nodeLabel(details.node) : ''}</span>
            <button className="icon-button small" title="Edit as HTML" onClick={() => onEditHTML(details.id)}>
              <Pencil size={11} />
            </button>
          </>
        )}
      </div>
      {details && details.node && isElement(details.node) ? (
        tab === 'styles' ? (
          <StylesView session={session} details={details} />
        ) : tab === 'computed' ? (
          <ComputedView details={details} />
        ) : tab === 'layout' ? (
          <div className="dt-scroll pad">
            <BoxModel details={details} />
          </div>
        ) : (
          <AttributesView session={session} details={details} />
        )
      ) : (
        <Empty icon={<MousePointer size={26} strokeWidth={1.2} className="tertiary" />} title="No element selected" detail="Select a node in the tree, or pick one in the page." />
      )}
    </div>
  );
});

function StylesView({ session, details }: { session: DevToolsSession; details: ElementDetails }) {
  const [inline, setInline] = useState(details.inlineStyle);
  useEffect(() => setInline(details.inlineStyle), [details.id, details.inlineStyle]);
  return (
    <div className="dt-scroll pad styles">
      <div className="rule">
        <div className="rule-selector">element.style</div>
        <textarea
          className="code-input"
          rows={2}
          value={inline}
          placeholder="color: red; margin: 0 auto"
          spellCheck={false}
          onChange={(e) => setInline(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              void session.setInlineStyle(inline, details.id);
            }
          }}
        />
        <div className="tertiary small">Enter applies to the page right away.</div>
      </div>
      {details.rules.map((rule, i) => (
        <div key={i} className="rule boxed">
          <div className="rule-head">
            <span className="rule-selector selectable">{rule.selector}</span>
            <span className="tertiary small truncate">{rule.source}</span>
          </div>
          {rule.media && <div className="mono secondary small">@media {rule.media}</div>}
          {rule.declarations.map(([name, value], j) => (
            <div key={j} className="declaration selectable">
              <span className="m-attr">{name}</span>: {value};
            </div>
          ))}
        </div>
      ))}
      {details.rules.length === 0 && <div className="secondary small">No matching rules in readable stylesheets. Cross-origin sheets can’t be read from the page.</div>}
    </div>
  );
}

/** Values that are just the initial ones make the list long and tell you little. */
const BORING = new Set(['auto', 'normal', 'none', '0px', 'initial', '0', 'visible', 'static', 'baseline', 'start']);

const ComputedView = observer(function ComputedView({ details }: { details: ElementDetails }) {
  const [filter, setFilter] = useState('');
  const all = settings.get<boolean>('devtools.elements.computedAll', false);
  const q = filter.trim().toLowerCase();
  const rows = details.computed.filter(
    ([name, value]) => (!q || name.toLowerCase().includes(q) || value.toLowerCase().includes(q)) && (all || !!q || !BORING.has(value)),
  );
  return (
    <div className="computed">
      <div className="pane-toolbar">
        <SearchField value={filter} onChange={setFilter} placeholder="Filter properties" />
        <label className="checkbox">
          <input type="checkbox" checked={all} onChange={(e) => settings.set('devtools.elements.computedAll', e.target.checked)} /> Show all
        </label>
      </div>
      <div className="dt-scroll">
        {rows.map(([name, value]) => {
          const color = cssColor(value);
          return (
            <div key={name} className="computed-row">
              <span className="m-attr computed-name">{name}</span>
              {color && <span className="swatch" style={{ background: color }} />}
              <span className="selectable">{value}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
});

function BoxModel({ details }: { details: ElementDetails }) {
  const box = details.box;
  if (!box) return null;
  const f = (v: number) => (v === 0 ? '–' : Number.isInteger(v) ? String(v) : v.toFixed(1));
  const s = (a: number[], i: number) => a[i] ?? 0;
  const width = box.width - (s(box.border, 1) + s(box.border, 3) + s(box.padding, 1) + s(box.padding, 3));
  const height = box.height - (s(box.border, 0) + s(box.border, 2) + s(box.padding, 0) + s(box.padding, 2));
  const layer = (name: string, sides: number[], color: string, inner: React.ReactNode) => (
    <div className="box-layer" style={{ background: color }}>
      <span className="box-name">{name}</span>
      <span>{f(s(sides, 0))}</span>
      <div className="box-middle">
        <span>{f(s(sides, 3))}</span>
        {inner}
        <span>{f(s(sides, 1))}</span>
      </div>
      <span>{f(s(sides, 2))}</span>
    </div>
  );
  return (
    <div className="box-model">
      {layer('margin', box.margin, '#f6b36b', layer('border', box.border, '#ffe69a', layer('padding', box.padding, '#94c47d', <span className="box-content">{f(width)} × {f(height)}</span>)))}
      <div className="box-facts">
        <span className="secondary">Position</span>
        <span className="mono">{box.position}</span>
        <span className="secondary">Display</span>
        <span className="mono">{box.display}</span>
        <span className="secondary">Box sizing</span>
        <span className="mono">{box.boxSizing}</span>
        <span className="secondary">Rendered size</span>
        <span className="mono">{f(box.width)} × {f(box.height)}</span>
        <span className="secondary">Page offset</span>
        <span className="mono">x {f(box.x)}, y {f(box.y)}</span>
      </div>
    </div>
  );
}

function AttributesView({ session, details }: { session: DevToolsSession; details: ElementDetails }) {
  const [name, setName] = useState('');
  const [value, setValue] = useState('');
  const add = () => {
    const n = name.trim();
    if (!n) return;
    void session.setAttribute(n, value, details.id);
    setName('');
    setValue('');
  };
  return (
    <div className="dt-scroll pad attributes">
      {(details.node?.attributes ?? []).map((a) => (
        <AttributeField key={a.name} name={a.name} value={a.value} onCommit={(v) => void session.setAttribute(a.name, v, details.id)} onRemove={() => void session.removeAttribute(a.name, details.id)} />
      ))}
      <div className="attr-add">
        <input className="text-field mono" placeholder="name" value={name} onChange={(e) => setName(e.target.value)} style={{ width: 110 }} />
        <input className="text-field mono" placeholder="value" value={value} onChange={(e) => setValue(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && add()} />
        <button className="button small" disabled={!name.trim()} onClick={add}>
          Add
        </button>
      </div>
      {details.selector && <DetailSection title="Selector" rows={[['CSS', details.selector]]} />}
    </div>
  );
}

function AttributeField({ name, value, onCommit, onRemove }: { name: string; value: string; onCommit: (v: string) => void; onRemove: () => void }) {
  const [text, setText] = useState(value);
  useEffect(() => setText(value), [value]);
  return (
    <div className="attr-row">
      <span className="m-attr mono truncate attr-name">{name}</span>
      <input className="text-field mono" value={text} onChange={(e) => setText(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && onCommit(text)} />
      <button className="icon-button small" title="Remove attribute" onClick={onRemove}>
        <MinusCircle size={13} />
      </button>
    </div>
  );
}

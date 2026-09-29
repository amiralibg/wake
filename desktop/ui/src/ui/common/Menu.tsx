// Menus and context menus drawn by Wake's UI. Native webviews sit above the UI,
// so while a menu is open the browser covers the pages (they show snapshots).

import { createContext, useContext, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { Check, ChevronRight } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import './menu.css';

const CloseContext = createContext<() => void>(() => {});

interface Position {
  x: number;
  y: number;
  /** Open upwards / leftwards when there's no room. */
  anchor?: DOMRect;
}

function MenuPanel({ position, onClose, children, minWidth = 200 }: { position: Position; onClose: () => void; children: ReactNode; minWidth?: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const [placed, setPlaced] = useState<{ left: number; top: number } | null>(null);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    let left = position.x;
    let top = position.y;
    if (left + r.width > window.innerWidth - 8) left = Math.max(8, (position.anchor ? position.anchor.right : window.innerWidth) - r.width);
    if (top + r.height > window.innerHeight - 8) top = Math.max(8, (position.anchor ? position.anchor.top - 4 : window.innerHeight - 8) - r.height);
    setPlaced({ left, top });
  }, [position]);

  useEffect(() => {
    const down = (event: PointerEvent) => {
      if (ref.current && !ref.current.contains(event.target as Node)) onClose();
    };
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        onClose();
      }
    };
    const blur = () => onClose();
    const id = setTimeout(() => window.addEventListener('pointerdown', down, true));
    window.addEventListener('keydown', key, true);
    window.addEventListener('blur', blur);
    return () => {
      clearTimeout(id);
      window.removeEventListener('pointerdown', down, true);
      window.removeEventListener('keydown', key, true);
      window.removeEventListener('blur', blur);
    };
  }, [onClose]);

  return createPortal(
    <CloseContext.Provider value={onClose}>
      <div
        ref={ref}
        className="menu glass-strong"
        role="menu"
        style={{ left: placed?.left ?? position.x, top: placed?.top ?? position.y, minWidth, visibility: placed ? 'visible' : 'hidden' }}
        onContextMenu={(e) => e.preventDefault()}
      >
        {children}
      </div>
    </CloseContext.Provider>,
    document.body,
  );
}

/** Tells the browser a menu is open (so it covers the pages) while mounted. */
function useCover(browser: BrowserModel | undefined, open: boolean) {
  useEffect(() => {
    if (!open || !browser) return;
    browser.menuOpened();
    return () => browser.menuClosed();
  }, [browser, open]);
}

/** A button that opens a menu below it. */
export function Menu({
  browser,
  label,
  children,
  className = 'menu-button',
  title,
  minWidth,
  disabled,
}: {
  browser?: BrowserModel;
  label: ReactNode;
  children: ReactNode;
  className?: string;
  title?: string;
  minWidth?: number;
  disabled?: boolean;
}) {
  const [position, setPosition] = useState<Position | null>(null);
  useCover(browser, !!position);
  return (
    <>
      <button
        className={className}
        title={title}
        disabled={disabled}
        aria-haspopup="menu"
        aria-expanded={!!position}
        onClick={(event) => {
          if (position) return setPosition(null);
          const r = event.currentTarget.getBoundingClientRect();
          setPosition({ x: r.left, y: r.bottom + 4, anchor: r });
        }}
      >
        {label}
      </button>
      {position && (
        <MenuPanel position={position} onClose={() => setPosition(null)} minWidth={minWidth}>
          {children}
        </MenuPanel>
      )}
    </>
  );
}

/** Right-click menus: `const menu = useContextMenu(browser); <div onContextMenu={menu.open(() => <>items</>)}>`. */
export function useContextMenu(browser?: BrowserModel) {
  const [state, setState] = useState<{ position: Position; render: () => ReactNode } | null>(null);
  useCover(browser, !!state);
  return {
    open: (render: () => ReactNode) => (event: React.MouseEvent) => {
      event.preventDefault();
      event.stopPropagation();
      setState({ position: { x: event.clientX, y: event.clientY }, render });
    },
    element: state ? (
      <MenuPanel position={state.position} onClose={() => setState(null)}>
        {state.render()}
      </MenuPanel>
    ) : null,
  };
}

export function MenuItem({
  children,
  onSelect,
  checked,
  disabled,
  danger,
  shortcut,
  icon,
}: {
  children: ReactNode;
  onSelect: () => void;
  checked?: boolean;
  disabled?: boolean;
  danger?: boolean;
  shortcut?: string;
  icon?: ReactNode;
}) {
  const close = useContext(CloseContext);
  return (
    <button
      className={`menu-item ${danger ? 'danger' : ''}`}
      role="menuitem"
      disabled={disabled}
      onClick={() => {
        close();
        onSelect();
      }}
    >
      <span className="menu-check">{checked ? <Check size={13} strokeWidth={2.5} /> : icon}</span>
      <span className="menu-label">{children}</span>
      {shortcut && <span className="menu-shortcut">{shortcut}</span>}
    </button>
  );
}

export function SubMenu({ label, children }: { label: ReactNode; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  return (
    <div className="submenu" ref={ref} onPointerEnter={() => setOpen(true)} onPointerLeave={() => setOpen(false)}>
      <div className="menu-item">
        <span className="menu-check" />
        <span className="menu-label">{label}</span>
        <ChevronRight size={12} className="secondary" />
      </div>
      {open && <div className="menu glass-strong submenu-panel">{children}</div>}
    </div>
  );
}

export const MenuSeparator = () => <div className="menu-separator" role="separator" />;

export const MenuHeader = ({ children }: { children: ReactNode }) => <div className="menu-header">{children}</div>;

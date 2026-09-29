// A Pop Out window (PopOut.swift, PopOutView.swift): a slim glass header (live
// dot, title, source, pin, close) over a live copy of the page, laid out at the
// source page's width and clipped to the picked element.
//
// Limitation (as on the Mac): an engine can't render one DOM element of a page in
// another view, so the element lives in a second copy of the page. State that
// exists only in the original tab (an unsent form, a scrolled carousel) isn't
// carried over.

import { observer } from 'mobx-react-lite';
import { useEffect, useMemo, useState } from 'react';
import { makeAutoObservable, reaction } from 'mobx';
import { Pin, X } from 'lucide-react';
import { host } from '../../host/host';
import { Page, hostOf, type PopOutPick } from '../../model/page';
import { POPOUT_HEADER, popOutScale, popOutWindowSize } from '../../model/popout';
import { settings } from '../../model/settings';
import { accelerator } from '../../model/keys';
import { windowState } from '../window';
import './popout.css';

type State = 'loading' | 'live' | 'lost';

class PopOut {
  state: State = 'loading';
  rect: { x: number; y: number; width: number; height: number };
  pinned = false;
  readonly page: Page;

  constructor(readonly pick: PopOutPick & { source: number }) {
    this.rect = { ...pick.rect };
    this.page = new Page();
    makeAutoObservable(this, { page: false, pick: false });
    const openInTrail = (url: string) => host.send('window.emit', { id: pick.source, name: 'popout.openLink', payload: { url } });
    // The popped-out copy stays on its page: links open in the trail.
    this.page.onOpenLink = (url) => openInTrail(url);
    this.page.onPopup = (popup) => {
      if (popup.requestedURL) openInTrail(popup.requestedURL);
      return false;
    };
    this.page.onPopOutMessage = (message) => this.receive(message);
    this.page.onDocument = (phase) => {
      if (phase === 'finished') this.page.fire('popout-isolate', { selector: pick.selector, channel: 'wakePopOut' });
    };
    this.page.onClose = () => this.close();
    this.page.load(pick.url);
    host.on('page.failed', (p) => p.page === this.page.id && (this.state = 'lost'));
  }

  get scale() {
    return popOutScale(this.rect);
  }

  get host() {
    return hostOf(this.pick.url);
  }

  receive(message: any) {
    switch (message?.type) {
      case 'found':
        this.state = 'live';
        break;
      case 'lost':
        this.state = 'lost';
        break;
      case 'rect': {
        const next = {
          x: typeof message.x === 'number' ? message.x : this.rect.x,
          y: this.rect.y,
          width: typeof message.w === 'number' ? message.w : this.rect.width,
          height: typeof message.h === 'number' ? message.h : this.rect.height,
        };
        if (next.width < 1 || next.height < 1) return;
        if (JSON.stringify(next) === JSON.stringify(this.rect)) return;
        this.rect = next;
        const size = popOutWindowSize(next);
        host.send('window.setSize', { width: size.width, height: size.height });
        break;
      }
    }
  }

  reload() {
    this.state = 'loading';
    this.page.reload();
  }

  togglePin() {
    this.pinned = !this.pinned;
    host.send('window.pin', { on: this.pinned });
  }

  close() {
    this.page.close();
    host.send('window.close');
  }
}

export const PopOutApp = observer(function PopOutApp({ pick }: { pick: PopOutPick & { source: number } }) {
  const popOut = useMemo(() => new PopOut(pick), [pick]);
  const [width, setWidth] = useState(window.innerWidth);

  useEffect(() => {
    const root = document.documentElement;
    const dark = settings.theme === 'dark' || (settings.theme === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
    root.dataset.theme = dark ? 'dark' : 'light';
    root.style.setProperty('--accent', settings.accentColor);
    host.send('window.title', { title: `${pick.label || pick.title} — Pop Out` });
    host.send('keys.set', { keys: ['ctrl+w'] });
    const onKey = (event: KeyboardEvent) => {
      if (accelerator(event) === 'ctrl+w') {
        event.preventDefault();
        popOut.close();
      }
    };
    const onResize = () => setWidth(window.innerWidth);
    window.addEventListener('keydown', onKey);
    window.addEventListener('resize', onResize);
    const offKey = host.on('key', ({ accel }) => accel === 'ctrl+w' && popOut.close());
    const offClose = host.on('window.closeRequested', () => popOut.close());
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('resize', onResize);
      offKey();
      offClose();
    };
  }, [popOut, pick]);

  // The element's webview: at the source page's width, offset so only the element shows.
  useEffect(
    () =>
      reaction(
        () => [popOut.rect.x, popOut.rect.height, popOut.scale, popOut.state, width] as const,
        ([x, height, scale, state]) => {
          popOut.page.setZoom(scale);
          if (state === 'lost') {
            host.send('layout', { frames: [] });
            return;
          }
          const contentWidth = Math.max(1, popOut.rect.width * scale);
          const left = Math.max(0, (width - contentWidth) / 2);
          host.send('layout', {
            frames: [{ page: popOut.page.id, x: Math.round(left - x * scale), y: POPOUT_HEADER, w: Math.round(pick.layoutWidth * scale), h: Math.round(height * scale) }],
          });
        },
        { fireImmediately: true },
      ),
    [popOut, pick, width],
  );

  const title = pick.label || pick.title;
  const color = popOut.state === 'live' ? 'var(--green)' : popOut.state === 'loading' ? 'var(--orange)' : 'var(--red)';

  return (
    <div className={`popout ${windowState.focused ? '' : 'is-inactive'}`} title={pick.url}>
      <div
        className="popout-header"
        onPointerDown={(e) => {
          if (e.button === 0 && !(e.target as HTMLElement).closest('button')) host.send('window.drag');
        }}
      >
        <span className="live-state" style={{ color }}>
          <span className={`live-dot ${popOut.state === 'live' ? 'is-live' : ''}`} style={{ background: color }} />
          {popOut.state === 'live' ? 'Live' : popOut.state === 'loading' ? 'Loading' : 'Lost'}
        </span>
        <span className="popout-titles">
          <span className="popout-title truncate">{title}</span>
          <span className="popout-host secondary truncate">{popOut.host}</span>
        </span>
        <button
          className={`popout-button ${popOut.pinned ? 'is-on' : ''}`}
          title={popOut.pinned ? 'Unpin: stay on this workspace' : 'Pin: show on every workspace'}
          aria-label="Pin"
          onClick={() => popOut.togglePin()}
        >
          <Pin size={11} fill={popOut.pinned ? 'currentColor' : 'none'} />
        </button>
        <button className="popout-button" title="Close (Ctrl+W)" aria-label="Close" onClick={() => popOut.close()}>
          <X size={12} />
        </button>
      </div>
      <div className="popout-content">
        {popOut.state === 'loading' && <span className="spinner" />}
        {popOut.state === 'lost' && (
          <div className="popout-lost glass-strong">
            <strong>Couldn’t find the element</strong>
            <button className="button small" onClick={() => popOut.reload()}>
              Try Again
            </button>
          </div>
        )}
      </div>
    </div>
  );
});

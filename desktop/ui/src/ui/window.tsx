// The borderless window's own chrome: its state (maximized, focused), and resize
// zones along its edges. The shell webview covers the whole window, so the system
// never sees the pointer at the edge; these zones ask the host to start the
// system's resize instead.

import { makeAutoObservable } from 'mobx';
import { observer } from 'mobx-react-lite';
import { host } from '../host/host';

class WindowState {
  maximized = false;
  fullscreen = false;
  focused = true;
  scale = 1;

  constructor() {
    makeAutoObservable(this);
    host.on('window.state', (s) => this.apply(s));
    host.on('window.focus', ({ focused }) => (this.focused = !!focused));
  }

  apply(s: any) {
    this.maximized = !!s.maximized;
    this.fullscreen = !!s.fullscreen;
    this.focused = s.focused !== false;
    this.scale = Number(s.scale) || 1;
  }
}

export const windowState = new WindowState();
export const useWindowState = () => windowState;

const EDGES = ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'] as const;

export const ResizeEdges = observer(function ResizeEdges() {
  if (windowState.maximized || windowState.fullscreen) return null;
  return (
    <>
      {EDGES.map((edge) => (
        <div
          key={edge}
          className={`resize-edge resize-${edge}`}
          onPointerDown={(event) => {
            if (event.button !== 0) return;
            event.preventDefault();
            host.send('window.resize', { edge });
          }}
        />
      ))}
    </>
  );
});

// The bridge to the Rust host (desktop/host). Commands go out through wry's IPC
// as `{ cmd, req?, ...args }`; replies and events come back through
// `window.__wakeHost`. Outside the host (plain `vite dev` in a browser) a mock
// answers instead, so the UI can be worked on without pages.

import { mockCall } from './mock';

type Handler = (payload: any) => void;

declare global {
  interface Window {
    ipc?: { postMessage(message: string): void };
    __wakeHost?: {
      reply(req: number, ok: boolean, value: unknown): void;
      event(name: string, payload: unknown): void;
    };
  }
}

const pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void }>();
const handlers = new Map<string, Set<Handler>>();
let nextReq = 1;

export const isHosted = typeof window !== 'undefined' && !!window.ipc;

window.__wakeHost = {
  reply(req, ok, value) {
    const waiting = pending.get(req);
    if (!waiting) return;
    pending.delete(req);
    if (ok) waiting.resolve(value);
    else waiting.reject(new Error(String(value)));
  },
  event(name, payload) {
    dispatch(name, payload);
  },
};

function dispatch(name: string, payload: unknown) {
  const set = handlers.get(name);
  if (!set) return;
  for (const handler of [...set]) {
    try {
      handler(payload);
    } catch (error) {
      console.error(`host event ${name}:`, error);
    }
  }
}

export const host = {
  /** Sends a command and waits for its answer. */
  call<T = any>(cmd: string, args: Record<string, unknown> = {}): Promise<T> {
    if (!isHosted) return mockCall(cmd, args, dispatch) as Promise<T>;
    const req = nextReq++;
    return new Promise<T>((resolve, reject) => {
      pending.set(req, { resolve, reject });
      window.ipc!.postMessage(JSON.stringify({ cmd, req, ...args }));
    });
  },

  /** Sends a command without waiting. */
  send(cmd: string, args: Record<string, unknown> = {}): void {
    if (!isHosted) {
      void mockCall(cmd, args, dispatch);
      return;
    }
    window.ipc!.postMessage(JSON.stringify({ cmd, ...args }));
  },

  on(name: string, handler: Handler): () => void {
    let set = handlers.get(name);
    if (!set) handlers.set(name, (set = new Set()));
    set.add(handler);
    return () => set!.delete(handler);
  },
};

export interface HostInfo {
  window: number;
  platform: 'linux' | 'windows' | string;
  version: string;
  settings: Record<string, unknown>;
  claims: Record<string, number>;
  downloads: string;
  dataDir: string;
  firstWindow: boolean;
}

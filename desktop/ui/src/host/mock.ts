// A stand-in host for working on the UI in a plain browser (`npm run dev`).
// Storage is a real SQLite (sql.js) in memory with the shared schema; pages are
// placeholders that "load" instantly. Never part of a production build: every
// entry point is behind `import.meta.env.DEV`.

import schemaSQL from '../../../../shared/schema/001_initial.sql?raw';
import settingsSchema from '../../../../shared/schema/settings.json';

type Dispatch = (name: string, payload: unknown) => void;

let dbPromise: Promise<any> | null = null;

async function database(): Promise<any> {
  // `if (DEV)` (not an early return) so production builds drop sql.js entirely.
  if (import.meta.env.DEV && !dbPromise) {
    dbPromise = (async () => {
      const initSqlJs = (await import('sql.js')).default;
      const wasm = (await import('sql.js/dist/sql-wasm.wasm?url')).default;
      const SQL = await initSqlJs({ locateFile: () => wasm });
      const db = new SQL.Database();
      db.exec(schemaSQL);
      return db;
    })();
  }
  if (!dbPromise) throw new Error('no host');
  return dbPromise;
}

function rows(db: any, sql: string, params: unknown[]) {
  const statement = db.prepare(sql);
  statement.bind(params.map(clean));
  const out: Record<string, unknown>[] = [];
  while (statement.step()) out.push(statement.getAsObject());
  statement.free();
  return out;
}

function clean(value: unknown) {
  if (typeof value === 'boolean') return value ? 1 : 0;
  if (value === undefined) return null;
  if (value !== null && typeof value === 'object') return JSON.stringify(value);
  return value;
}

const settings: Record<string, unknown> = Object.fromEntries(
  Object.entries(settingsSchema as Record<string, any>)
    .filter(([key]) => !key.startsWith('$'))
    .map(([key, spec]) => [key, spec.default]),
);
try {
  Object.assign(settings, JSON.parse(localStorage.getItem('wake.mock.settings') || '{}'));
} catch {}

function placeholder(title: string, url: string, width = 640): string {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = Math.round(width * 0.62);
  const g = canvas.getContext('2d')!;
  let hue = 0;
  for (const ch of url) hue = (hue * 31 + ch.charCodeAt(0)) % 360;
  g.fillStyle = '#fff';
  g.fillRect(0, 0, canvas.width, canvas.height);
  g.fillStyle = `hsl(${hue} 45% 78%)`;
  g.fillRect(0, 0, canvas.width, canvas.height * 0.36);
  g.fillStyle = '#1d1d1f';
  g.font = `600 ${Math.round(width / 16)}px system-ui`;
  g.fillText(title.slice(0, 28), width * 0.06, canvas.height * 0.5);
  g.fillStyle = '#d1d1d6';
  for (let i = 0; i < 5; i++) g.fillRect(width * 0.06, canvas.height * (0.6 + i * 0.07), width * (0.5 + ((i * 37) % 40) / 100), 8);
  return canvas.toDataURL('image/jpeg', 0.8);
}

const pageURLs = new Map<string, string>();

function load(page: string, url: string, dispatch: Dispatch) {
  pageURLs.set(page, url);
  let title = url;
  try {
    title = new URL(url).hostname.replace(/^www\./, '');
  } catch {}
  dispatch('page.load', { page, phase: 'started', url });
  dispatch('page.state', { page, loading: true, progress: 0.2 });
  setTimeout(() => {
    dispatch('page.committed', { page, url, secure: url.startsWith('https:') });
    dispatch('page.state', { page, url, title, progress: 1, loading: false, canGoBack: false, canGoForward: false });
    dispatch('page.load', { page, phase: 'finished', url });
  }, 250);
}

export async function mockCall(cmd: string, args: Record<string, any>, dispatch: Dispatch): Promise<unknown> {
  switch (cmd) {
    case 'ready':
      return {
        window: 1,
        platform: 'linux',
        version: 'dev',
        settings,
        claims: {},
        downloads: '~/Downloads',
        dataDir: '(browser)',
        firstWindow: true,
      };
    case 'settings.set':
      settings[args.key] = args.value;
      localStorage.setItem('wake.mock.settings', JSON.stringify(settings));
      dispatch('settings.changed', { key: args.key, value: args.value });
      return null;
    case 'db.query':
      return rows(await database(), args.sql, args.params ?? []);
    case 'db.exec': {
      const db = await database();
      db.run(args.sql, (args.params ?? []).map(clean));
      return { changes: db.getRowsModified(), lastId: 0 };
    }
    case 'db.batch': {
      const db = await database();
      db.exec('BEGIN');
      try {
        for (const s of args.statements ?? []) db.run(s.sql, (s.params ?? []).map(clean));
        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
      return null;
    }
    case 'threads.claim':
      return true;
    case 'page.create':
      if (args.url) load(args.page, args.url, dispatch);
      return null;
    case 'page.load':
      load(args.page, args.url, dispatch);
      return null;
    case 'page.snapshot': {
      const url = pageURLs.get(args.page) ?? 'about:blank';
      let title = url;
      try {
        title = new URL(url).hostname;
      } catch {}
      return placeholder(title, url, args.width ?? 640);
    }
    case 'page.eval':
    case 'page.run':
      return null;
    case 'http.fetch':
      try {
        const response = await fetch(args.url);
        return { status: response.status, headers: {}, text: await response.text() };
      } catch (error) {
        throw new Error(String(error));
      }
    case 'clipboard.write':
      await navigator.clipboard?.writeText(args.text);
      return null;
    case 'window.new':
      window.open(location.href);
      return 2;
    case 'open.external':
      window.open(args.url, '_blank');
      return null;
    case 'file.exists':
      return false;
    default:
      return null;
  }
}

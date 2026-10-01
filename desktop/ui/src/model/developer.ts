// Developer mode's model (ports of DevProjects.swift, DevServerScanner.swift and
// SourceMapResolver.swift): projects and their environments, local dev servers,
// and source maps.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { settings } from './settings';
import type { SourceLocation } from './devtools-log';

export type DevEnvironment = 'local' | 'staging' | 'production';
export const ENVIRONMENTS: DevEnvironment[] = ['local', 'staging', 'production'];
export const ENVIRONMENT_LABELS: Record<DevEnvironment, string> = { local: 'Local', staging: 'Staging', production: 'Production' };
export const ENVIRONMENT_COLORS: Record<DevEnvironment, string> = { local: '#34C759', staging: '#FF9500', production: '#FF3B30' };

export interface DevProjectData {
  id: string;
  name: string;
  origins: Partial<Record<DevEnvironment, string>>;
  /** The project folder: for the git branch and opening source files in the editor. */
  folderPath: string | null;
}

export function originOf(url: string): string | null {
  try {
    const u = new URL(url);
    const port = u.port || (u.protocol === 'https:' ? '443' : '80');
    return `${u.protocol}//${u.hostname.toLowerCase()}:${port}`;
  } catch {
    return null;
  }
}

export class DevProject {
  constructor(public data: DevProjectData) {}

  get name() {
    return this.data.name;
  }

  environment(url: string): DevEnvironment | null {
    const origin = originOf(url);
    if (!origin) return null;
    for (const env of ENVIRONMENTS) {
      const value = this.data.origins[env];
      if (value && originOf(value) === origin) return env;
    }
    return null;
  }

  /** The same path and query, on another environment's origin. */
  url(url: string, env: DevEnvironment): string | null {
    const base = this.data.origins[env];
    if (!base) return null;
    try {
      const target = new URL(base);
      const u = new URL(url);
      u.protocol = target.protocol;
      u.hostname = target.hostname;
      u.port = target.port;
      return u.href;
    } catch {
      return null;
    }
  }
}

class DevProjectStore {
  projects: DevProjectData[] = [];

  constructor() {
    makeAutoObservable(this);
  }

  load() {
    const saved = settings.get<DevProjectData[]>('developer.projects', []);
    this.projects = Array.isArray(saved) ? saved : [];
  }

  project(url: string | null | undefined): DevProject | null {
    if (!url) return null;
    const data = this.projects.find((p) => new DevProject(p).environment(url));
    return data ? new DevProject(data) : null;
  }

  save(project: DevProjectData) {
    const index = this.projects.findIndex((p) => p.id === project.id);
    if (index >= 0) this.projects[index] = project;
    else this.projects.push(project);
    this.persist();
  }

  delete(project: DevProjectData) {
    this.projects = this.projects.filter((p) => p.id !== project.id);
    this.persist();
  }

  /** A project for a local page you haven't set up yet. */
  makeProject(url: string): DevProjectData {
    const u = new URL(url);
    return {
      id: crypto.randomUUID(),
      name: `${u.hostname}${u.port ? ':' + u.port : ''}`,
      origins: { local: `${u.protocol}//${u.hostname}${u.port ? ':' + u.port : ''}` },
      folderPath: null,
    };
  }

  /** Asks for the project folder and saves it with the project. */
  async chooseFolder(project: DevProjectData): Promise<DevProjectData | null> {
    const folder = await host.call<string | null>('dialog.folder', { title: `Choose the folder for ${project.name}` });
    if (!folder) return null;
    const next = { ...project, folderPath: folder };
    this.save(next);
    return next;
  }

  gitBranch(project: DevProjectData): Promise<string | null> {
    if (!project.folderPath) return Promise.resolve(null);
    return host.call<string | null>('git.branch', { folder: project.folderPath }).catch(() => null);
  }

  private persist() {
    settings.set('developer.projects', this.projects.map((p) => ({ ...p })));
  }
}

export const projects = new DevProjectStore();
export const projectFor = (url: string | null | undefined) => projects.project(url);

// MARK: Dev servers

export type Framework = 'Vite' | 'Next.js' | 'Storybook' | 'Angular' | 'Django' | 'Rails' | 'Express' | 'Server';

export interface DevServer {
  port: number;
  framework: Framework;
  title: string;
  isRunning: boolean;
  url: string;
}

const PORTS = [...range(3000, 3010), 4200, ...range(5173, 5180), 6006, 8000, 8080];

function range(a: number, b: number) {
  return Array.from({ length: b - a + 1 }, (_, i) => a + i);
}

function identify(headers: Record<string, string>, html: string): Framework {
  const get = (k: string) => (Object.entries(headers).find(([h]) => h.toLowerCase() === k)?.[1] ?? '').toLowerCase();
  const poweredBy = get('x-powered-by');
  const server = get('server');
  if (poweredBy.includes('next') || html.includes('/_next/') || html.includes('__NEXT_DATA__')) return 'Next.js';
  if (html.includes('/@vite/client')) return 'Vite';
  if (html.toLowerCase().includes('storybook')) return 'Storybook';
  if (html.includes('ng-version') || html.includes('<app-root')) return 'Angular';
  if (server.includes('wsgiserver') || html.includes('csrfmiddlewaretoken')) return 'Django';
  if (server.includes('puma') || get('x-runtime')) return 'Rails';
  if (poweredBy.includes('express')) return 'Express';
  return 'Server';
}

/**
 * Polls the usual dev-server ports on localhost and identifies what answers.
 * Servers seen this session stay listed (grey) after they stop, so restarting
 * one doesn't reshuffle the capsule.
 */
class DevServerScanner {
  servers: DevServer[] = [];
  private timer = 0;
  private running = false;
  windowFocused = true;

  constructor() {
    makeAutoObservable<DevServerScanner, 'timer' | 'running'>(this, { timer: false, running: false });
  }

  start() {
    if (this.running) return;
    this.running = true;
    void this.loop();
  }

  stop() {
    this.running = false;
    clearTimeout(this.timer);
  }

  private async loop() {
    if (!this.running) return;
    await this.scan();
    // Every 5 s while you're in Wake; in the background a new server can wait.
    this.timer = window.setTimeout(() => void this.loop(), this.windowFocused ? 5000 : 30000);
  }

  private async scan() {
    const found = await Promise.all(PORTS.map((port) => this.probe(port)));
    const byPort = new Map(found.filter((s): s is DevServer => !!s).map((s) => [s.port, s]));
    runInAction(() => {
      const next = this.servers.map((s) => byPort.get(s.port) ?? { ...s, isRunning: false });
      for (const s of byPort.values()) if (!next.some((n) => n.port === s.port)) next.push(s);
      next.sort((a, b) => a.port - b.port);
      if (JSON.stringify(next) !== JSON.stringify(this.servers)) this.servers = next;
    });
  }

  private async probe(port: number): Promise<DevServer | null> {
    try {
      const url = `http://localhost:${port}/`;
      const response = await host.call<{ status: number; headers: Record<string, string>; text: string }>('http.fetch', {
        url,
        timeoutMs: 600,
        maxBytes: 16384,
      });
      const html = response.text ?? '';
      const framework = identify(response.headers ?? {}, html);
      const title = /<title[^>]*>([^<]{1,80})<\/title>/i.exec(html)?.[1]?.trim() || framework;
      return { port, framework, title, isRunning: true, url };
    } catch {
      return null;
    }
  }
}

export const devServers = new DevServerScanner();

// MARK: Source maps

export interface OriginalPosition {
  /** As written in the map, e.g. "webpack://app/./src/App.tsx" or "/src/App.tsx". */
  source: string;
  line: number;
  column: number;
}

/** The source as a path inside the project: prefixes and queries stripped. */
export function projectRelativePath(source: string) {
  let path = source.replace(/^[a-z-]+:\/\/[^/]*\//, '');
  const q = path.indexOf('?');
  if (q >= 0) path = path.slice(0, q);
  while (path.startsWith('./') || path.startsWith('../')) path = path.replace(/^\.+\//, '');
  if (path.startsWith('/@fs/')) path = path.slice(4);
  return path;
}

const BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function decodeVLQ(segment: string): number[] {
  const values: number[] = [];
  let value = 0;
  let shift = 0;
  for (const ch of segment) {
    const digit = BASE64.indexOf(ch);
    if (digit < 0) return values;
    value += (digit & 31) << shift;
    if (digit & 32) shift += 5;
    else {
      values.push(value & 1 ? -(value >> 1) : value >> 1);
      value = 0;
      shift = 0;
    }
  }
  return values;
}

/** Finds the original position of a 0-based generated line and column (source map v3). */
export function originalPosition(map: { sources: string[]; sourceRoot?: string; mappings: string }, line: number, column: number): OriginalPosition | null {
  let source = 0, originalLine = 0, originalColumn = 0;
  let best: [number, number, number] | null = null;
  const lines = map.mappings.split(';');
  for (let i = 0; i <= line && i < lines.length; i++) {
    let generated = 0;
    for (const segment of lines[i].split(',')) {
      if (!segment) continue;
      const v = decodeVLQ(segment);
      if (!v.length) continue;
      generated += v[0];
      if (v.length >= 4) {
        source += v[1];
        originalLine += v[2];
        originalColumn += v[3];
        if (i === line && generated <= column) best = [source, originalLine, originalColumn];
      }
    }
  }
  if (!best || !map.sources[best[0]]) return null;
  const root = map.sourceRoot ? (map.sourceRoot.endsWith('/') ? map.sourceRoot : map.sourceRoot + '/') : '';
  return { source: root + map.sources[best[0]], line: best[1] + 1, column: best[2] + 1 };
}

async function fetchText(url: string): Promise<string | null> {
  try {
    const response = await host.call<{ status: number; text: string }>('http.fetch', { url, timeoutMs: 5000, maxBytes: 32 * 1024 * 1024 });
    return response.status < 400 ? response.text : null;
  } catch {
    return null;
  }
}

/** Maps a position in served JavaScript back to its original source file. */
export async function resolveSourceMap(location: SourceLocation): Promise<OriginalPosition | null> {
  const script = await fetchText(location.url);
  if (!script) return null;
  const refs = [...script.matchAll(/[#@] sourceMappingURL=(\S+)/g)];
  const reference = refs[refs.length - 1]?.[1];
  if (!reference) return null;
  let mapText: string | null = null;
  if (reference.startsWith('data:')) {
    const comma = reference.indexOf(',');
    const payload = reference.slice(comma + 1);
    try {
      mapText = reference.slice(0, comma).includes('base64')
        ? new TextDecoder().decode(Uint8Array.from(atob(payload), (c) => c.charCodeAt(0)))
        : decodeURIComponent(payload);
    } catch {
      return null;
    }
  } else {
    try {
      mapText = await fetchText(new URL(reference, location.url).href);
    } catch {
      return null;
    }
  }
  if (!mapText) return null;
  try {
    return originalPosition(JSON.parse(mapText), location.line - 1, location.column - 1);
  } catch {
    return null;
  }
}

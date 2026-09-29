// What developer mode has observed on one page: console, network, HMR, and the
// mocked routes it's answering itself (port of DevToolsLog.swift).

import { makeAutoObservable } from 'mobx';

export interface SourceLocation {
  url: string;
  line: number;
  column: number;
}

export function fileName(location: SourceLocation) {
  try {
    const u = new URL(location.url);
    return u.pathname.split('/').pop() || u.hostname;
  } catch {
    return location.url;
  }
}

/** The first frame of a JS stack that points at an http(s) script ("at fn (url:1:2)" or "fn@url:1:2"). */
export function firstFrame(stack: string | null | undefined): SourceLocation | null {
  if (!stack) return null;
  for (const line of stack.split('\n')) {
    const match = /(https?:\/\/[^\s()]+?):(\d+):(\d+)/.exec(line);
    if (match) return { url: match[1], line: Number(match[2]), column: Number(match[3]) };
  }
  return null;
}

export type ConsoleLevel = 'log' | 'info' | 'debug' | 'warn' | 'error' | 'input' | 'result';

let nextEntry = 1;

export interface ConsoleEntry {
  id: number;
  level: ConsoleLevel;
  message: string;
  stack: string | null;
  date: Date;
  /** Identical messages in a row are shown once with a count. */
  repeatCount: number;
}

/** React names the failing component in its error text; pick it out when present. */
export function componentOf(entry: ConsoleEntry): string | null {
  const text = entry.message + '\n' + (entry.stack ?? '');
  return /in the <(\w+)> component/.exec(text)?.[1] ?? /at <?([A-Z]\w+)>? \(/.exec(text)?.[1] ?? null;
}

export interface NetworkEntry {
  id: number;
  method: string;
  url: string;
  requestHeaders: Record<string, string>;
  requestBody: string | null;
  startedAt: Date;
  status?: number | null;
  /** Seconds. */
  duration?: number | null;
  responsePreview?: string | null;
  responseHeaders: Record<string, string>;
  responseSize?: number | null;
  error?: string | null;
  isMocked: boolean;
  initiator: string;
}

export const isFailure = (entry: NetworkEntry) => !!entry.error || (entry.status ?? 0) >= 400;

export function pathAndQuery(entry: NetworkEntry) {
  try {
    const u = new URL(entry.url);
    return u.pathname + u.search;
  } catch {
    return entry.url;
  }
}

const shellQuoted = (text: string) => "'" + text.replace(/'/g, "'\\''") + "'";

/** The request as a shell command. */
export function curl(entry: NetworkEntry) {
  const parts = ['curl', '-X', entry.method, shellQuoted(entry.url)];
  for (const [name, value] of Object.entries(entry.requestHeaders).sort(([a], [b]) => a.localeCompare(b))) {
    parts.push('-H', shellQuoted(`${name}: ${value}`));
  }
  if (entry.requestBody) parts.push('--data-raw', shellQuoted(entry.requestBody));
  return parts.join(' ');
}

export type HMR = { state: 'none' } | { state: 'connected'; kind: string } | { state: 'disconnected'; kind: string };

/** Drops Wake's own frames (its console hook is an injected script) from a stack. */
export function pageFrames(stack: unknown): string | null {
  if (typeof stack !== 'string') return null;
  const frames = stack.split('\n').filter((f) => !f.includes('user-script:') && !f.includes('__wakeDev'));
  return frames.length ? frames.join('\n') : null;
}

export class DevToolsLog {
  console: ConsoleEntry[] = [];
  network: NetworkEntry[] = [];
  hmr: HMR = { state: 'none' };
  lastHotUpdate: Date | null = null;
  /** Path → JSON body. Matching fetches are answered without touching the network. */
  mocks: Record<string, string> = {};
  preservesLog = false;
  documentStart = new Date();
  errorCount = 0;
  warningCount = 0;

  private consoleLimit = 500;
  private networkLimit = 300;

  constructor() {
    makeAutoObservable(this);
  }

  clearConsole() {
    this.console = [];
    this.errorCount = 0;
    this.warningCount = 0;
  }

  clearNetwork() {
    this.network = [];
  }

  /** A new document: its requests and messages start fresh. Mocks persist. */
  reset() {
    this.documentStart = new Date();
    this.hmr = { state: 'none' };
    if (this.preservesLog) {
      this.append('info', 'Navigated to a new page', null);
      return;
    }
    this.clearConsole();
    this.network = [];
  }

  addLocal(level: ConsoleLevel, message: string) {
    this.append(level, message, null);
  }

  private append(level: ConsoleLevel, message: string, stack: string | null) {
    const last = this.console[this.console.length - 1];
    if (last && last.level === level && last.message === message && last.stack === stack && level !== 'input' && level !== 'result') {
      last.repeatCount += 1;
    } else {
      this.console.push({ id: nextEntry++, level, message, stack, date: new Date(), repeatCount: 1 });
      if (this.console.length > this.consoleLimit) this.console.splice(0, this.console.length - this.consoleLimit);
    }
    if (level === 'error') this.errorCount += 1;
    if (level === 'warn') this.warningCount += 1;
  }

  setMock(body: string | null, path: string) {
    if (body == null) delete this.mocks[path];
    else this.mocks[path] = body;
  }

  receive(message: any) {
    switch (message?.type) {
      case 'console': {
        const level = (['log', 'info', 'debug', 'warn', 'error'].includes(message.level) ? message.level : 'log') as ConsoleLevel;
        this.append(level, String(message.message ?? ''), pageFrames(message.stack));
        break;
      }
      case 'consoleClear':
        this.clearConsole();
        break;
      case 'request': {
        if (typeof message.id !== 'number' || typeof message.url !== 'string') return;
        this.network.push({
          id: message.id,
          method: message.method ?? 'GET',
          url: message.url,
          requestHeaders: message.headers ?? {},
          requestBody: message.body ?? null,
          startedAt: new Date(),
          responseHeaders: {},
          isMocked: false,
          initiator: message.initiator ?? 'fetch',
        });
        if (this.network.length > this.networkLimit) this.network.splice(0, this.network.length - this.networkLimit);
        break;
      }
      case 'response': {
        const entry = [...this.network].reverse().find((e) => e.id === message.id);
        if (!entry) return;
        entry.status = message.status ?? null;
        entry.duration = typeof message.ms === 'number' ? message.ms / 1000 : null;
        entry.responsePreview = message.preview ?? null;
        entry.error = message.error ?? null;
        entry.isMocked = !!message.mocked;
        entry.responseHeaders = message.headers ?? {};
        entry.responseSize = message.size ?? null;
        break;
      }
      case 'hmr': {
        const kind = message.kind ?? 'HMR';
        if (message.state === 'connected') this.hmr = { state: 'connected', kind };
        else if (message.state === 'disconnected') this.hmr = { state: 'disconnected', kind };
        else if (message.state === 'updated') {
          this.hmr = { state: 'connected', kind };
          this.lastHotUpdate = new Date();
        }
        break;
      }
    }
  }
}

export interface ComponentPick {
  framework: string | null;
  name: string | null;
  file: string | null;
  line: number | null;
  pageURL: string | null;
}

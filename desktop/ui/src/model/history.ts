// Pages you visited and things you searched for (port of HistoryStore.swift).
// Searches are recognised from results-page URLs, so searches typed on a search
// site count too.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { db } from '../host/db';
import { settings } from './settings';
import { matchSearch, isValidTemplate, type SearchMatch } from './search';

export interface Visit {
  url: string;
  title: string;
  /** Seconds since 1970. */
  visitedAt: number;
  visitCount: number;
  source: string | null;
}

export interface Search {
  id: number;
  query: string;
  engine: string;
  url: string;
  searchedAt: number;
  source: string | null;
}

/** The address lowercased, without its scheme: what History's search matches. */
export function addressOf(url: string) {
  const lower = url.toLowerCase();
  const scheme = /^[a-z][a-z0-9+.-]*:\/\//.exec(lower);
  return scheme ? lower.slice(scheme[0].length) : lower;
}

/** Paging a results page (or reloading it) within this window counts as one search. */
const SEARCH_MERGE_WINDOW = 30 * 60;

class HistoryStore {
  /** Bumped on every change; lists re-query when it moves. */
  version = 0;
  /** The most recent visits, for the palette's "Recent". */
  recent: Visit[] = [];
  visitCount = 0;
  searchCount = 0;

  constructor() {
    makeAutoObservable(this);
    host.on('history.changed', () => void this.refresh(false));
  }

  async refresh(notify = true) {
    const [recent, counts] = await Promise.all([
      db.query<Visit>('SELECT url, title, visitedAt, visitCount, source FROM VisitRecord ORDER BY visitedAt DESC LIMIT 50'),
      db.first<{ visits: number; searches: number }>(
        'SELECT (SELECT COUNT(*) FROM VisitRecord) AS visits, (SELECT COUNT(*) FROM SearchRecord) AS searches',
      ),
    ]);
    runInAction(() => {
      this.recent = recent;
      this.visitCount = counts?.visits ?? 0;
      this.searchCount = counts?.searches ?? 0;
      this.version += 1;
    });
    if (notify) host.send('broadcast', { name: 'history.changed' });
  }

  // MARK: Recording

  async recordVisit(url: string, title: string) {
    const now = Date.now() / 1000;
    await db.exec(
      `INSERT INTO VisitRecord (url, title, visitedAt, visitCount, source, address) VALUES (?, ?, ?, 1, NULL, ?)
       ON CONFLICT(url) DO UPDATE SET title = CASE WHEN excluded.title = '' THEN title ELSE excluded.title END,
         visitedAt = excluded.visitedAt, visitCount = visitCount + 1`,
      [url, title, now, addressOf(url)],
    );
    const custom = settings.searchEngine === 'custom' && isValidTemplate(settings.customSearchTemplate) ? settings.customSearchTemplate : null;
    const match = matchSearch(url, custom);
    if (match) await this.recordSearch(match, url, now);
    await this.refresh();
  }

  private async recordSearch(match: SearchMatch, url: string, date: number) {
    const recent = await db.first<Search>(
      'SELECT * FROM SearchRecord WHERE query = ? AND searchedAt > ? ORDER BY searchedAt DESC LIMIT 1',
      [match.query, date - SEARCH_MERGE_WINDOW],
    );
    if (recent && recent.engine === match.engine) {
      await db.exec('UPDATE SearchRecord SET searchedAt = ? WHERE id = ?', [date, recent.id]);
    } else {
      await db.exec('INSERT INTO SearchRecord (query, engine, url, searchedAt) VALUES (?, ?, ?, ?)', [match.query, match.engine, url, date]);
    }
  }

  // MARK: Reading

  /** Newest first; `text` matches title or address, across the whole history. */
  visits(text: string, limit: number, offset = 0): Promise<Visit[]> {
    const needle = text.trim();
    if (!needle) {
      return db.query('SELECT url, title, visitedAt, visitCount, source FROM VisitRecord ORDER BY visitedAt DESC LIMIT ? OFFSET ?', [limit, offset]);
    }
    const like = `%${needle.toLowerCase().replace(/[\\%_]/g, (c) => '\\' + c)}%`;
    return db.query(
      `SELECT url, title, visitedAt, visitCount, source FROM VisitRecord
       WHERE lower(title) LIKE ? ESCAPE '\\' OR address LIKE ? ESCAPE '\\'
       ORDER BY visitedAt DESC LIMIT ? OFFSET ?`,
      [like, like, limit, offset],
    );
  }

  searches(text: string, limit: number, offset = 0): Promise<Search[]> {
    const needle = text.trim();
    if (!needle) return db.query('SELECT * FROM SearchRecord ORDER BY searchedAt DESC LIMIT ? OFFSET ?', [limit, offset]);
    const like = `%${needle.toLowerCase().replace(/[\\%_]/g, (c) => '\\' + c)}%`;
    return db.query(`SELECT * FROM SearchRecord WHERE lower(query) LIKE ? ESCAPE '\\' ORDER BY searchedAt DESC LIMIT ? OFFSET ?`, [like, limit, offset]);
  }

  // MARK: Removing

  async deleteVisit(url: string) {
    await db.exec('DELETE FROM VisitRecord WHERE url = ?', [url]);
    await this.refresh();
  }

  async deleteSearch(id: number) {
    await db.exec('DELETE FROM SearchRecord WHERE id = ?', [id]);
    await this.refresh();
  }

  /** Forgets visited pages (and searches), keeping threads and pins. */
  async clearAll() {
    await db.batch([{ sql: 'DELETE FROM VisitRecord' }, { sql: 'DELETE FROM SearchRecord' }]);
    await this.refresh();
  }

  async clearSearches() {
    await db.exec('DELETE FROM SearchRecord');
    await this.refresh();
  }

  // MARK: Importing

  /** Merges another browser's history: a known page keeps the newer visit and higher count. Returns how many were new. */
  async importVisits(visits: { url: string; title: string; lastVisit: number; visitCount: number }[], source: string): Promise<number> {
    const before = (await db.first<{ n: number }>('SELECT COUNT(*) AS n FROM VisitRecord'))?.n ?? 0;
    for (let i = 0; i < visits.length; i += 500) {
      await db.batch(
        visits.slice(i, i + 500).map((v) => ({
          sql: `INSERT INTO VisitRecord (url, title, visitedAt, visitCount, source, address) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(url) DO UPDATE SET
                  title = CASE WHEN title = '' THEN excluded.title ELSE title END,
                  visitedAt = MAX(visitedAt, excluded.visitedAt),
                  visitCount = MAX(visitCount, excluded.visitCount)`,
          params: [v.url, v.title, v.lastVisit, Math.max(1, v.visitCount), source, addressOf(v.url)],
        })),
      );
    }
    const after = (await db.first<{ n: number }>('SELECT COUNT(*) AS n FROM VisitRecord'))?.n ?? 0;
    await this.refresh();
    return after - before;
  }

  /** Adds searches not already recorded (same words, engine and minute). */
  async importSearches(searches: { query: string; engine: string; url: string; date: number }[], source: string): Promise<number> {
    const existing = await db.query<Search>('SELECT query, engine, searchedAt FROM SearchRecord');
    const key = (q: string, e: string, d: number) => `${q.toLowerCase()}|${e}|${Math.floor(d / 60)}`;
    const seen = new Set(existing.map((s) => key(s.query, s.engine, s.searchedAt)));
    const fresh = searches.filter((s) => {
      const k = key(s.query, s.engine, s.date);
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
    for (let i = 0; i < fresh.length; i += 500) {
      await db.batch(
        fresh.slice(i, i + 500).map((s) => ({
          sql: 'INSERT INTO SearchRecord (query, engine, url, searchedAt, source) VALUES (?, ?, ?, ?, ?)',
          params: [s.query, s.engine, s.url, s.date, source],
        })),
      );
    }
    await this.refresh();
    return fresh.length;
  }
}

export const history = new HistoryStore();

// SQLite through the host (tables in shared/schema/001_initial.sql).

import { host } from './host';

export type Row = Record<string, any>;
export interface Statement {
  sql: string;
  params?: unknown[];
}

export const db = {
  query<T extends Row = Row>(sql: string, params: unknown[] = []): Promise<T[]> {
    return host.call<T[]>('db.query', { sql, params });
  },
  async first<T extends Row = Row>(sql: string, params: unknown[] = []): Promise<T | undefined> {
    return (await db.query<T>(sql, params))[0];
  },
  exec(sql: string, params: unknown[] = []): Promise<{ changes: number; lastId: number }> {
    return host.call('db.exec', { sql, params });
  },
  batch(statements: Statement[]): Promise<void> {
    return host.call('db.batch', { statements });
  },
};

/** Seconds since 1970, as the schema stores dates (Swift's timeIntervalSince1970). */
export const toSeconds = (date: Date | number) => (typeof date === 'number' ? date : date.getTime()) / 1000;
export const fromSeconds = (seconds: number | null | undefined) => (seconds == null ? null : new Date(seconds * 1000));

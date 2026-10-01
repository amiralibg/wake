// Pinned web apps (ports of PinnedApps.swift and PinnedAppRecord.swift): a page
// per app, loaded once per window and kept alive, shown in a panel beside the
// capsule.

import { makeAutoObservable, runInAction } from 'mobx';
import { host } from '../host/host';
import { db } from '../host/db';
import { Page, hostOf } from './page';
import { badgeIn } from './live';

export class PinnedApp {
  readonly page: Page;

  constructor(readonly id: string, readonly url: string, readonly savedTitle: string) {
    this.page = new Page();
    this.page.load(url);
    makeAutoObservable(this, { page: false, id: false, url: false, savedTitle: false });
  }

  get title() {
    return this.page.title || this.savedTitle || hostOf(this.url) || this.url;
  }

  get host() {
    return hostOf(this.url);
  }

  get badge() {
    return badgeIn(this.page.title);
  }
}

export class PinnedAppsModel {
  apps: PinnedApp[] = [];
  activeID: string | null = null;
  /** Hooks each app page into the browser (links open in the trail, and so on). */
  configurePage: (page: Page) => void = () => {};

  constructor() {
    makeAutoObservable(this, { configurePage: false });
    host.on('apps.changed', () => void this.sync());
  }

  get active(): PinnedApp | null {
    return this.apps.find((a) => a.id === this.activeID) ?? null;
  }

  /** Loads every pinned app. Called once per window. */
  async load() {
    const rows = await db.query('SELECT * FROM PinnedAppRecord ORDER BY "order"');
    runInAction(() => {
      this.apps = rows.map((r) => new PinnedApp(r.id, r.url, r.title));
    });
    this.apps.forEach((a) => this.configurePage(a.page));
  }

  /** Another window pinned or unpinned: match its list, keeping live pages. */
  private async sync() {
    const rows = await db.query('SELECT * FROM PinnedAppRecord ORDER BY "order"');
    runInAction(() => {
      const next = rows.map((r) => this.apps.find((a) => a.id === r.id) ?? new PinnedApp(r.id, r.url, r.title));
      for (const gone of this.apps.filter((a) => !next.includes(a))) gone.page.close();
      for (const fresh of next.filter((a) => !this.apps.includes(a))) this.configurePage(fresh.page);
      this.apps = next;
      if (this.activeID && !next.some((a) => a.id === this.activeID)) this.activeID = null;
    });
  }

  isPinned(url: string | null) {
    const h = hostOf(url);
    return !!h && this.apps.some((a) => a.host === h);
  }

  async pin(url: string, title: string) {
    if (this.isPinned(url)) return;
    const id = crypto.randomUUID();
    const order = this.apps.length;
    const app = new PinnedApp(id, url, title);
    this.configurePage(app.page);
    runInAction(() => this.apps.push(app));
    await db.exec('INSERT INTO PinnedAppRecord (id, url, title, "order") VALUES (?, ?, ?, ?)', [id, url, title, order]);
    host.send('broadcast', { name: 'apps.changed' });
  }

  async unpin(app: PinnedApp) {
    if (this.activeID === app.id) this.activeID = null;
    app.page.close();
    this.apps = this.apps.filter((a) => a !== app);
    await db.exec('DELETE FROM PinnedAppRecord WHERE id = ?', [app.id]);
    host.send('broadcast', { name: 'apps.changed' });
  }

  /** Clicking an app shows it; clicking the showing app puts it away. */
  toggle(app: PinnedApp) {
    this.activeID = this.activeID === app.id ? null : app.id;
  }

  dismiss() {
    this.activeID = null;
  }
}

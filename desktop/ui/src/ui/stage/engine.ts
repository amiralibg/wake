// Places page webviews. Every frame it springs each column towards the position
// TrailGeometry gives it, moves the column's card in the DOM, and tells the host
// where each page's native webview goes (`layout`).
//
// Native webviews sit above the UI and can't be drawn over. So a page's webview
// is shown only while nothing covers it; otherwise its card shows a snapshot:
// - while the UI covers the pages (Deck, palette, menus…: `covered`),
// - while the column's left edge is under the app capsule (it would draw over it),
// - while the page failed to load (the card shows the error).

import { Spring, Springs } from '../motion';
import { host } from '../../host/host';
import { settings } from '../../model/settings';
import type { Page } from '../../model/page';

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface Column {
  page: Page;
  x: Spring;
  w: Spring;
  el: HTMLElement | null;
  /** Where the page's webview goes inside the card (device previews are inset). */
  content: (card: Rect) => Rect | null;
  /** Current card rect in window coordinates. */
  rect: Rect;
}

export interface Extra {
  page: Page;
  rect: Rect;
}

export class LayoutEngine {
  private columns = new Map<string, Column>();
  private order: string[] = [];
  private targets = new Map<string, { x: number; w: number }>();
  private extras = new Map<string, Extra>();
  private frame = 0;
  private last = 0;
  private lastSent = '';
  /** Stage origin in window coordinates, and its size. */
  stage: Rect = { x: 0, y: 0, w: 0, h: 0 };
  offset = new Spring(0, Springs.trail);
  /** While true (a drag or resize), columns follow without springs. */
  immediate = false;
  covered = false;
  /** Pages shown full-window (a video in fullscreen); everything else hides. */
  fullscreen: Page | null = null;
  /** Webviews left of this x (window coordinates) would draw over the capsule. */
  clipLeft = -Infinity;
  /** Called after each frame with the columns' current rects (edge handles follow them). */
  onFrame: (rects: Map<string, Rect>) => void = () => {};

  register(page: Page, el: HTMLElement | null, content?: (card: Rect) => Rect | null) {
    const existing = this.columns.get(page.id);
    if (existing) {
      existing.el = el;
      if (content) existing.content = content;
      if (el) this.apply(existing);
      return;
    }
    const target = this.targets.get(page.id);
    const column: Column = {
      page,
      x: new Spring(target?.x ?? 0, Springs.trail),
      w: new Spring(target?.w ?? 0, Springs.trail),
      el,
      content: content ?? ((card) => card),
      rect: { x: 0, y: 0, w: 0, h: 0 },
    };
    this.columns.set(page.id, column);
    if (el) this.apply(column);
  }

  unregister(page: Page) {
    this.columns.delete(page.id);
    this.kick();
  }

  setContent(page: Page, content: (card: Rect) => Rect | null) {
    const column = this.columns.get(page.id);
    if (column) column.content = content;
    this.kick();
  }

  /** Targets for every column (content x, width), and the trail's offset. */
  setTargets(order: string[], targets: Map<string, { x: number; w: number }>, offset: number, fresh: Set<string>) {
    this.order = order;
    this.targets = targets;
    this.offset.target = offset;
    for (const [id, target] of targets) {
      const column = this.columns.get(id);
      if (!column) continue;
      column.x.target = target.x;
      column.w.target = target.w;
      // A new column appears where it belongs (it fades and scales in, CSS).
      if (fresh.has(id) || this.immediate) {
        column.x.jump(target.x);
        column.w.jump(target.w);
      }
    }
    if (this.immediate) this.offset.jump(offset);
    this.kick();
  }

  setExtra(id: string, extra: Extra | null) {
    if (extra) this.extras.set(id, extra);
    else this.extras.delete(id);
    this.kick();
  }

  kick() {
    if (this.frame) return;
    this.last = performance.now();
    this.frame = requestAnimationFrame(this.tick);
  }

  private tick = (now: number) => {
    this.frame = 0;
    const dt = Math.max(0, (now - this.last) / 1000);
    this.last = now;
    let moving = false;
    if (this.immediate) {
      this.offset.jump(this.offset.target);
      for (const column of this.columns.values()) {
        column.x.jump(column.x.target);
        column.w.jump(column.w.target);
      }
    } else {
      moving = this.offset.step(dt) || moving;
      for (const column of this.columns.values()) {
        moving = column.x.step(dt) || moving;
        moving = column.w.step(dt) || moving;
      }
    }
    const rects = new Map<string, Rect>();
    for (const column of this.columns.values()) {
      this.apply(column);
      rects.set(column.page.id, column.rect);
    }
    this.onFrame(rects);
    this.sendFrames();
    if (moving) this.frame = requestAnimationFrame(this.tick);
  };

  private apply(column: Column) {
    const x = column.x.value - this.offset.value;
    const w = Math.max(1, column.w.value);
    column.rect = { x: this.stage.x + x, y: this.stage.y, w, h: this.stage.h };
    const el = column.el;
    if (el) {
      el.style.transform = `translate3d(${x}px, 0, 0)`;
      el.style.width = `${w}px`;
    }
  }

  private sendFrames() {
    // `r`: the corner radius the native webview is clipped to, matching its card.
    const frames: { page: string; x: number; y: number; w: number; h: number; r: number }[] = [];
    const add = (page: Page, rect: Rect, r = settings.cornerRadius) =>
      frames.push({ page: page.id, x: Math.round(rect.x), y: Math.round(rect.y), w: Math.round(rect.w), h: Math.round(rect.h), r });

    if (this.fullscreen) {
      add(this.fullscreen, { x: 0, y: 0, w: window.innerWidth, h: window.innerHeight }, 0);
    } else {
      if (!this.covered) {
        for (const id of this.order) {
          const column = this.columns.get(id);
          if (!column || !this.shows(column)) continue;
          const content = column.content(column.rect);
          if (content) add(column.page, content);
        }
      }
      for (const extra of this.extras.values()) add(extra.page, extra.rect);
    }
    const key = JSON.stringify(frames);
    if (key === this.lastSent) return;
    this.lastSent = key;
    host.send('layout', { frames });
  }

  /** Whether a column's live webview is shown (else its card shows a snapshot). */
  shows(column: { page: Page; rect: Rect }): boolean {
    const page = column.page;
    if (page.isDevTools || page.failure || page.isClosed) return false;
    const r = column.rect;
    // Off the stage entirely (with a quarter stage of margin, the next one to slide in).
    const margin = this.stage.w / 4;
    if (r.x + r.w < this.stage.x - margin || r.x > this.stage.x + this.stage.w + margin) return false;
    if (r.x < this.clipLeft - 0.5) return false;
    return true;
  }

  /** Whether the page's card should show its snapshot right now. */
  showsSnapshot(page: Page): boolean {
    const column = this.columns.get(page.id);
    if (!column) return true;
    return this.covered || !this.shows(column);
  }

  columnRect(id: string) {
    return this.columns.get(id)?.rect ?? null;
  }

  /** The pages whose webviews are showing now (to snapshot before covering them). */
  visiblePages(): Page[] {
    if (this.covered) return [];
    return this.order
      .map((id) => this.columns.get(id))
      .filter((c): c is Column => !!c && this.shows(c))
      .map((c) => c.page);
  }

  dispose() {
    cancelAnimationFrame(this.frame);
    host.send('layout', { frames: [] });
  }
}

// Ordered columns of pages, left to right, with one in focus (port of
// TrailModel.swift). Positions animate in the Stage, which springs every column
// towards what this model and TrailGeometry say.

import { makeAutoObservable } from 'mobx';
import { Page } from './page';
import { TrailGeometry, Metrics } from './geometry';
import { settings } from './settings';
import { type DevicePreset, type DeviceFrame } from './device';

export type Edge = 'leading' | 'trailing';

export interface ColumnSnapshot {
  url: string;
  title: string;
  widthFraction: number | null;
  /** Where the page was scrolled to, when the thread was discarded. */
  scrollY?: number | null;
}

interface ClosedColumn {
  url: string;
  index: number;
  widthFraction: number | null;
}

export class TrailModel {
  columns: Page[] = [];
  focusedIndex = 0;
  /** Non-null while a swipe or a resize is moving the trail. */
  dragOffset: number | null = null;
  /** Where the trail rests after a resize, until focus moves. */
  restingOffset: number | null = null;
  /** Columns the user resized, as a share of the stage width. */
  customWidths = new Map<string, number>();
  isResizing = false;
  developerModeOverride: boolean | null = null;

  /** Written by the Stage whenever the stage or appearance changes. */
  geometry = new TrailGeometry();
  /** Called for every page this trail creates, so the owner can hook history etc. */
  didCreatePage: (page: Page) => void = () => {};
  /** Something worth saving changed: columns, focus, widths, URLs. */
  onChange: () => void = () => {};
  /** Focus moved to a column (the owner gives it keyboard focus). */
  onFocus: (page: Page) => void = () => {};

  recentlyClosed: ClosedColumn[] = [];
  private previewSources = new Map<string, Page>();
  private activeResize: { id: string; edge: Edge; width: number; offset: number } | null = null;
  private unbandedDrag: number | null = null;

  constructor() {
    makeAutoObservable<TrailModel, 'previewSources' | 'activeResize' | 'unbandedDrag'>(this, {
      geometry: false,
      didCreatePage: false,
      onChange: false,
      onFocus: false,
      recentlyClosed: false,
      previewSources: false,
      activeResize: false,
      unbandedDrag: false,
    });
  }

  get focused(): Page | null {
    return this.columns[this.focusedIndex] ?? null;
  }

  setDeveloperModeOverride(value: boolean | null) {
    this.developerModeOverride = value;
    this.columns.forEach((page) => page.setDeveloperModeOverride(value));
  }

  // MARK: Opening and closing

  /** Opens `url` in a new column right after `source` (or after the focused column). */
  open(url: string, after: Page | null = null, focus = true): Page {
    const page = this.makePage();
    this.insert(page, after ?? this.focused, focus);
    page.load(url);
    return page;
  }

  /** A popup the host created for `source`: it becomes a column right after it. */
  adoptPopup(page: Page, source: Page | null) {
    this.hook(page);
    this.insert(page, source, true);
  }

  close(page: Page) {
    const index = this.columns.indexOf(page);
    if (index < 0) return;
    const companions = this.columns.filter((c) => this.isCompanion(c, page));
    const address = page.address;
    if (!page.isEphemeral && address) {
      this.recentlyClosed.push({ url: address, index, widthFraction: this.customWidths.get(page.id) ?? null });
      if (this.recentlyClosed.length > 20) this.recentlyClosed.shift();
    }
    this.columns.splice(index, 1);
    this.customWidths.delete(page.id);
    if (index < this.focusedIndex || this.focusedIndex >= this.columns.length) {
      this.focusedIndex = Math.max(0, this.focusedIndex - 1);
    }
    this.restingOffset = null;
    // A lone column always fills the stage again.
    if (this.columns.length === 1) this.customWidths.clear();
    this.unlinkPreview(page);
    companions.forEach((c) => this.close(c));
    if (this.focused) this.onFocus(this.focused);
    this.onChange();
    this.release([page]);
  }

  /** Closes every column, e.g. when the thread is resolved or discarded. */
  closeAll() {
    this.release(this.columns);
    this.columns = [];
    this.customWidths.clear();
    this.focusedIndex = 0;
    this.restingOffset = null;
  }

  /** Recreates columns from a saved thread and starts loading them. */
  restore(snapshots: ColumnSnapshot[], focusedIndex: number) {
    const pages = snapshots.map((snapshot) => {
      const page = this.makePage();
      if (snapshots.length > 1 && snapshot.widthFraction != null) this.customWidths.set(page.id, snapshot.widthFraction);
      page.isRestoring = true;
      page.pendingScrollY = snapshot.scrollY ?? null;
      page.title = snapshot.title;
      page.load(snapshot.url);
      return page;
    });
    this.columns = pages;
    this.focusedIndex = Math.min(Math.max(focusedIndex, 0), Math.max(pages.length - 1, 0));
  }

  closeFocused() {
    if (this.focused) this.close(this.focused);
  }

  /** Frees closed pages' webviews once their cards have animated away. */
  private release(pages: Page[]) {
    const list = [...pages];
    list.forEach((p) => p.stopLoading());
    setTimeout(() => list.forEach((p) => p.close()), 400);
  }

  /** Reopens the last closed column where it was. */
  reopenClosed() {
    const closed = this.recentlyClosed.pop();
    if (!closed) return;
    const page = this.makePage();
    const index = Math.min(closed.index, this.columns.length);
    if (this.columns.length >= 1 && closed.widthFraction != null) this.customWidths.set(page.id, closed.widthFraction);
    this.columns.splice(index, 0, page);
    this.focusedIndex = index;
    this.restingOffset = null;
    page.load(closed.url);
    this.onFocus(page);
    this.onChange();
  }

  duplicateFocused() {
    const page = this.focused;
    const address = page?.address;
    if (!page || page.isDevTools || !address) return;
    this.open(address, page);
  }

  /** Moves the focused column (with its DevTools and previews) one place left or right. */
  moveFocused(step: number) {
    const page = this.focused;
    if (!page) return;
    const groups: Page[][] = [];
    for (const column of this.columns) {
      const last = groups[groups.length - 1];
      if (last && this.isCompanion(column, last[0])) last.push(column);
      else groups.push([column]);
    }
    const from = groups.findIndex((g) => g.includes(page));
    const to = from + (step < 0 ? -1 : 1);
    if (from < 0 || to < 0 || to >= groups.length) return;
    [groups[from], groups[to]] = [groups[to], groups[from]];
    const owner = groups[to][0];
    this.columns = groups.flat();
    this.focusedIndex = this.columns.indexOf(owner);
    this.restingOffset = null;
    this.onChange();
  }

  private insert(page: Page, source: Page | null, focus: boolean) {
    const index = source ? this.insertionIndex(source) : this.columns.length;
    this.columns.splice(index, 0, page);
    if (focus) this.focusedIndex = index;
    else if (index <= this.focusedIndex && this.columns.length > 1) this.focusedIndex += 1;
    this.restingOffset = null;
    if (focus) this.onFocus(page);
    this.onChange();
  }

  private makePage(options: ConstructorParameters<typeof Page>[0] = {}): Page {
    const page = new Page(options);
    this.hook(page);
    return page;
  }

  private hook(page: Page) {
    page.onOpenLink = (url, background) => {
      if (!background && !settings.linksOpenInNewColumn) page.load(url);
      else this.open(url, page, !background);
    };
    page.onPopup = (popup) => {
      this.adoptPopup(popup, page);
      return true;
    };
    page.onClose = () => this.close(page);
    page.onStateChange = () => this.onChange();
    page.onFocused = (p) => {
      const index = this.columns.indexOf(p);
      if (index >= 0 && index !== this.focusedIndex) this.focus(index, false);
    };
    if (this.developerModeOverride !== null) page.setDeveloperModeOverride(this.developerModeOverride);
    this.didCreatePage(page);
  }

  // MARK: Focus

  /** `giveKeyboard`: false when the page already has it (it was clicked). */
  focus(index: number, giveKeyboard = true) {
    if (index < 0 || index >= this.columns.length) return;
    this.focusedIndex = index;
    this.dragOffset = null;
    this.restingOffset = null;
    this.unbandedDrag = null;
    if (giveKeyboard) this.onFocus(this.columns[index]);
    this.onChange();
  }

  focusID(id: string) {
    const index = this.columns.findIndex((c) => c.id === id);
    if (index >= 0) this.focus(index);
  }

  focusNext() {
    this.focus(Math.min(this.focusedIndex + 1, this.columns.length - 1));
  }

  focusPrevious() {
    this.focus(Math.max(this.focusedIndex - 1, 0));
  }

  /** Ctrl+Tab: next column, wrapping around. */
  cycleFocus(forward: boolean) {
    const n = this.columns.length;
    if (!n) return;
    this.focus((this.focusedIndex + (forward ? 1 : n - 1)) % n);
  }

  // MARK: Developer columns

  devTools(page: Page): Page | null {
    return this.columns.find((c) => c.isDevTools && c.inspectedPage === page) ?? null;
  }

  /** Shows or hides the DevTools column next to `page`. Focus stays on the page. */
  toggleDevTools(page: Page) {
    const existing = this.devTools(page);
    if (existing) {
      this.close(existing);
      return;
    }
    const tools = new Page({ devToolsFor: page });
    this.customWidths.set(tools.id, this.devToolsFraction());
    this.insert(tools, page, false);
  }

  /** DevTools open at the width they were last dragged to; at first ~2/5 of the stage (≥ 480 px). */
  private devToolsFraction() {
    const saved = Number(settings.get('devtools.widthFraction', 0));
    if (saved > 0) return saved;
    const usable = this.geometry.usableWidth;
    if (usable <= 0) return 0.4;
    return Math.min(0.6, Math.max(0.4, 480 / usable));
  }

  /** Opens the same URL in a device-sized column that scrolls in step with the original. */
  openResponsivePreview(page: Page, preset: DevicePreset) {
    const existing = this.previews(page)[0];
    if (existing) {
      existing.setDevice({ preset, isLandscape: false });
      return;
    }
    if (!page.url) return;
    const device: DeviceFrame = { preset, isLandscape: false };
    const preview = this.makePage({ ephemeral: true, device });
    this.previewSources.set(preview.id, page);
    this.insert(preview, page, false);
    preview.load(page.url);
    page.syncsScroll = true;
    preview.syncsScroll = true;
    page.onScroll = (fraction) => this.previews(page).forEach((p) => p.scrollToFraction(fraction));
    preview.onScroll = (fraction) => page.scrollToFraction(fraction);
    page.setScrollSync(true);
  }

  /** The focused column plus the DevTools and previews right after it. */
  get focusSpan(): number {
    const focused = this.focused;
    if (!focused) return 1;
    let span = 1;
    for (let i = this.focusedIndex + 1; i < this.columns.length && this.isCompanion(this.columns[i], focused); i++) span++;
    return span;
  }

  companions(page: Page): Page[] {
    const index = this.columns.indexOf(page);
    if (index < 0) return [];
    const out: Page[] = [];
    for (let i = index + 1; i < this.columns.length && this.isCompanion(this.columns[i], page); i++) out.push(this.columns[i]);
    return out;
  }

  previewSource(page: Page): Page | null {
    return this.previewSources.get(page.id) ?? null;
  }

  private insertionIndex(source: Page) {
    const index = this.columns.indexOf(source);
    if (index < 0) return this.columns.length;
    return index + 1 + this.companions(source).length;
  }

  isCompanion(column: Page, page: Page) {
    return column.inspectedPage === page || this.previewSources.get(column.id) === page;
  }

  private previews(page: Page) {
    return this.columns.filter((c) => this.previewSources.get(c.id) === page);
  }

  private unlinkPreview(page: Page) {
    const source = this.previewSources.get(page.id);
    if (!source) return;
    this.previewSources.delete(page.id);
    if (this.previews(source).length === 0) {
      source.syncsScroll = false;
      source.onScroll = undefined;
      source.setScrollSync(false);
    }
  }

  // MARK: Widths

  widthFraction(page: Page): number | null {
    return this.customWidths.get(page.id) ?? null;
  }

  /** Where the trail is showing right now. */
  get displayedOffset(): number {
    return this.dragOffset ?? (this.restingOffset != null ? this.geometry.clamped(this.restingOffset) : this.geometry.targetOffset(this.focusedIndex, this.focusSpan));
  }

  /** Starts dragging one edge of `page`: only that column changes width; its neighbours slide. */
  beginResize(page: Page, edge: Edge) {
    const index = this.columns.indexOf(page);
    if (index < 0) return;
    this.activeResize = { id: page.id, edge, width: this.geometry.width(index), offset: this.displayedOffset };
    this.isResizing = true;
  }

  /** `delta` is how far the pointer moved since the drag began. */
  resize(delta: number) {
    const r = this.activeResize;
    if (!r) return;
    const usable = this.geometry.usableWidth;
    if (usable <= 0) return;
    const minimum = Math.min(Metrics.minResizedColumnWidth, usable);
    const width = Math.min(Math.max(r.width + (r.edge === 'trailing' ? delta : -delta), minimum), usable);
    this.customWidths.set(r.id, width / usable);
    // Dragging the leading edge: the columns before it move out of the way.
    this.dragOffset = r.edge === 'leading' ? r.offset + (width - r.width) : r.offset;
  }

  endResize() {
    const r = this.activeResize;
    if (!r) return;
    this.activeResize = null;
    const page = this.columns.find((c) => c.id === r.id);
    const fraction = page ? this.customWidths.get(page.id) : undefined;
    if (page?.isDevTools && fraction != null) settings.set('devtools.widthFraction', fraction);
    const rest = this.dragOffset;
    this.isResizing = false;
    this.dragOffset = null;
    this.restingOffset = rest;
    this.onChange();
  }

  /** Double-click on an edge: the column goes back to its default width. */
  resetWidth(page: Page) {
    this.customWidths.delete(page.id);
    this.restingOffset = null;
    this.onChange();
  }

  /** The focused column grows or shrinks by a tenth of the stage. */
  resizeFocused(step: number) {
    const page = this.focused;
    if (!page || this.columns.length <= 1 || page.device) return;
    const usable = this.geometry.usableWidth;
    if (usable <= 0) return;
    const current = this.geometry.width(this.focusedIndex) / usable;
    const minimum = Math.min(Metrics.minResizedColumnWidth / usable, 1);
    this.customWidths.set(page.id, Math.min(Math.max(current + step, minimum), 1));
    this.restingOffset = null;
    this.onChange();
  }

  // MARK: Swipes

  /** `delta` follows the fingers: positive moves the trail right (towards earlier columns). */
  scroll(delta: number) {
    const next = (this.unbandedDrag ?? this.displayedOffset) - delta;
    this.unbandedDrag = next;
    this.dragOffset = this.geometry.rubberBanded(next);
  }

  /** Snaps to the column the gesture is heading for. `velocity` is in px/s. */
  endScroll(velocity: number) {
    const drag = this.unbandedDrag;
    if (drag == null) return;
    let target = this.geometry.nearestIndex(drag - velocity * 0.18);
    // A deliberate flick always moves at least one column.
    if (target === this.focusedIndex && Math.abs(velocity) > 350) {
      target = Math.min(Math.max(this.focusedIndex + (velocity < 0 ? 1 : -1), 0), this.columns.length - 1);
    }
    this.focus(target);
  }
}

// Pure layout maths for the trail (port of TrailGeometry.swift). Offsets are in
// "content" space: 0 means the leading inset of the first column sits at the
// stage's left edge.
//
// Default widths: one column fills the stage; with more, the stage is split into
// `columnsPerScreen` (2 for Balanced), and anything beyond that scrolls. A column
// the user resized keeps its own share of the stage. A lone column always fills it.

export const Metrics = {
  toolbarHeight: 56,
  toolbarPadding: 16,
  capsuleHeight: 32,
  /** The vertical app capsule on the left. */
  capsuleWidth: 42,
  stageInset: 12,
  minColumnWidth: 420,
  /** How narrow a column can be dragged. */
  minResizedColumnWidth: 300,
  /** Window-controls island on the right (Windows and Linux have no traffic lights). */
  windowControlsWidth: 104,
};

export class TrailGeometry {
  readonly widths: number[];

  constructor(
    readonly stageWidth = 0,
    readonly gap = 0,
    readonly inset = 0,
    columnsPerScreen = 2,
    customFractions: (number | null)[] = [],
  ) {
    const usable = Math.max(0, stageWidth - inset * 2);
    const split = Math.min(customFractions.length, columnsPerScreen);
    const standard = split > 0 ? (usable - (split - 1) * gap) / split : usable;
    const minimum = Math.min(Metrics.minColumnWidth, usable);
    const resizedMinimum = Math.min(Metrics.minResizedColumnWidth, usable);
    if (customFractions.length === 1) {
      this.widths = [usable];
      return;
    }
    this.widths = customFractions.map((fraction) =>
      fraction == null ? Math.min(usable, Math.max(minimum, standard)) : Math.min(usable, Math.max(resizedMinimum, fraction * usable)),
    );
  }

  get count() {
    return this.widths.length;
  }

  get usableWidth() {
    return Math.max(0, this.stageWidth - this.inset * 2);
  }

  get contentWidth() {
    if (this.count === 0) return 0;
    return this.inset * 2 + this.widths.reduce((a, b) => a + b, 0) + (this.count - 1) * this.gap;
  }

  x(index: number) {
    let x = this.inset + index * this.gap;
    for (let i = 0; i < index && i < this.count; i++) x += this.widths[i];
    return x;
  }

  width(index: number) {
    return this.widths[index] ?? 0;
  }

  /** Columns on the stage at `offset`, or within `margin` of it. */
  indicesOnStage(offset: number, margin: number): Set<number> {
    const out = new Set<number>();
    for (let i = 0; i < this.count; i++) {
      const start = this.x(i) - offset;
      if (start + this.width(i) > -margin && start < this.stageWidth + margin) out.add(i);
    }
    return out;
  }

  private get maxOffset() {
    return Math.max(0, this.contentWidth - this.stageWidth);
  }

  /** Centre the focused column (and `span - 1` companions after it), within the trail's ends. */
  targetOffset(index: number, span = 1) {
    if (this.contentWidth <= this.stageWidth) return -(this.stageWidth - this.contentWidth) / 2;
    const last = Math.min(index + Math.max(span, 1) - 1, this.count - 1);
    const start = this.x(index);
    const end = this.x(last) + this.width(last);
    const ideal = end - start > this.stageWidth - this.inset * 2 ? start - this.inset : (start + end) / 2 - this.stageWidth / 2;
    return Math.min(Math.max(ideal, 0), this.maxOffset);
  }

  clamped(offset: number) {
    if (this.contentWidth <= this.stageWidth) return -(this.stageWidth - this.contentWidth) / 2;
    return Math.min(Math.max(offset, 0), this.maxOffset);
  }

  nearestIndex(offset: number) {
    if (this.count === 0) return 0;
    let best = 0;
    for (let i = 1; i < this.count; i++) {
      if (Math.abs(this.targetOffset(i) - offset) < Math.abs(this.targetOffset(best) - offset)) best = i;
    }
    return best;
  }

  /** Resistance past either end while dragging. */
  rubberBanded(offset: number) {
    const low = Math.min(this.targetOffset(0), 0);
    const high = Math.max(this.targetOffset(Math.max(this.count - 1, 0)), this.maxOffset);
    const dimension = Math.max(this.stageWidth, 1);
    const rubber = (distance: number) => (1 - 1 / ((distance * 0.55) / dimension + 1)) * dimension;
    if (offset < low) return low - rubber(low - offset);
    if (offset > high) return high + rubber(offset - high);
    return offset;
  }

  equals(other: TrailGeometry) {
    return (
      other.stageWidth === this.stageWidth &&
      other.gap === this.gap &&
      other.inset === this.inset &&
      other.widths.length === this.widths.length &&
      other.widths.every((w, i) => w === this.widths[i])
    );
  }
}

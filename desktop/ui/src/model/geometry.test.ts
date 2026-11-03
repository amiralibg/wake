import { describe, expect, it } from 'vitest';
import { TrailGeometry } from './geometry';

describe('site minimum widths', () => {
  it('raises a column to its minimum and caps it at the stage', () => {
    const g = new TrailGeometry(1000, 10, 0, 2, [null, null, 0.3, null], [800, null, 600, 5000]);
    expect(g.widths).toEqual([800, 495, 600, 1000]);
  });

  it('leaves a lone column filling the stage', () => {
    expect(new TrailGeometry(1000, 10, 0, 2, [null], [800]).widths).toEqual([1000]);
  });
});

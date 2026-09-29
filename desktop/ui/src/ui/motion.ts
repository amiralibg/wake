// Motion helpers: springs (the Mac app's Motion.swift values) and mount/unmount
// transitions for things that appear on demand.

import { useEffect, useRef, useState } from 'react';

/** response (s) and damping fraction, as SwiftUI's `.spring(response:dampingFraction:)`. */
export const Springs = {
  /** Columns sliding, opening and closing. */
  trail: { response: 0.3, damping: 0.9 },
  /** The Deck and other large surfaces. */
  deck: { response: 0.34, damping: 0.86 },
  /** Toolbars, palettes, panels appearing. */
  chrome: { response: 0.24, damping: 0.88 },
  hover: { response: 0.18, damping: 0.75 },
};

export class Spring {
  value: number;
  velocity = 0;
  target: number;

  constructor(value: number, private readonly config = Springs.trail) {
    this.value = value;
    this.target = value;
  }

  jump(value: number) {
    this.value = value;
    this.target = value;
    this.velocity = 0;
  }

  /** Advances by `dt` seconds; returns whether it's still moving. */
  step(dt: number): boolean {
    const stiffness = Math.pow((2 * Math.PI) / this.config.response, 2);
    const damping = (4 * Math.PI * this.config.damping) / this.config.response;
    // Small substeps keep a stiff spring stable at low frame rates.
    let remaining = Math.min(dt, 0.064);
    while (remaining > 0) {
      const h = Math.min(remaining, 1 / 240);
      const force = -stiffness * (this.value - this.target) - damping * this.velocity;
      this.velocity += force * h;
      this.value += this.velocity * h;
      remaining -= h;
    }
    if (Math.abs(this.value - this.target) < 0.05 && Math.abs(this.velocity) < 0.5) {
      this.value = this.target;
      this.velocity = 0;
      return false;
    }
    return true;
  }
}

/**
 * Keeps something mounted while it animates out. `visible` turns true a frame
 * after mounting (so CSS transitions run) and false immediately on hide.
 */
export function usePresence(show: boolean, exitMs = 220) {
  const [mounted, setMounted] = useState(show);
  const [visible, setVisible] = useState(false);
  const timer = useRef(0);
  useEffect(() => {
    clearTimeout(timer.current);
    if (show) {
      setMounted(true);
      const frame = requestAnimationFrame(() => requestAnimationFrame(() => setVisible(true)));
      return () => cancelAnimationFrame(frame);
    }
    setVisible(false);
    timer.current = window.setTimeout(() => setMounted(false), exitMs);
    return () => clearTimeout(timer.current);
  }, [show, exitMs]);
  return { mounted, visible };
}

/** Calls `onOutside` for a pointer-down outside `ref` (menus, popovers). */
export function useOutsideClick(ref: React.RefObject<HTMLElement | null>, active: boolean, onOutside: () => void) {
  const handler = useRef(onOutside);
  handler.current = onOutside;
  useEffect(() => {
    if (!active) return;
    const listener = (event: PointerEvent) => {
      if (ref.current && !ref.current.contains(event.target as Node)) handler.current();
    };
    const id = setTimeout(() => window.addEventListener('pointerdown', listener, true));
    return () => {
      clearTimeout(id);
      window.removeEventListener('pointerdown', listener, true);
    };
  }, [active, ref]);
}

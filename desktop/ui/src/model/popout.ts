// Pop Out (port of PopOut.swift): a picked element floats in its own always-on-top
// window, live. The element lives in a second copy of the page (an engine can't
// draw one DOM element of a page in another view), laid out at the source's
// width and clipped to the element by shared/scripts/popout-isolate.js.

import { host } from '../host/host';
import type { PopOutPick } from './page';

export const POPOUT_HEADER = 34;
const MAX_SIZE = { width: 760, height: 620 };

/** Big elements are shown smaller (page zoom keeps their layout). */
export function popOutScale(rect: { width: number; height: number }) {
  if (rect.width <= 0 || rect.height <= 0) return 1;
  return Math.max(0.3, Math.min(1, MAX_SIZE.width / rect.width, MAX_SIZE.height / rect.height));
}

export function popOutWindowSize(rect: { width: number; height: number }) {
  const scale = popOutScale(rect);
  const content = { width: Math.max(1, rect.width * scale), height: Math.max(1, rect.height * scale) };
  return { width: Math.round(Math.max(280, content.width)), height: Math.round(content.height + POPOUT_HEADER) };
}

let windowID = 0;

export const popOuts = {
  setWindow(id: number) {
    windowID = id;
  },
  open(pick: PopOutPick) {
    const size = popOutWindowSize(pick.rect);
    const query = 'popout=' + encodeURIComponent(JSON.stringify({ ...pick, source: windowID }));
    host.send('window.new', { query, popout: true, width: size.width, height: size.height });
  },
};

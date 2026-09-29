// Device sizes for the responsive preview (port of DevicePreset.swift), in CSS
// pixels, portrait.

export type DeviceKind = 'phone' | 'tablet' | 'custom';

export interface DevicePreset {
  name: string;
  width: number;
  height: number;
  kind: DeviceKind;
}

export const PHONES: DevicePreset[] = [
  { name: 'iPhone SE', width: 375, height: 667, kind: 'phone' },
  { name: 'iPhone 16', width: 393, height: 852, kind: 'phone' },
  { name: 'iPhone 16 Pro Max', width: 440, height: 956, kind: 'phone' },
  { name: 'Android · Pixel 9', width: 412, height: 915, kind: 'phone' },
];

export const TABLETS: DevicePreset[] = [
  { name: 'iPad mini', width: 744, height: 1133, kind: 'tablet' },
  { name: 'iPad Air 11″', width: 820, height: 1180, kind: 'tablet' },
  { name: 'iPad Pro 13″', width: 1032, height: 1376, kind: 'tablet' },
];

export const DEFAULT_PHONE = PHONES[1];

export const customPreset = (width: number, height: number): DevicePreset => ({ name: 'Custom', width, height, kind: 'custom' });

/** Phones get a mobile user agent so sites serve their phone layout. */
export function userAgent(preset: DevicePreset): string | null {
  if (preset.kind !== 'phone') return null;
  if (preset.name.startsWith('Android')) {
    return 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36';
  }
  return 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
}

export const menuTitle = (p: DevicePreset) => `${p.name} · ${p.width}×${p.height}`;

export interface DeviceFrame {
  preset: DevicePreset;
  isLandscape: boolean;
}

export const DEVICE_HEADER = 44;
export const DEVICE_PADDING = 14;
export const DEVICE_MIN_COLUMN = 340;

export function viewport(frame: DeviceFrame) {
  return frame.isLandscape
    ? { width: frame.preset.height, height: frame.preset.width }
    : { width: frame.preset.width, height: frame.preset.height };
}

/** Scale that fits the viewport into `available` without going above 100%. */
export function fitScale(view: { width: number; height: number }, available: { width: number; height: number }) {
  if (view.width <= 0 || view.height <= 0) return 1;
  return Math.max(0.2, Math.min(1, available.width / view.width, available.height / view.height));
}

/** Column width that shows the whole device at the largest scale the stage allows. */
export function deviceColumnWidth(frame: DeviceFrame, stageHeight: number, maxWidth: number) {
  const chrome = DEVICE_HEADER + DEVICE_PADDING * 2;
  const view = viewport(frame);
  const scale = fitScale(view, { width: maxWidth - DEVICE_PADDING * 2, height: stageHeight - chrome });
  return Math.min(maxWidth, Math.max(DEVICE_MIN_COLUMN, view.width * scale + DEVICE_PADDING * 2));
}

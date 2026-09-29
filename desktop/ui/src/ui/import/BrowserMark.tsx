// A browser's mark: its initial on its brand colour. The host can't read other
// apps' icons portably, and a letter reads fine at this size.

const COLORS: Record<string, string> = {
  Chrome: '#4285f4',
  'Chrome Beta': '#4285f4',
  Chromium: '#5f86d8',
  Edge: '#0c8fd8',
  Brave: '#fb542b',
  Vivaldi: '#ef3939',
  Opera: '#ff1b2d',
  'Opera GX': '#fa1e4e',
  Firefox: '#ff7139',
  Zen: '#f76f53',
  Waterfox: '#3fa9f5',
  LibreWolf: '#00acff',
  Floorp: '#1a6cf0',
};

export function BrowserMark({ browser, size = 24 }: { browser: string; size?: number }) {
  return (
    <span
      className="browser-mark"
      aria-hidden
      style={{ width: size, height: size, fontSize: size * 0.46, background: COLORS[browser] ?? 'var(--text-3)' }}
    >
      {browser.slice(0, 1)}
    </span>
  );
}

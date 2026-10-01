// A responsive preview (DevicePreviewColumn.swift): the page laid out at a real
// device's CSS size, shown whole. When the device is taller than the stage it's
// scaled down with page zoom, which keeps the CSS viewport at the device size.

import { observer } from 'mobx-react-lite';
import { useEffect, useState } from 'react';
import { RotateCw, RefreshCw, X, Smartphone, Tablet, SquareDashed } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import type { Page } from '../../model/page';
import { DEVICE_HEADER, DEVICE_PADDING, PHONES, TABLETS, customPreset, fitScale, menuTitle, viewport } from '../../model/device';
import { Menu, MenuItem, MenuSeparator } from '../common/Menu';
import type { Rect } from './engine';

/** Where the preview's webview goes inside its column. */
export function deviceContentRect(page: Page, card: Rect): Rect | null {
  if (!page.device) return card;
  const view = viewport(page.device);
  const available = { width: card.w - DEVICE_PADDING * 2, height: card.h - DEVICE_HEADER - DEVICE_PADDING * 2 };
  const scale = fitScale(view, available);
  const w = view.width * scale;
  const h = view.height * scale;
  return {
    x: card.x + (card.w - w) / 2,
    y: card.y + DEVICE_HEADER + (card.h - DEVICE_HEADER - h) / 2,
    w,
    h,
  };
}

export const DevicePreviewColumn = observer(function DevicePreviewColumn({ page, browser }: { page: Page; browser: BrowserModel }) {
  const device = page.device!;
  const view = viewport(device);
  const [box, setBox] = useState<{ width: number; height: number } | null>(null);
  const scale = box ? fitScale(view, { width: box.width - DEVICE_PADDING * 2, height: box.height - DEVICE_PADDING * 2 }) : 1;

  useEffect(() => {
    if (Math.abs(page.zoom - scale) > 0.001) page.setZoom(scale);
  }, [page, scale]);

  const radius = (device.preset.kind === 'phone' ? 38 : 20) * scale;
  const Icon = device.preset.kind === 'phone' ? Smartphone : device.preset.kind === 'tablet' ? Tablet : SquareDashed;

  return (
    <div className="device-column">
      <div className="device-header">
        <Menu
          browser={browser}
          label={
            <span className="device-name">
              <Icon size={14} /> {device.preset.name}
            </span>
          }
        >
          {PHONES.map((p) => (
            <MenuItem key={p.name} onSelect={() => page.setDevice({ preset: p, isLandscape: device.isLandscape })} checked={p.name === device.preset.name}>
              {menuTitle(p)}
            </MenuItem>
          ))}
          <MenuSeparator />
          {TABLETS.map((p) => (
            <MenuItem key={p.name} onSelect={() => page.setDevice({ preset: p, isLandscape: device.isLandscape })} checked={p.name === device.preset.name}>
              {menuTitle(p)}
            </MenuItem>
          ))}
        </Menu>
        <SizeFields page={page} width={view.width} height={view.height} />
        <button className="icon-button" title="Rotate" onClick={() => page.setDevice({ ...device, isLandscape: !device.isLandscape })}>
          <RotateCw size={14} />
        </button>
        <span style={{ flex: 1 }} />
        <span className="secondary device-zoom" title={page.zoom < 0.999 ? 'Scaled to fit the column; the page still lays out at the full device size' : 'Actual size'}>
          {Math.round(page.zoom * 100)}%
        </span>
        <button className="icon-button" title="Reload preview" onClick={() => page.reload()}>
          <RefreshCw size={13} />
        </button>
        <button className="icon-button" title="Close preview" onClick={() => browser.trail.close(page)}>
          <X size={14} />
        </button>
      </div>
      <div
        className="device-stage"
        ref={(el) => {
          if (!el) return;
          const r = el.getBoundingClientRect();
          if (!box || Math.abs(box.width - r.width) > 0.5 || Math.abs(box.height - r.height) > 0.5) setBox({ width: r.width, height: r.height });
        }}
      >
        <div className="device-screen" style={{ width: view.width * scale, height: view.height * scale, borderRadius: radius }}>
          {page.snapshot && <img src={page.snapshot} alt="" className="card-snapshot" />}
        </div>
      </div>
    </div>
  );
});

function SizeFields({ page, width, height }: { page: Page; width: number; height: number }) {
  const [w, setW] = useState(String(width));
  const [h, setH] = useState(String(height));
  useEffect(() => {
    setW(String(width));
    setH(String(height));
  }, [width, height]);
  const apply = () => {
    const nw = Number(w);
    const nh = Number(h);
    if (!(nw >= 200 && nh >= 200 && nw <= 3000 && nh <= 3000)) {
      setW(String(width));
      setH(String(height));
      return;
    }
    if (nw !== width || nh !== height) page.setDevice({ preset: customPreset(nw, nh), isLandscape: false });
  };
  const field = (value: string, set: (v: string) => void) => (
    <input
      className="size-field"
      value={value}
      onChange={(e) => set(e.target.value.replace(/\D/g, ''))}
      onKeyDown={(e) => e.key === 'Enter' && apply()}
      onBlur={apply}
      title="Type a width or height and press Enter"
    />
  );
  return (
    <span className="size-fields">
      {field(w, setW)}
      <span className="secondary">×</span>
      {field(h, setH)}
    </span>
  );
}

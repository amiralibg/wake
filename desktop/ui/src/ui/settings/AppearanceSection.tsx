import { observer } from 'mobx-react-lite';
import { settings, ACCENTS, GAP_PRESETS, CORNER_PRESETS, type Accent, type Glass, type PageWidth, type Theme } from '../../model/settings';
import { Group, Row, Segmented } from './components';

export const AppearanceSection = observer(function AppearanceSection() {
  return (
    <>
      <AppearancePreview />
      <Group>
        <Row label="Theme">
          <div className="theme-swatches">
            {(['light', 'dark', 'auto'] as Theme[]).map((theme) => (
              <button key={theme} className={`theme-swatch ${settings.theme === theme ? 'is-selected' : ''}`} onClick={() => settings.set('appearance.theme', theme)} aria-label={theme}>
                <span className={`swatch-art swatch-${theme}`}>
                  <span className="swatch-bar" />
                  <span className="swatch-panel" />
                </span>
                <span>{theme[0].toUpperCase() + theme.slice(1)}</span>
              </button>
            ))}
          </div>
        </Row>
        <Row label="Accent color">
          <div className="accent-dots">
            {(Object.keys(ACCENTS) as Accent[]).map((accent) => (
              <button
                key={accent}
                className={`accent-dot ${settings.accent === accent ? 'is-selected' : ''}`}
                style={{ '--dot': ACCENTS[accent] } as React.CSSProperties}
                title={accent[0].toUpperCase() + accent.slice(1)}
                aria-label={accent}
                onClick={() => settings.set('appearance.accent', accent)}
              />
            ))}
          </div>
        </Row>
        <Row label="Glass">
          <Segmented<Glass>
            value={settings.glass}
            options={[
              { value: 'subtle', label: 'Subtle' },
              { value: 'balanced', label: 'Balanced' },
              { value: 'clear', label: 'Clear' },
            ]}
            onChange={(v) => settings.set('appearance.glass', v)}
          />
        </Row>
      </Group>
      <Group title="Trail layout">
        <Row label="Gap between pages">
          <div className="gap-control">
            <Segmented value={settings.gap} options={GAP_PRESETS} onChange={(v) => settings.set('appearance.gap', v)} />
            <input
              type="range"
              min={0}
              max={48}
              step={2}
              value={settings.gap}
              aria-label="Gap in pixels"
              onChange={(e) => settings.set('appearance.gap', Number(e.target.value))}
            />
            <span className="mono secondary gap-value">{settings.gap} px</span>
          </div>
        </Row>
        <Row label="Corner radius">
          <Segmented value={settings.cornerRadius} options={CORNER_PRESETS} onChange={(v) => settings.set('appearance.cornerRadius', v)} />
        </Row>
        <Row label="Page width">
          <Segmented<PageWidth>
            value={settings.pageWidth}
            options={[
              { value: 'narrow', label: 'Narrow' },
              { value: 'balanced', label: 'Balanced' },
              { value: 'wide', label: 'Wide' },
            ]}
            onChange={(v) => settings.set('appearance.pageWidth', v)}
          />
        </Row>
      </Group>
    </>
  );
});

/** A miniature Wake window drawn from the current settings (AppearancePreview.swift). */
const AppearancePreview = observer(function AppearancePreview() {
  const dark = settings.theme === 'dark' || (settings.theme === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
  const perScreen = settings.columnsPerScreen;
  const gap = settings.gap * 0.5;
  const radius = settings.cornerRadius * 0.5;
  const tint = { subtle: 0.7, balanced: 0.4, clear: 0.08 }[settings.glass];
  return (
    <div className={`appearance-preview ${dark ? 'is-dark' : ''}`} aria-label="Preview of the current appearance" role="img">
      <span className="preview-blob" style={{ background: '#f0874f', left: '8%', top: '-30%' }} />
      <span className="preview-blob" style={{ background: '#6c5ce7', left: '62%', top: '-10%' }} />
      <span className="preview-blob" style={{ background: '#19b3a6', left: '34%', top: '48%' }} />
      <div className="mini-window" style={{ background: dark ? `rgba(30,30,34,${0.5 + tint * 0.5})` : `rgba(246,246,248,${0.35 + tint * 0.6})` }}>
        <div className="mini-toolbar">
          <span className="mini-island">
            <span className="mini-bar" style={{ width: 22 }} />
            <span className="mini-dot" />
            <span className="mini-pill" />
            <span className="mini-dot" />
          </span>
          <span style={{ flex: 1 }} />
          <span className="mini-island" style={{ width: 90 }} />
          <span style={{ flex: 1 }} />
          <span className="mini-island" style={{ width: 40 }} />
        </div>
        <div className="mini-pages" style={{ gap }}>
          {[0, 1, 2, 3].map((i) => (
            <span
              key={i}
              className={`mini-page ${i === 0 ? 'is-focused' : ''}`}
              style={{ borderRadius: radius, flex: `0 0 calc((100% - ${(perScreen - 1) * gap}px) / ${perScreen})` }}
            >
              <span className="mini-bar" style={{ width: 40 }} />
              <span className="mini-bar faint" />
              <span className="mini-bar faint" style={{ width: 50 }} />
              {i === 0 && <span className="mini-loading" style={{ left: radius + 6, right: radius + 6 }} />}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
});

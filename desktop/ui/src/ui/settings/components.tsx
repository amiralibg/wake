// Building blocks for Settings (SettingsComponents.swift): groups of rows like
// System Settings, switches and segmented pickers.

import type { ReactNode } from 'react';

export function Group({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <section className="settings-group">
      {title && <h3 className="settings-group-title">{title}</h3>}
      <div className="settings-group-body">{children}</div>
    </section>
  );
}

/** Label on the left, control on the right; the control drops below when narrow. */
export function Row({ label, detail, children }: { label: ReactNode; detail?: ReactNode; children?: ReactNode }) {
  return (
    <div className="settings-row">
      <div className="settings-row-labels">
        <div className="settings-row-label">{label}</div>
        {detail && <div className="settings-row-detail secondary">{detail}</div>}
      </div>
      {children && <div className="settings-row-control">{children}</div>}
    </div>
  );
}

export function Switch({ checked, onChange, label }: { checked: boolean; onChange: (value: boolean) => void; label?: string }) {
  return (
    <button role="switch" aria-checked={checked} aria-label={label} className={`switch ${checked ? 'is-on' : ''}`} onClick={() => onChange(!checked)}>
      <span className="switch-knob" />
    </button>
  );
}

export function Segmented<T extends string | number | boolean>({
  value, options, onChange,
}: {
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
}) {
  return (
    <div className="segmented" role="radiogroup">
      {options.map((o) => (
        <button key={String(o.value)} role="radio" aria-checked={o.value === value} className={o.value === value ? 'is-selected' : ''} onClick={() => onChange(o.value)}>
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Select<T extends string>({ value, options, onChange }: { value: T; options: { value: T; label: string }[]; onChange: (value: T) => void }) {
  return (
    <select className="select" value={value} onChange={(e) => onChange(e.target.value as T)}>
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

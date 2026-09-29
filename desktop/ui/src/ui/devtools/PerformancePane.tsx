// Load timings and Core Web Vitals, a live frame-rate meter, page weight by type,
// DOM statistics, and a quick audit (PerformancePane.swift).
//
// Limitation: metrics an engine doesn't report are shown as "Not supported"
// rather than guessed. For CPU and layout profiling, use the engine's inspector.

import { observer } from 'mobx-react-lite';
import { useEffect, useState } from 'react';
import { RefreshCw, CircleCheck, TriangleAlert, OctagonX, ChevronRight } from 'lucide-react';
import type { Page } from '../../model/page';
import { inspector, type Audit, type Metrics } from '../../model/devtools-session';
import { bytes, milliseconds } from './common';

export const PerformancePane = observer(function PerformancePane({ page }: { page: Page }) {
  const session = inspector(page);
  const [expanded, setExpanded] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    const run = async () => {
      await session.loadMetrics();
      await session.runAudits();
      // Metrics settle as the page finishes loading; FPS is sampled every second.
      let tick = 0;
      while (live) {
        await session.sampleFPS();
        tick++;
        if (tick % 3 === 0) await session.loadMetrics();
        await new Promise((r) => setTimeout(r, 1000));
      }
    };
    void run();
    return () => {
      live = false;
      session.stopFPS();
    };
  }, [session, session.documentLoads]);

  const m = session.metrics;
  return (
    <div className="dt-scroll pad performance">
      <div className="perf-head">
        <strong>Page load</strong>
        <span style={{ flex: 1 }} />
        <button className="button small" onClick={() => page.reloadFromOrigin()}>
          Reload and Measure
        </button>
        <button
          className="icon-button small"
          title="Measure again"
          onClick={async () => {
            await session.loadMetrics();
            await session.runAudits();
          }}
        >
          <RefreshCw size={12} />
        </button>
      </div>
      {m ? (
        <>
          <Vitals m={m} />
          <FPS samples={session.fpsSamples} />
          <Weight m={m} />
          <Stats m={m} />
        </>
      ) : (
        <span className="spinner" />
      )}
      <Audits audits={session.audits} expanded={expanded} setExpanded={setExpanded} onRun={() => void session.runAudits()} />
    </div>
  );
});

function Vitals({ m }: { m: Metrics }) {
  const tiles: [string, string, number | null, 'ms' | 'score', [number, number] | null, boolean][] = [
    ['Time to First Byte', 'TTFB', m.ttfb, 'ms', [800, 1800], true],
    ['First Contentful Paint', 'FCP', m.fcp, 'ms', [1800, 3000], !!m.support.fcp],
    ['Largest Contentful Paint', 'LCP', m.lcp, 'ms', [2500, 4000], !!m.support.lcp],
    ['Cumulative Layout Shift', 'CLS', m.cls, 'score', [0.1, 0.25], !!m.support.cls],
    ['Interaction to Next Paint', 'INP', m.inp, 'ms', [200, 500], !!m.support.inp],
    ['DOMContentLoaded', 'DCL', m.dcl, 'ms', null, true],
    ['Load', 'Load', m.load, 'ms', null, true],
  ];
  return (
    <div className="vitals">
      {tiles.map(([name, short, value, unit, thresholds, supported]) => {
        const formatted = !supported || value == null ? '—' : unit === 'ms' ? milliseconds(value) : value.toFixed(3);
        let rating: [string, string, typeof CircleCheck] | null = null;
        if (supported && value != null && thresholds) {
          rating = value <= thresholds[0] ? ['Good', 'var(--green)', CircleCheck] : value <= thresholds[1] ? ['Needs work', 'var(--orange)', TriangleAlert] : ['Poor', 'var(--red)', OctagonX];
        }
        return (
          <div key={short} className="vital" title={name}>
            <span className="secondary vital-short">{short}</span>
            <span className={`vital-value ${value == null ? 'secondary' : ''}`}>{formatted}</span>
            {rating ? (
              <span className="vital-rating" style={{ color: rating[1] }}>
                {(() => {
                  const Icon = rating[2];
                  return <Icon size={10} />;
                })()}{' '}
                {rating[0]}
              </span>
            ) : (
              <span className="tertiary small">{supported ? (value == null ? 'Waiting…' : ' ') : 'Not supported'}</span>
            )}
          </div>
        );
      })}
    </div>
  );
}

function FPS({ samples }: { samples: number[] }) {
  const max = Math.max(120, (samples.length ? Math.max(...samples) : 60) + 10);
  const w = 300;
  const h = 80;
  const x = (i: number) => (i / 59) * w;
  const y = (v: number) => h - (v / max) * h;
  const points = samples.map((v, i) => `${x(i)},${y(v)}`).join(' ');
  const low = samples.slice(-30).length ? Math.min(...samples.slice(-30)) : null;
  return (
    <div className="perf-block">
      <div className="perf-row">
        <strong>Frame rate</strong>
        <span style={{ flex: 1 }} />
        <span className="tabular strong">{samples.length ? `${Math.round(samples[samples.length - 1])} fps` : '—'}</span>
        {low != null && <span className="secondary small tabular">low {Math.round(low)}</span>}
      </div>
      <svg className="fps-chart" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" role="img" aria-label="Frame rate over the last minute">
        <line x1="0" x2={w} y1={y(60)} y2={y(60)} className="fps-target" />
        {samples.length > 1 && (
          <>
            <polygon points={`0,${h} ${points} ${x(samples.length - 1)},${h}`} className="fps-area" />
            <polyline points={points} className="fps-line" />
          </>
        )}
      </svg>
      <div className="secondary small">Frames the page painted each second while this pane is open. Scroll or interact with the page to see drops.</div>
    </div>
  );
}

const TYPE_LABELS: Record<string, string> = { img: 'Images', script: 'Scripts', css: 'Styles & links', link: 'Styles & links', fetch: 'Fetch/XHR', xmlhttprequest: 'Fetch/XHR', other: 'Other' };

function Weight({ m }: { m: Metrics }) {
  const merged: { type: string; count: number; decoded: number }[] = [];
  for (const entry of m.byType) {
    const name = TYPE_LABELS[entry.type] ?? entry.type[0].toUpperCase() + entry.type.slice(1);
    const row = merged.find((r) => r.type === name);
    if (row) {
      row.count += entry.count;
      row.decoded += entry.decoded;
    } else merged.push({ type: name, count: entry.count, decoded: entry.decoded });
  }
  const rows = merged.filter((r) => r.decoded > 0 || r.count > 0).sort((a, b) => b.decoded - a.decoded).slice(0, 8);
  const top = Math.max(1, ...rows.map((r) => r.decoded));
  return (
    <div className="perf-block">
      <div className="perf-row">
        <strong>Page weight</strong>
        <span style={{ flex: 1 }} />
        <span className="secondary small tabular">
          {m.requests} requests · {bytes(m.transfer)} transferred · {bytes(m.decoded)} decoded
        </span>
      </div>
      {rows.length === 0 ? (
        <div className="secondary small">No subresources yet.</div>
      ) : (
        rows.map((r) => (
          <div key={r.type} className="weight-row">
            <span className="weight-label small">{r.type}</span>
            <span className="weight-bar">
              <span style={{ width: `${(r.decoded / top) * 100}%` }} />
            </span>
            <span className="secondary small tabular">
              {bytes(r.decoded)} · {r.count}
            </span>
          </div>
        ))
      )}
    </div>
  );
}

function Stats({ m }: { m: Metrics }) {
  const stat = (label: string, value: string) => (
    <>
      <span className="secondary small">{label}</span>
      <span className="mono small">{value}</span>
    </>
  );
  return (
    <div className="perf-block">
      <strong>Document</strong>
      <div className="stats-grid">
        {stat('DOM elements', String(m.domNodes))}
        {stat('Max depth', String(m.domDepth))}
        {stat('Scripts', String(m.scripts))}
        {stat('Stylesheets', String(m.styleSheets))}
        {stat('Images', String(m.images))}
        {stat('Iframes', String(m.iframes))}
        {stat('Viewport', m.viewport)}
        {stat('Pixel ratio', `${m.devicePixelRatio.toFixed(1)}×`)}
        {stat('Protocol', m.protocolName || '—')}
        {stat('Navigation', m.navigationType || '—')}
      </div>
    </div>
  );
}

function Audits({ audits, expanded, setExpanded, onRun }: { audits: Audit[]; expanded: string | null; setExpanded: (id: string | null) => void; onRun: () => void }) {
  const passed = audits.filter((a) => a.state === 'pass').length;
  const fraction = audits.length ? passed / audits.length : 0;
  const order = { fail: 0, warn: 1, pass: 2 };
  return (
    <div className="perf-block">
      <div className="perf-row">
        <svg width="36" height="36" viewBox="0 0 36 36" className="score-ring">
          <circle cx="18" cy="18" r="15" className="ring-track" />
          <circle cx="18" cy="18" r="15" className="ring-value" strokeDasharray={`${fraction * 94.2} 94.2`} transform="rotate(-90 18 18)" />
          <text x="18" y="22" textAnchor="middle">
            {Math.round(fraction * 100)}
          </text>
        </svg>
        <div className="audit-title">
          <strong>Audit</strong>
          <span className="secondary small">{audits.length ? `${passed} of ${audits.length} checks pass` : 'Checks for accessibility, SEO and loading problems.'}</span>
        </div>
        <span style={{ flex: 1 }} />
        <button className="button small" onClick={onRun}>
          Run Again
        </button>
      </div>
      <div className="audit-list">
        {[...audits]
          .sort((a, b) => order[a.state] - order[b.state])
          .map((a) => {
            const Icon = a.state === 'pass' ? CircleCheck : a.state === 'warn' ? TriangleAlert : OctagonX;
            const color = a.state === 'pass' ? 'var(--green)' : a.state === 'warn' ? 'var(--orange)' : 'var(--red)';
            return (
              <button key={a.id} className="audit-row" onClick={() => setExpanded(expanded === a.id ? null : a.id)} aria-label={`${a.title}: ${a.state}`}>
                <span className="audit-line">
                  <Icon size={13} color={color} />
                  <span style={{ flex: 1 }}>{a.title}</span>
                  {a.count > 0 && a.state !== 'pass' && <span className="secondary small tabular">{a.count}</span>}
                  <ChevronRight size={10} className="tertiary" style={{ transform: expanded === a.id ? 'rotate(90deg)' : undefined }} />
                </span>
                {expanded === a.id && a.detail && <span className="audit-detail mono secondary selectable">{a.detail}</span>}
              </button>
            );
          })}
      </div>
    </div>
  );
}

// First-launch welcome (OnboardingView.swift): bringing your old browser's data
// over, what the trail is, how Wake should look, where searches go, and the
// shortcuts worth knowing. Choices apply live and are the real settings. Shown
// again from Settings ▸ General ▸ Welcome tour.

import { observer } from 'mobx-react-lite';
import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { CheckCircle2, Circle, Loader2 } from 'lucide-react';
import type { BrowserModel } from '../../model/browser';
import { BrowserImporter, type ImportOptions } from '../../model/importer';
import { ENGINE_ORDER } from '../../model/search';
import { ACCENTS, settings, type Accent, type Theme } from '../../model/settings';
import { prettyKey } from '../../model/keys';
import { EnginePicker } from '../settings/SearchSection';
import { Segmented, Switch } from '../settings/components';
import { BrowserMark } from '../import/BrowserMark';
import { importHeadline } from '../import/ImportSheet';
import { WaterRenderer } from './water';
import { WindowControls } from '../toolbar/Toolbar';
import { host } from '../../host/host';
import icon from '../../assets/icon.png';
import '../settings/settings.css';
import '../import/import.css';
import './onboarding.css';

const STEPS = ['welcome', 'browsers', 'trail', 'look', 'search', 'shortcuts', 'ready'] as const;

const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

export const Onboarding = observer(function Onboarding({ browser }: { browser: BrowserModel }) {
  const [index, setIndex] = useState(0);
  const [forward, setForward] = useState(true);
  // Owned here, not by the step, so an import keeps running (and its summary
  // stays) when you move on while it works.
  const [imports] = useState(() => new BrowserImporter());
  const step = STEPS[index]!;
  const finish = () => browser.finishOnboarding();

  const go = (target: number) => {
    if (target === index || target < 0 || target >= STEPS.length) return;
    setForward(target > index);
    setIndex(target);
  };
  const canImport = step === 'browsers' && imports.canStart;
  const advance = () => {
    if (canImport) {
      void imports.start();
      return;
    }
    if (index === STEPS.length - 1) finish();
    else go(index + 1);
  };

  const keys = useRef({ advance, back: () => go(index - 1), finish });
  keys.current = { advance, back: () => go(index - 1), finish };
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA')) return;
      if (e.ctrlKey || e.altKey || e.metaKey) return;
      if (e.key === 'Enter' || e.key === 'ArrowRight') keys.current.advance();
      else if (e.key === 'ArrowLeft') keys.current.back();
      else if (e.key === 'Escape') keys.current.finish();
      else return;
      e.preventDefault();
      e.stopPropagation();
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, []);

  const primary = step === 'welcome' ? 'Get started' : canImport ? 'Import' : step === 'ready' ? 'Start browsing' : 'Continue';

  return (
    <div className="onboarding" style={{ '--accent': settings.accentColor } as CSSProperties}>
      <Water progress={index / (STEPS.length - 1)} dropID={index} />
      {/* The window has no title bar: this strip moves it, as the toolbar does elsewhere. */}
      <div className="onboarding-titlebar" onPointerDown={dragWindow}>
        {step !== 'ready' && (
          <button className="onboarding-link" onClick={finish} title="Skip (Esc)">
            Skip tour
          </button>
        )}
        <WindowControls browser={browser} />
      </div>
      <div className="onboarding-top" />
      <ScaleToFit>
        <div key={step} className={`onboarding-step ${forward ? 'from-right' : 'from-left'}`}>
          {step === 'welcome' && <WelcomeStep />}
          {step === 'browsers' && <ImportStep imports={imports} />}
          {step === 'trail' && <TrailStep />}
          {step === 'look' && <LookStep />}
          {step === 'search' && <SearchStep />}
          {step === 'shortcuts' && <ShortcutsStep />}
          {step === 'ready' && <ReadyStep imports={imports} />}
        </div>
      </ScaleToFit>
      <div className="onboarding-controls">
        <button className="onboarding-link back" onClick={() => go(index - 1)} disabled={index === 0} style={{ opacity: index === 0 ? 0 : 1 }}>
          Back
        </button>
        <span className="spacer" />
        <div className="progress-dots">
          {STEPS.map((s, i) => (
            <button
              key={s}
              className={`progress-dot ${i === index ? 'is-current' : i < index ? 'is-done' : ''}`}
              aria-label={`Step ${i + 1} of ${STEPS.length}`}
              onClick={() => go(i)}
            >
              <span />
            </button>
          ))}
        </div>
        <span className="spacer" />
        {canImport && (
          <button className="onboarding-link" onClick={() => go(index + 1)}>
            Not now
          </button>
        )}
        <button className="onboarding-primary pressable" onClick={advance}>
          {primary}
        </button>
      </div>
    </div>
  );
});

function dragWindow(event: React.PointerEvent) {
  if (event.button !== 0 || event.target !== event.currentTarget) return;
  if (event.detail === 2) host.send('window.toggleMaximize');
  else host.send('window.drag');
}

// MARK: The water

const Water = observer(function Water({ progress, dropID }: { progress: number; dropID: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const boat = useRef<HTMLDivElement>(null);
  const renderer = useRef<WaterRenderer | null>(null);
  const lastDrop = useRef(dropID);

  useEffect(() => {
    const water = new WaterRenderer(canvas.current!, boat.current, reduceMotion());
    renderer.current = water;
    const move = (e: PointerEvent) => water.pointerMoved(e.clientX, e.clientY);
    window.addEventListener('pointermove', move);
    return () => {
      window.removeEventListener('pointermove', move);
      water.dispose();
      renderer.current = null;
    };
  }, []);

  useEffect(() => {
    renderer.current?.setAccent(settings.accentColor);
  }, [settings.accentColor]);

  useEffect(() => {
    const drop = lastDrop.current !== dropID;
    lastDrop.current = dropID;
    renderer.current?.setProgress(progress, drop);
  }, [progress, dropID]);

  return (
    <div className="onboarding-water" aria-hidden>
      <canvas ref={canvas} />
      <div ref={boat} className="paper-boat">
        <PaperBoat />
      </div>
    </div>
  );
});

/** An origami paper boat: the hull and the two folds of the sail, lit from the left. */
function PaperBoat() {
  const paper = (white: number) => `rgb(${white * 255}, ${white * 0.99 * 255}, ${white * 0.95 * 255})`;
  const fold = (points: string, white: number) => (
    <polygon points={points} fill={paper(white)} stroke="rgba(0,0,0,0.08)" strokeWidth={0.5} strokeLinejoin="round" />
  );
  return (
    <svg width="54" height="36" viewBox="0 0 54 36">
      {fold('0,20 27,20 27,34 11,34', 0.74)}
      {fold('27,20 54,20 43,34 27,34', 0.9)}
      {fold('15,20 27,0 27,20', 0.84)}
      {fold('27,20 27,0 39,20', 0.98)}
    </svg>
  );
}

// MARK: Layout

/** Lays the step out at its natural size and shrinks it to fit a small window; never scales up. */
function ScaleToFit({ children }: { children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  useLayoutEffect(() => {
    const measure = () => {
      if (!outer.current || !inner.current) return;
      const natural = inner.current.scrollHeight;
      const available = outer.current.clientHeight;
      setScale(natural > 0 ? Math.min(1, available / natural) : 1);
    };
    const observer = new ResizeObserver(measure);
    observer.observe(outer.current!);
    observer.observe(inner.current!);
    measure();
    return () => observer.disconnect();
  }, []);
  return (
    <div ref={outer} className="scale-to-fit">
      <div ref={inner} className="scale-to-fit-content" style={{ transform: `scale(${scale})`, width: `min(${100 / scale}%, 900px)` }}>
        {children}
      </div>
    </div>
  );
}

/** A headline whose words rise out of a blur one after another. */
function RevealText({ text, size = 56, weight = 600, delay = 0 }: { text: string; size?: number; weight?: number; delay?: number }) {
  return (
    <h1 className="reveal-text" aria-label={text} style={{ fontSize: size, fontWeight: weight, letterSpacing: -size * 0.028, columnGap: size * 0.24 }}>
      {text.split(' ').map((word, i) => (
        <span key={i} aria-hidden style={{ animationDelay: `${delay + i * 0.07}s`, '--rise': `${size * 0.35}px` } as CSSProperties}>
          {word}
        </span>
      ))}
    </h1>
  );
}

/** Fades and lifts content in after the headline. */
function Arrive({ after, children, className }: { after: number; children: ReactNode; className?: string }) {
  return (
    <div className={`arrive ${className ?? ''}`} style={{ animationDelay: `${after}s` }}>
      {children}
    </div>
  );
}

function StepLayout({ eyebrow, title, detail, children }: { eyebrow: string; title: string; detail: string; children: ReactNode }) {
  return (
    <div className="step-layout">
      <div className="step-heading">
        <Arrive after={0}>
          <div className="step-eyebrow">{eyebrow}</div>
        </Arrive>
        <RevealText text={title} size={44} delay={0.05} />
        <Arrive after={0.25}>
          <p className="step-detail">{detail}</p>
        </Arrive>
      </div>
      <Arrive after={0.4} className="step-content">
        {children}
      </Arrive>
    </div>
  );
}

// MARK: Steps

function WelcomeStep() {
  return (
    <div className="welcome-step">
      <PageWake />
      <div className="step-heading">
        <RevealText text="Browse in a wake." size={72} weight={700} delay={0.35} />
        <Arrive after={0.8}>
          <p className="step-detail wide">
            Wake is a browser where every link opens as a column beside the page you came from. Your path stays in view, and nothing hides in a tab bar.
          </p>
        </Arrive>
      </div>
    </div>
  );
}

/** The icon's idea at hero size: a page, and the wake of pages trailing behind it. */
function PageWake() {
  const [shown, setShown] = useState(false);
  useEffect(() => {
    const frame = requestAnimationFrame(() => requestAnimationFrame(() => setShown(true)));
    return () => cancelAnimationFrame(frame);
  }, []);
  return (
    <div className="page-wake" aria-hidden>
      {[4, 3, 2, 1, 0].map((depth) => (
        <div
          key={depth}
          className="page-wake-item"
          style={{
            zIndex: 10 - depth,
            opacity: shown ? 1 - depth * 0.19 : 0,
            transform: shown
              ? `translateX(${-depth * 74 + 150}px) scale(${1 - depth * 0.08}) rotateY(${-8 - depth * 3}deg)`
              : 'translateX(360px) rotateY(-30deg)',
            transitionDelay: `${0.08 * (5 - depth)}s`,
          }}
        >
          <div className="page-wake-bob" style={{ animationDelay: `${-depth * 0.55}s`, '--amp': `${3 + depth * 1.5}px` } as CSSProperties}>
            <MiniPage lead={depth === 0} />
          </div>
        </div>
      ))}
    </div>
  );
}

function MiniPage({ lead = false, small = false }: { lead?: boolean; small?: boolean }) {
  return (
    <div className={`mini-page ${lead ? 'is-lead' : ''} ${small ? 'is-small' : ''}`}>
      <div className="mini-page-hero" />
      {[0, 1, 2, 3, 4].map((line) => (
        <div key={line} className="mini-page-line" style={{ marginRight: line === 4 ? 50 : 0 }} />
      ))}
    </div>
  );
}

// Browsers

const ImportStep = observer(function ImportStep({ imports }: { imports: BrowserImporter }) {
  useEffect(() => {
    void imports.refresh();
  }, [imports]);
  const selected = imports.selected;
  const browsers = imports.browsers;
  // Centred rows of even length (never one card alone on the last row).
  const rows = Math.max(1, Math.ceil(browsers.length / 6));
  const perRow = Math.max(1, Math.ceil(browsers.length / rows));
  const grid: string[][] = [];
  for (let i = 0; i < browsers.length; i += perRow) grid.push(browsers.slice(i, i + perRow));
  const profiles = selected ? imports.profilesOf(selected.browser) : [];
  const phase = imports.phase;

  return (
    <StepLayout
      eyebrow="Switching over"
      title="Bring your browser along."
      detail="Import your history, searches and sign-ins from the browser you use now. It isn't changed, and you can do this later from History ▸ Import."
    >
      <div className="import-step">
        {browsers.length === 0 && <p className="step-note">No other browsers found on this computer.</p>}
        <div className={`browser-grid ${imports.isIdle ? '' : 'is-disabled'}`}>
          {grid.map((row, r) => (
            <div key={r} className="browser-row">
              {row.map((name) => {
                const count = imports.profilesOf(name).length;
                const isSelected = selected?.browser === name;
                return (
                  <button key={name} className={`browser-card pressable ${isSelected ? 'is-selected' : ''}`} disabled={!imports.isIdle} onClick={() => imports.selectBrowser(name)}>
                    <BrowserMark browser={name} size={44} />
                    <span className="browser-card-name">{name}</span>
                    <span className="browser-card-caption">{count > 1 ? `${count} profiles` : ' '}</span>
                  </button>
                );
              })}
            </div>
          ))}
        </div>
        {profiles.length > 1 && (
          <select className="onboarding-select" value={imports.selection ?? ''} disabled={!imports.isIdle} onChange={(e) => (imports.selection = e.target.value)}>
            {profiles.map((p) => (
              <option key={p.id} value={p.id}>
                {p.profile ?? 'Default'}
              </option>
            ))}
          </select>
        )}
        <div className="import-phase">
          {phase.kind === 'idle' && selected && (
            <div className="include-chips">
              {(
                [
                  ['history', 'History'],
                  ['searches', 'Searches'],
                  ['cookies', 'Sign-ins'],
                  ['siteData', 'Site settings'],
                ] as [keyof ImportOptions, string][]
              ).map(([key, title]) => (
                <button key={key} className={`include-chip pressable ${imports.options[key] ? 'is-on' : ''}`} onClick={() => imports.setOption(key, !imports.options[key])} aria-pressed={imports.options[key]}>
                  {imports.options[key] ? <CheckCircle2 size={15} /> : <Circle size={15} />}
                  {title}
                </button>
              ))}
            </div>
          )}
          {phase.kind === 'running' && (
            <div className="import-running">
              <Loader2 size={15} className="spin" />
              {phase.step}
            </div>
          )}
          {phase.kind === 'finished' && (
            <div className="import-summary-step">
              <div className="import-headline">
                <CheckCircle2 size={17} />
                {importHeadline(phase.report)}
              </div>
              {phase.report.notes.map((note) => (
                <p key={note} className="step-note">
                  {note}
                </p>
              ))}
              <button className="onboarding-link accent" onClick={() => imports.reset()}>
                Import another browser
              </button>
            </div>
          )}
        </div>
      </div>
    </StepLayout>
  );
});

// Trail

const TrailStep = observer(function TrailStep() {
  return (
    <StepLayout
      eyebrow="The trail"
      title="Links open beside you."
      detail={`Click a link and it slides in as a new column. Go deeper and the trail scrolls; step back with ${prettyKey('ctrl+[')} or Shift-scroll and every page is still there.`}
    >
      <div className="trail-step">
        <TrailDemo />
        <div className="hints">
          <Hint keys="click" text="New column" />
          <Hint keys="Ctrl click" text="In the background" />
          <Hint keys="Alt click" text="Stay on the page" />
        </div>
        <div className="onboarding-segmented">
          <Segmented
            value={settings.linksOpenInNewColumn}
            options={[
              { value: true, label: 'In a new column' },
              { value: false, label: 'In the same page' },
            ]}
            onChange={(v) => settings.set('browsing.linksInNewColumn', v)}
          />
        </div>
      </div>
    </StepLayout>
  );
});

/** Columns arriving one after another, like following links. */
function TrailDemo() {
  const [count, setCount] = useState(0);
  useEffect(() => {
    if (reduceMotion()) {
      setCount(3);
      return;
    }
    const timer = window.setTimeout(() => setCount((c) => (c + 1) % 4), count === 0 ? 1200 : 1450);
    return () => clearTimeout(timer);
  }, [count]);
  const shown = Math.max(1, count);
  const lead = Math.max(0, count - 1);
  return (
    <div className="trail-demo" aria-label="Animation: pages opening as columns">
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          className="trail-demo-page"
          style={{ opacity: i < shown ? 1 : 0, transform: `translateX(${i < shown ? 0 : 50}px) scale(${i === lead ? 1 : 0.96})` }}
        >
          <MiniPage lead={i === lead} small />
        </div>
      ))}
    </div>
  );
}

function Hint({ keys, text }: { keys: string; text: string }) {
  return (
    <div className="hint">
      <span className="hint-keys">{keys}</span>
      <span>{text}</span>
    </div>
  );
}

// Look

const THEMES: { value: Theme; label: string }[] = [
  { value: 'auto', label: 'Auto' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
];

const LookStep = observer(function LookStep() {
  return (
    <StepLayout
      eyebrow="Make it yours"
      title="Pick a look."
      detail="Chrome floats as glass above your pages and only shows up when you need it. Change any of this later in Settings."
    >
      <div className="look-step">
        <div className="theme-cards">
          {THEMES.map((t) => {
            const selected = settings.theme === t.value;
            return (
              <button key={t.value} className={`theme-card pressable ${selected ? 'is-selected' : ''}`} aria-label={`${t.label} theme`} onClick={() => settings.set('appearance.theme', t.value)}>
                <div className="theme-preview">
                  {(t.value === 'auto' || t.value === 'light') && <ThemeSample dark={false} />}
                  {(t.value === 'auto' || t.value === 'dark') && <ThemeSample dark />}
                </div>
                <span>{t.label}</span>
              </button>
            );
          })}
        </div>
        <div className="accent-choices">
          {(Object.keys(ACCENTS) as Accent[]).map((accent) => (
            <button
              key={accent}
              className={`accent-choice pressable ${settings.accent === accent ? 'is-selected' : ''}`}
              style={{ '--dot': ACCENTS[accent] } as CSSProperties}
              aria-label={accent}
              title={accent[0]!.toUpperCase() + accent.slice(1)}
              onClick={() => settings.set('appearance.accent', accent)}
            >
              <span />
            </button>
          ))}
        </div>
      </div>
    </StepLayout>
  );
});

function ThemeSample({ dark }: { dark: boolean }) {
  return (
    <div className={`theme-sample ${dark ? 'is-dark' : ''}`}>
      <span className="theme-sample-bar" />
      <div className="theme-sample-pages">
        <span />
        <span />
      </div>
    </div>
  );
}

// Search

const SearchStep = observer(function SearchStep() {
  return (
    <StepLayout
      eyebrow="Search"
      title="Search your way."
      detail={`Type anything into ${prettyKey('ctrl+k')}. Addresses open, and everything else goes to the engine you choose here.`}
    >
      <div className="search-step">
        <EnginePicker value={settings.searchEngine} engines={ENGINE_ORDER.filter((e) => e !== 'custom')} onChange={(id) => settings.set('search.engine', id)} />
        <label className="suggestions-toggle">
          <Switch checked={settings.showsSearchSuggestions} onChange={(v) => settings.set('search.suggestions', v)} label="Show suggestions while I type" />
          Show suggestions while I type
        </label>
      </div>
    </StepLayout>
  );
});

// Shortcuts

const SHORTCUT_CARDS: { keys: string; title: string; detail: string }[] = [
  { keys: 'ctrl+k', title: 'Deck & search', detail: 'Every thread, live, plus search' },
  { keys: 'ctrl+t', title: 'New column', detail: 'Open a page beside this one' },
  { keys: 'ctrl+d', title: 'Save a moment', detail: 'Scroll spot, selection and why' },
  { keys: 'ctrl+\\', title: 'Zen', detail: 'Hide everything but the pages' },
  { keys: 'ctrl+shift+i', title: 'DevTools', detail: 'Elements, console, network…' },
  { keys: 'ctrl+w', title: 'Close column', detail: 'Never the window while pages remain' },
];

function ShortcutsStep() {
  // A keycap row presses itself in turn, so the grid reads like someone typing.
  const [pressed, setPressed] = useState(-1);
  useEffect(() => {
    if (reduceMotion()) return;
    const timer = window.setInterval(() => setPressed((p) => (p + 1) % SHORTCUT_CARDS.length), 600);
    return () => clearInterval(timer);
  }, []);
  return (
    <StepLayout
      eyebrow="Shortcuts"
      title="Six keys to remember."
      detail="Wake keeps its chrome out of the way, so the keyboard does the work. The full list lives in Settings ▸ General."
    >
      <div className="shortcut-grid">
        {SHORTCUT_CARDS.map((s, i) => (
          <div key={s.keys} className="shortcut-card" aria-label={`${prettyKey(s.keys)} ${s.title}: ${s.detail}`}>
            <div className="keycaps">
              {prettyKey(s.keys)
                .split('+')
                .map((k) => (
                  <span key={k} className={`keycap ${pressed === i ? 'is-pressed' : ''}`}>
                    {k}
                  </span>
                ))}
            </div>
            <div className="shortcut-text">
              <div className="shortcut-title">{s.title}</div>
              <div className="shortcut-detail">{s.detail}</div>
            </div>
          </div>
        ))}
      </div>
    </StepLayout>
  );
}

// Ready

const ReadyStep = observer(function ReadyStep({ imports }: { imports: BrowserImporter }) {
  const phase = imports.phase;
  const imported = phase.kind === 'finished' && phase.report.pages > 0 ? ` Your ${phase.report.source} history is waiting in ${prettyKey('ctrl+h')}.` : '';
  const look = settings.theme === 'auto' ? 'matching your system' : `${settings.theme} mode`;
  return (
    <div className="ready-step">
      <div className="ready-icon">
        {!reduceMotion() && [0, 1, 2].map((ring) => <span key={ring} className="ripple" style={{ animationDelay: `${ring * 0.5}s` }} />)}
        <Arrive after={0.1}>
          <img src={icon} width={120} height={120} alt="" />
        </Arrive>
      </div>
      <div className="step-heading">
        <RevealText text="You’re all set." size={64} weight={700} delay={0.2} />
        <Arrive after={0.55}>
          <p className="step-detail">
            {settings.searchName} for search, {look}, and a trail that remembers where you've been.{imported} Press Enter to start.
          </p>
        </Arrive>
      </div>
    </div>
  );
});

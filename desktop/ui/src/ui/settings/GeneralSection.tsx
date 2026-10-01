import { observer } from 'mobx-react-lite';
import type { BrowserModel } from '../../model/browser';
import { settings } from '../../model/settings';
import { updater } from '../../model/updater';
import { relativeTime } from '../../model/deck';
import { Group, Row, Segmented, Switch } from './components';

const SHORTCUTS: [string, string][] = [
  ['Open the Deck and search', 'Ctrl+K'],
  ['New column', 'Ctrl+T'],
  ['Go to address in this column', 'Ctrl+L'],
  ['Close column · close window', 'Ctrl+W  Ctrl+Shift+W'],
  ['Reopen closed column', 'Ctrl+Shift+T'],
  ['Duplicate column', 'Ctrl+Shift+D'],
  ['Previous / next column', 'Ctrl+[  Ctrl+]'],
  ['Cycle columns', 'Ctrl+Tab  Ctrl+Shift+Tab'],
  ['Previous / next column with a mouse', 'Shift + scroll'],
  ['Column mode, then focus · move · jump', 'Alt+W  h l  H L  1–9'],
  ['In column mode: width · close · new · done', '< > =  x  n  Esc'],
  ['Jump to column 1–8 · last', 'Ctrl+1 … Ctrl+8  Ctrl+9'],
  ['Move column left / right', 'Ctrl+Shift+PgUp  Ctrl+Shift+PgDn'],
  ['Wider / narrower column · default', 'Ctrl+Shift+=  Ctrl+Shift+−  Ctrl+Shift+0'],
  ['Zoom in / out · actual size', 'Ctrl+=  Ctrl+−  Ctrl+0'],
  ['Back / forward in page', 'Alt+←  Alt+→'],
  ['Reload · without cache · stop', 'Ctrl+R  Ctrl+Shift+R  Ctrl+.'],
  ['Copy page address', 'Ctrl+Shift+L'],
  ['Save moment · Moments', 'Ctrl+D  Ctrl+Shift+B'],
  ['History · searches', 'Ctrl+H  Ctrl+Shift+H'],
  ['Pop out an element', 'Ctrl+Shift+O'],
  ['New thread · new window', 'Ctrl+Shift+N  Ctrl+N'],
  ['DevTools · responsive preview', 'Ctrl+Shift+I  Ctrl+Shift+M'],
  ['Web Inspector · inspect element', 'F12  Ctrl+Shift+C'],
  ['Console · page source · empty caches', 'Ctrl+Shift+J  Ctrl+U  Ctrl+Shift+Del'],
  ['Developer mode for thread · components', 'Ctrl+Shift+E  Ctrl+Shift+X'],
  ['Pin page as app · show app 1–9', 'Ctrl+Shift+P  Alt+1 … Alt+9'],
  ['Zen · full screen', 'Ctrl+\\  F11'],
  ['Settings', 'Ctrl+,'],
];

export const GeneralSection = observer(function GeneralSection({ browser }: { browser: BrowserModel }) {
  return (
    <>
      <Group title="Browsing">
        <Row label="Clicked links open" detail="Ctrl-click opens a column in the background; Alt-click stays on the page.">
          <Segmented
            value={settings.linksOpenInNewColumn}
            options={[
              { value: true, label: 'In a new column' },
              { value: false, label: 'In the same page' },
            ]}
            onChange={(v) => settings.set('browsing.linksInNewColumn', v)}
          />
        </Row>
        <Row label="Resume your last thread" detail="New windows pick up where you left off.">
          <Switch checked={settings.restoresLastThread} onChange={(v) => settings.set('browsing.restoreThread', v)} />
        </Row>
        <Row label="Shift-scroll moves between columns" detail="With a mouse wheel. Off, Shift-scroll scrolls the page sideways.">
          <Switch checked={settings.shiftScrollMovesColumns} onChange={(v) => settings.set('browsing.shiftScrollColumns', v)} />
        </Row>
        <Row
          label="Column mode with Alt+W"
          detail="Like Vim's window keys: Alt+W, then h and l to move, H and L to reorder, x to close. (Ctrl+W closes the column on Windows and Linux.) Turn off if a site needs Alt+W."
        >
          <Switch checked={settings.columnModeKeyEnabled} onChange={(v) => settings.set('browsing.columnModeKey', v)} />
        </Row>
        <Row label="Apps and dev servers" detail="The capsule on the left. Hidden, it slides in when the pointer reaches the window's left edge.">
          <Segmented
            value={settings.capsuleHidesAtEdge}
            options={[
              { value: false, label: 'Always shown' },
              { value: true, label: 'At left edge' },
            ]}
            onChange={(v) => settings.set('browsing.capsuleHides', v)}
          />
        </Row>
      </Group>
      <UpdatesGroup />
      <Group>
        <Row label="Welcome tour" detail="The trail, your look, search and shortcuts, one screen each.">
          <button
            className="button"
            onClick={() => {
              browser.hideSettings();
              browser.showOnboarding();
            }}
          >
            Show Welcome Tour
          </button>
        </Row>
      </Group>
      <Group title="Keyboard shortcuts">
        {SHORTCUTS.map(([label, keys]) => (
          <div key={label} className="shortcut-row">
            <span>{label}</span>
            <span className="key-hint">{keys}</span>
          </div>
        ))}
      </Group>
    </>
  );
});

function updateDetail(): string {
  if (!updater.isAvailable) return updater.unavailableReason;
  if (updater.state === 'checking') return 'Checking…';
  const next = updater.available?.version;
  if (next && updater.handedOver) return `Wake ${next} is in your Downloads folder. Finish installing it in the window that opened, then restart Wake.`;
  if (updater.error) return updater.error;
  if (next) return `Wake ${next} is available.`;
  if (updater.lastChecked) return `Up to date. Last checked ${relativeTime(updater.lastChecked / 1000)}.`;
  return 'New versions come from GitHub releases.';
}

const UpdatesGroup = observer(function UpdatesGroup() {
  const detail = updateDetail();
  return (
    <Group title="Updates">
      <Row label={`Wake ${updater.version}`} detail={detail}>
        {updater.available ? (
          <button className="button primary" disabled={updater.state === 'installing'} onClick={() => void updater.install()}>
            {updater.state === 'installing' ? (updater.isManual ? 'Downloading…' : 'Installing…') : updater.isManual ? 'Download and Install' : 'Install and Restart'}
          </button>
        ) : (
          <button className="button" disabled={!updater.isAvailable || updater.state === 'checking'} onClick={() => void updater.check(true)}>
            Check Now
          </button>
        )}
      </Row>
      {updater.isAvailable && (
        <Row label="Check automatically" detail="Once a day. You choose when to install.">
          <Switch checked={updater.automaticallyChecks} onChange={(v) => updater.setAutomaticallyChecks(v)} />
        </Row>
      )}
    </Group>
  );
});

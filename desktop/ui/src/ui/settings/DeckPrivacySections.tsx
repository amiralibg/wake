import { observer } from 'mobx-react-lite';
import { useState } from 'react';
import type { BrowserModel } from '../../model/browser';
import { settings, type SinkAfter } from '../../model/settings';
import { history } from '../../model/history';
import { host } from '../../host/host';
import { Group, Row, Segmented, Switch } from './components';

export const DeckSection = observer(function DeckSection() {
  return (
    <Group>
      <Row label="Sink tabs after" detail="Untouched tabs sink below the waterline. They stay searchable.">
        <Segmented<SinkAfter>
          value={settings.sinkAfter}
          options={[
            { value: 'threeDays', label: '3 days' },
            { value: 'sevenDays', label: '7 days' },
            { value: 'fourteenDays', label: '14 days' },
            { value: 'never', label: 'Never' },
          ]}
          onChange={(v) => settings.set('deck.sinkAfter', v)}
        />
      </Row>
      <Row label="Keep playing and unsaved tabs afloat">
        <Switch checked={settings.keepActiveAfloat} onChange={(v) => settings.set('deck.keepActiveAfloat', v)} />
      </Row>
      <Row label="Show the Deck from the bottom edge" detail="Move the pointer to the bottom of the window to see your threads. Ctrl+K always opens it.">
        <Switch checked={settings.deckPeeksFromEdge} onChange={(v) => settings.set('deck.peekFromEdge', v)} />
      </Row>
    </Group>
  );
});

type Action = 'history' | 'websiteData';

export const PrivacySection = observer(function PrivacySection({ browser }: { browser: BrowserModel }) {
  const [confirming, setConfirming] = useState<Action | null>(null);
  const [done, setDone] = useState<Set<Action>>(new Set());
  const perform = async (action: Action) => {
    setConfirming(null);
    if (action === 'history') await history.clearAll();
    else await host.call('data.clearAll');
    setDone((d) => new Set([...d, action]));
  };
  return (
    <>
      <Group title="Bring your data">
        <Row label="Import from another browser" detail="History, searches, cookies and site storage from Chrome, Edge, Brave, Vivaldi, Opera, Chromium, Firefox and more.">
          <button
            className="button"
            onClick={() => {
              browser.hideSettings();
              browser.isImportingBrowserData = true;
            }}
          >
            Import…
          </button>
        </Row>
      </Group>
      <Group title="Your data">
        <Row label="Clear browsing history" detail="Forgets visited pages and searches (History, and Recent in Ctrl+K). Threads and pinned apps stay.">
          <button className="button" disabled={done.has('history')} onClick={() => setConfirming('history')}>
            {done.has('history') ? 'Cleared' : 'Clear…'}
          </button>
        </Row>
        <Row label="Clear cookies and website data" detail="Signs you out of every site and removes caches, local storage and cookies.">
          <button className="button" disabled={done.has('websiteData')} onClick={() => setConfirming('websiteData')}>
            {done.has('websiteData') ? 'Cleared' : 'Clear…'}
          </button>
        </Row>
      </Group>
      {confirming && (
        <div className="confirm-backdrop" onPointerDown={() => setConfirming(null)}>
          <div className="confirm glass-strong" onPointerDown={(e) => e.stopPropagation()}>
            <div className="confirm-title">{confirming === 'history' ? 'Clear browsing history?' : 'Clear all website data?'}</div>
            <div className="secondary">This can't be undone.</div>
            <div className="confirm-actions">
              <button className="button" onClick={() => setConfirming(null)}>
                Cancel
              </button>
              <button className="button primary danger-fill" onClick={() => void perform(confirming)}>
                Clear
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
});

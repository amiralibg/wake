import { observer } from 'mobx-react-lite';
import { useState } from 'react';
import { CircleCheck, Link2 } from 'lucide-react';
import { settings } from '../../model/settings';
import { ENGINE_ORDER, SEARCH_ENGINES, engineIcon, isValidTemplate, type SearchEngineID } from '../../model/search';
import { host } from '../../host/host';
import { Favicon } from '../common/Favicon';
import { Group, Row, Switch } from './components';

const SUGGESTION_SOURCE: Partial<Record<SearchEngineID, string>> = { google: 'Google', brave: 'Brave', bing: 'Bing', yahoo: 'Bing', ecosia: 'Ecosia' };

export const SearchSection = observer(function SearchSection() {
  return (
    <>
      <Group title="Search engine">
        <div className="engine-group">
          <div className="secondary small">Typed words in Ctrl+K and the address bar search here.</div>
          <EnginePicker value={settings.searchEngine} onChange={(id) => settings.set('search.engine', id)} />
          {settings.searchEngine === 'custom' && <CustomEngineField />}
        </div>
      </Group>
      <Group>
        <Row
          label="Search suggestions"
          detail={`Suggestions from ${SUGGESTION_SOURCE[settings.effectiveEngine] ?? 'DuckDuckGo'} while you type. Off, nothing leaves Wake until you press Enter.`}
        >
          <Switch checked={settings.showsSearchSuggestions} onChange={(v) => settings.set('search.suggestions', v)} />
        </Row>
      </Group>
      <BraveKeyGroup />
    </>
  );
});

export const EnginePicker = observer(function EnginePicker({ value, onChange, engines = ENGINE_ORDER }: { value: SearchEngineID; onChange: (id: SearchEngineID) => void; engines?: SearchEngineID[] }) {
  return (
    <div className="engine-grid">
      {engines.map((id) => {
        const engine = SEARCH_ENGINES[id];
        const selected = id === value;
        return (
          <button key={id} className={`engine-card ${selected ? 'is-selected' : ''}`} onClick={() => onChange(id)} aria-label={engine.name}>
            {id === 'custom' ? (
              <span className="engine-custom-icon">
                <Link2 size={12} />
              </span>
            ) : (
              <Favicon url={engineIcon(engine)} host={engine.name} size={22} />
            )}
            <span className="engine-text">
              <span className="engine-name truncate">{engine.name}</span>
              <span className="engine-tagline secondary truncate">{engine.tagline}</span>
            </span>
            {selected && <CircleCheck size={15} className="engine-check" />}
          </button>
        );
      })}
    </div>
  );
});

const CustomEngineField = observer(function CustomEngineField() {
  const template = settings.customSearchTemplate;
  const valid = isValidTemplate(template);
  let host = '';
  try {
    host = new URL(template.replace('%s', 'x')).hostname;
  } catch {}
  return (
    <div className="custom-engine">
      <input className="text-field mono" placeholder="https://example.com/search?q=%s" value={template} onChange={(e) => settings.set('search.customTemplate', e.target.value)} />
      <div className="small" style={{ color: valid ? 'var(--text-2)' : 'var(--orange)' }}>
        {valid ? `Searches go to ${host}.` : 'Use %s where the search terms go. Until then, DuckDuckGo is used.'}
      </div>
    </div>
  );
});

/**
 * The Brave Search API key.
 *
 * Limitation: the Mac app keeps it in the Keychain; here it's in settings.json in
 * Wake's data folder, readable by anything running as you.
 */
const BraveKeyGroup = observer(function BraveKeyGroup() {
  const [key, setKey] = useState(settings.braveAPIKey);
  const [saved, setSaved] = useState(false);
  const save = () => {
    settings.set('search.braveKey', key.trim());
    setSaved(true);
  };
  return (
    <Group title="Results inside Ctrl+K">
      <Row label="Brave Search API key" detail="Optional. Shows real results in the palette without opening a page.">
        <div className="row-inline">
          <input
            className="text-field"
            type="password"
            placeholder="Paste key"
            value={key}
            style={{ width: 200 }}
            onChange={(e) => {
              setKey(e.target.value);
              setSaved(false);
            }}
            onKeyDown={(e) => e.key === 'Enter' && save()}
          />
          <button className="button" disabled={saved} onClick={save}>
            {saved ? 'Saved' : 'Save'}
          </button>
        </div>
      </Row>
      <Row label="Get a free key">
        <button className="link-button" onClick={() => host.send('open.external', { url: 'https://api-dashboard.search.brave.com/' })}>
          api-dashboard.search.brave.com
        </button>
      </Row>
    </Group>
  );
});

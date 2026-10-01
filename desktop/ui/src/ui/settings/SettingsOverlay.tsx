// Settings, floating inside the window as a glass panel (SettingsOverlay.swift,
// SettingsPanel.swift, SettingsSidebar.swift): a sidebar of sections and a
// content card.

import { observer } from 'mobx-react-lite';
import { useState } from 'react';
import { X, Search, Settings2, Palette, Layers, Code2, Hand } from 'lucide-react';
import type { BrowserModel, SettingsSection } from '../../model/browser';
import { usePresence } from '../motion';
import { GeneralSection } from './GeneralSection';
import { AppearanceSection } from './AppearanceSection';
import { SearchSection } from './SearchSection';
import { DeckSection, PrivacySection } from './DeckPrivacySections';
import { DeveloperSection } from './DeveloperSection';
import './settings.css';

interface SectionInfo {
  id: SettingsSection;
  title: string;
  icon: typeof Search;
  tint: string;
  keywords: string[];
}

const SECTIONS: SectionInfo[] = [
  { id: 'general', title: 'General', icon: Settings2, tint: '#8e8e93', keywords: ['links', 'columns', 'restore', 'capsule', 'shortcuts', 'keyboard', 'welcome', 'onboarding', 'tour', 'updates', 'version'] },
  { id: 'search', title: 'Search', icon: Search, tint: '#ff9500', keywords: ['engine', 'default', 'duckduckgo', 'google', 'brave', 'bing', 'ecosia', 'startpage', 'kagi', 'perplexity', 'yahoo', 'custom', 'suggestions', 'api', 'key', 'results'] },
  { id: 'appearance', title: 'Appearance', icon: Palette, tint: '#5856d6', keywords: ['theme', 'dark', 'light', 'accent', 'color', 'glass', 'gap', 'corner', 'radius', 'width', 'trail', 'layout'] },
  { id: 'deck', title: 'Deck', icon: Layers, tint: '#30b0c7', keywords: ['sink', 'tabs', 'waterline', 'playing', 'unsaved', 'afloat'] },
  { id: 'developer', title: 'Developer', icon: Code2, tint: '#262629', keywords: ['editor', 'cursor', 'vs code', 'zed', 'localhost', 'ports', 'devtools', 'projects'] },
  { id: 'privacy', title: 'Privacy', icon: Hand, tint: '#007aff', keywords: ['cookies', 'data', 'clear', 'history', 'website', 'import', 'chrome', 'firefox', 'edge', 'brave'] },
];

const matches = (s: SectionInfo, query: string) => {
  const q = query.trim().toLowerCase();
  return !q || s.title.toLowerCase().includes(q) || s.keywords.some((k) => k.includes(q));
};

export const SettingsOverlay = observer(function SettingsOverlay({ browser }: { browser: BrowserModel }) {
  const { mounted, visible } = usePresence(browser.isSettingsOpen, 220);
  const [query, setQuery] = useState('');
  if (!mounted) return null;
  const current = SECTIONS.find((s) => s.id === browser.settingsSection) ?? SECTIONS[0];
  const shown = SECTIONS.filter((s) => matches(s, query));

  return (
    <div className={`settings-overlay ${visible ? 'is-visible' : ''}`} onPointerDown={() => browser.hideSettings()}>
      <div className="settings-panel glass-strong" onPointerDown={(e) => e.stopPropagation()} role="dialog" aria-label="Settings">
        <nav className="settings-sidebar">
          <button className="settings-close" title="Close Settings (Esc)" aria-label="Close Settings" onClick={() => browser.hideSettings()}>
            <X size={11} strokeWidth={3} />
          </button>
          <label className="settings-search">
            <Search size={12} strokeWidth={2.5} className="secondary" />
            <input
              placeholder="Search"
              value={query}
              onChange={(e) => {
                setQuery(e.target.value);
                // Jump to the first section that matches what's being searched for.
                const first = SECTIONS.find((s) => matches(s, e.target.value));
                if (first && !matches(current, e.target.value)) browser.settingsSection = first.id;
              }}
            />
          </label>
          {shown.map((s) => {
            const Icon = s.icon;
            const selected = s.id === current.id;
            return (
              <button key={s.id} className={`settings-nav ${selected ? 'is-selected' : ''}`} onClick={() => (browser.settingsSection = s.id)}>
                <span className="settings-nav-icon" style={{ background: selected ? 'rgba(255,255,255,0.25)' : s.tint }}>
                  <Icon size={12} strokeWidth={2.4} color="white" />
                </span>
                {s.title}
              </button>
            );
          })}
        </nav>
        <div className="settings-content" key={current.id}>
          <h2>{current.title}</h2>
          {current.id === 'general' && <GeneralSection browser={browser} />}
          {current.id === 'appearance' && <AppearanceSection />}
          {current.id === 'search' && <SearchSection />}
          {current.id === 'deck' && <DeckSection />}
          {current.id === 'developer' && <DeveloperSection browser={browser} />}
          {current.id === 'privacy' && <PrivacySection browser={browser} />}
        </div>
      </div>
    </div>
  );
});

import { createRoot } from 'react-dom/client';
import { configure } from 'mobx';
import { host, type HostInfo } from './host/host';
import { settings } from './model/settings';
import { threadStore } from './model/threads';
import { projects } from './model/developer';
import { popOuts } from './model/popout';
import { BrowserModel } from './model/browser';
import { App } from './ui/App';
import { updater } from './model/updater';
import { PopOutApp } from './ui/popout/PopOutApp';
import './styles/theme.css';

// Actions run from host events, timers and awaits; MobX's strict mode would warn on each.
configure({ enforceActions: 'never' });

async function start() {
  const info = await host.call<HostInfo>('ready');
  settings.load(info.settings);
  threadStore.window = info.window;
  threadStore.claims = info.claims ?? {};
  projects.load();
  popOuts.setWindow(info.window);
  document.documentElement.dataset.platform = info.platform;
  const root = createRoot(document.getElementById('root')!);

  const popout = new URLSearchParams(location.search).get('popout');
  if (popout) {
    root.render(<PopOutApp pick={JSON.parse(popout)} />);
    return;
  }
  const browser = await BrowserModel.create(info.window);
  (window as any).__browser = browser;
  // One window checks saved moments in the background.
  if (info.firstWindow) browser.startWatcher();
  root.render(<App browser={browser} />);
  void updater.start();
}

start().catch((error) => {
  document.body.textContent = `Wake couldn't start: ${error}`;
  console.error(error);
});

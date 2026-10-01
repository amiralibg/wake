// Short messages at the bottom of the window ("Address copied", downloads).
// The Mac app uses the system's own feedback for these; here it's an island.

import { observer } from 'mobx-react-lite';
import type { BrowserModel } from '../../model/browser';
import { usePresence } from '../motion';
import './islands.css';

export const Toast = observer(function Toast({ browser }: { browser: BrowserModel }) {
  const toast = browser.toast;
  const { mounted, visible } = usePresence(!!toast, 200);
  if (!mounted) return null;
  return (
    <div className={`toast glass-strong capsule ${visible ? 'is-visible' : ''}`} role="status">
      <span className="truncate">{toast?.text}</span>
      {toast?.action && (
        <button className="toast-action" onClick={() => toast.action!.run()}>
          {toast.action.label}
        </button>
      )}
    </div>
  );
});

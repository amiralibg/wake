// A page on the window glass (PageCard.swift): a rounded card the live webview
// sits on. The card shows the page's last snapshot whenever the webview can't be
// shown (covered by the UI, or partly under the capsule), a loading line above
// its top edge, and the error when a page fails.

import { observer } from 'mobx-react-lite';
import { TriangleAlert } from 'lucide-react';
import type { Page } from '../../model/page';
import { Favicon } from '../common/Favicon';

export const PageCard = observer(function PageCard({ page }: { page: Page; focused: boolean; onClose?: () => void }) {
  return (
    <div className="card">
      {page.snapshot ? (
        <img className="card-snapshot" src={page.snapshot} alt="" draggable={false} />
      ) : (
        <div className="card-placeholder">
          <Favicon url={page.faviconURL} host={page.host} size={28} />
          <span className="truncate">{page.displayTitle}</span>
        </div>
      )}
      {page.failure && <PageFailure page={page} />}
      <LoadingLine progress={page.progress} loading={page.isLoading} />
    </div>
  );
});

/** A hairline of accent colour along the card's top edge while the page loads. */
export const LoadingLine = ({ progress, loading }: { progress: number; loading: boolean }) => (
  <div className={`loading-line ${loading ? 'is-loading' : ''}`}>
    <div className="loading-bar" style={{ width: `max(8px, ${Math.round(progress * 100)}%)` }} />
  </div>
);

const PageFailure = observer(function PageFailure({ page }: { page: Page }) {
  return (
    <div className="page-failure">
      <TriangleAlert size={30} strokeWidth={1.3} className="secondary" />
      <div className="failure-title">This page couldn’t load</div>
      <div className="failure-message secondary">{page.failure}</div>
      <button className="button large" onClick={() => page.reload()}>
        Try Again
      </button>
    </div>
  );
});

import Foundation

/// Page-side reporters for live chips, in Wake's content world. Each posts
/// `{ type: 'live', … }` only when its value changes, and all of them share one
/// throttled MutationObserver so a busy page costs one check every few seconds.
enum LiveScripts {
    static func source(handler: String) -> String {
        """
        (() => {
          window.__wake = window.__wake || {};
          const post = (data) => {
            try { window.webkit.messageHandlers.\(handler).postMessage(Object.assign({ type: 'live' }, data)); } catch (e) {}
          };
          const throttle = (fn, ms) => {
            let last = 0, timer = null;
            return () => {
              const now = Date.now();
              if (now - last >= ms) { last = now; fn(); return; }
              if (!timer) timer = setTimeout(() => { timer = null; last = Date.now(); fn(); }, ms - (now - last));
            };
          };

          // Media: time and progress of what's playing.
          let lastMedia = '';
          const reportMedia = () => {
            const all = [...document.querySelectorAll('video, audio')].filter(m => m.readyState > 0 && (m.currentTime > 0 || !m.paused));
            const m = all.find(m => !m.paused) || all[0];
            const media = m ? { t: m.currentTime, d: isFinite(m.duration) ? m.duration : 0, playing: !m.paused && !m.ended } : null;
            const key = media ? `${Math.floor(media.t)}|${media.playing}|${Math.floor(media.d)}` : 'none';
            if (key === lastMedia) return;
            lastMedia = key;
            post({ media });
          };
          const mediaTick = throttle(reportMedia, 1000);
          ['timeupdate', 'play', 'pause', 'ended', 'emptied', 'durationchange'].forEach(name => document.addEventListener(name, mediaTick, true));

          // Price: structured data first (JSON-LD, meta tags, microdata), never guessed from text.
          const findPrice = () => {
            const walk = (node) => {
              if (!node || typeof node !== 'object') return null;
              if (Array.isArray(node)) { for (const n of node) { const r = walk(n); if (r) return r; } return null; }
              if (node['@graph']) return walk(node['@graph']);
              const type = [].concat(node['@type'] || []).join(' ');
              if (/Product/.test(type) && node.offers) {
                for (const offer of [].concat(node.offers)) {
                  const amount = parseFloat(offer.price ?? offer.lowPrice ?? (offer.priceSpecification || {}).price);
                  if (amount > 0) return { amount, currency: offer.priceCurrency || '' };
                }
              }
              return null;
            };
            for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
              try { const r = walk(JSON.parse(script.textContent)); if (r) return r; } catch (e) {}
            }
            const meta = (n) => {
              const el = document.querySelector(`meta[property="${n}"], meta[name="${n}"], meta[itemprop="${n}"]`);
              return el && el.getAttribute('content');
            };
            const amount = parseFloat(meta('product:price:amount') || meta('og:price:amount'));
            if (amount > 0) return { amount, currency: meta('product:price:currency') || meta('og:price:currency') || '' };
            const item = document.querySelector('[itemprop="price"]');
            if (item) {
              const value = parseFloat((item.getAttribute('content') || item.textContent || '').replace(/[^0-9.]/g, ''));
              const currency = document.querySelector('[itemprop="priceCurrency"]');
              if (value > 0) return { amount: value, currency: currency ? (currency.getAttribute('content') || currency.textContent || '').trim() : '' };
            }
            return null;
          };
          let lastPrice = '';
          const reportPrice = () => {
            const price = findPrice();
            const key = price ? price.amount + price.currency : '';
            if (!price || key === lastPrice) return;
            lastPrice = key;
            post({ price });
          };

          // CI on GitHub pull requests, from the merge box's own words.
          let lastCI = '';
          const reportCI = () => {
            if (location.hostname !== 'github.com' || !/\\/pull\\/\\d+/.test(location.pathname)) return;
            const box = document.querySelector('[data-testid="mergebox-partial"], .merge-pr, #partial-pull-merging, .mergeability-details') || document.querySelector('main');
            const text = box ? box.innerText : '';
            let state = '';
            if (/checks? (have |has )?failed|were not successful|failing check/i.test(text)) state = 'failed';
            else if (/haven.t completed yet|checks? (are |is )?(in progress|pending|queued)|expected.{0,20}waiting/i.test(text)) state = 'pending';
            else if (/all checks have passed|checks? (have |has )?passed/i.test(text)) state = 'passed';
            if (state && state !== lastCI) { lastCI = state; post({ ci: state }); }
          };

          // "Updated": the text changed noticeably while this column wasn't focused.
          let baseline = null;
          const size = () => (document.body ? document.body.innerText.length : 0);
          const checkChanged = () => {
            if (baseline === null) return;
            if (document.hasFocus()) { baseline = size(); return; }
            const now = size();
            if (Math.abs(now - baseline) > 200) { baseline = now; post({ changed: true }); }
          };
          window.addEventListener('focus', () => { baseline = size(); post({ changed: false }); });

          // Single-page apps change pages without a navigation WebKit reports.
          let href = location.href;
          const check = throttle(() => {
            if (location.href !== href) {
              href = location.href; lastPrice = ''; lastCI = '';
              post({ reset: true });
            }
            reportPrice(); reportCI(); checkChanged();
          }, 4000);
          const start = () => {
            setTimeout(() => { reportPrice(); reportCI(); }, 1500);
            setTimeout(() => { baseline = size(); }, 3000);
            new MutationObserver(check).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
          };
          document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', start) : start();
        })();
        """
    }
}

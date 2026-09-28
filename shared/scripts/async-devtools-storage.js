// Storage the page can list only asynchronously.
const out = { databases: [], caches: [], workers: [] };
try { if (indexedDB.databases) out.databases = (await indexedDB.databases()).map(d => ({ name: d.name, version: d.version })); } catch {}
try { if (window.caches) for (const name of await caches.keys()) { const c = await caches.open(name); out.caches.push({ name, count: (await c.keys()).length }); } } catch {}
try { if (navigator.serviceWorker) out.workers = (await navigator.serviceWorker.getRegistrations()).map(r => ({ scope: r.scope, script: (r.active || r.waiting || r.installing || {}).scriptURL || '', state: (r.active || r.waiting || r.installing || {}).state || '' })); } catch {}
return out;

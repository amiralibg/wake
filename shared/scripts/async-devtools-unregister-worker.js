// Unregisters the service worker whose scope is `name`.
// params: { name }
for (const r of await navigator.serviceWorker.getRegistrations()) if (r.scope === params.name) await r.unregister();
return true;

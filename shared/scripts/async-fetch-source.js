// Fetches a script or stylesheet with the page's cookies. Runs in Wake's isolated
// world, whose `fetch` isn't the one developer mode wraps, so DevTools' own
// requests don't show up in Network.
// params: { url }
const response = await fetch(params.url, { credentials: 'include', cache: 'force-cache' });
return await response.text();

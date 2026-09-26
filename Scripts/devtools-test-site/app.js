localStorage.setItem('theme', 'dark'); localStorage.setItem('count', '3');
sessionStorage.setItem('session-key', 'abc123');
document.cookie = 'wake_test=hello; path=/';
document.cookie = 'flavor=vanilla; path=/';
const req = indexedDB.open('wake-db', 1);
req.onupgradeneeded = () => req.result.createObjectStore('items', { keyPath: 'id' });
req.onsuccess = () => { const tx = req.result.transaction('items', 'readwrite'); tx.objectStore('items').put({ id: 1, name: 'Boat' }); tx.oncomplete = () => req.result.close(); };
caches.open('wake-cache-v1').then(c => c.put('/data.json', new Response('{"cached":true}')));
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(e => console.warn('sw', e));
function doFetch() { return fetch('/data.json').then(r => r.json()).then(j => { console.log('fetched', j); return j; }); }
function greet(name) { const message = 'Hello, ' + name; console.info(message); return message; }
const xhr = new XMLHttpRequest(); xhr.open('GET', '/data.json'); xhr.send();
console.log('app loaded', { items: [1, 2, 3], nested: { a: 1 } });
console.warn('a warning'); console.error('an error');
setTimeout(() => fetch('/data.json?late=1'), 8000);

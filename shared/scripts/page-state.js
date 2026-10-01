// Reports whether media is playing and whether a form has unsaved input, so the
// Deck never sinks a tab you'd lose something in.
// params: { channel }
let unsaved = false;
const playing = () => [...document.querySelectorAll('video, audio')]
  .some(m => !m.paused && !m.ended && m.readyState > 2);
const report = () => wake.post(params.channel, { type: 'state', playing: playing(), unsaved });
['play', 'playing', 'pause', 'ended'].forEach(name => document.addEventListener(name, report, true));
document.addEventListener('input', (event) => {
  const t = event.target;
  const editable = t && (t.form || t.isContentEditable || t.tagName === 'TEXTAREA');
  if (editable && !unsaved) { unsaved = true; report(); }
}, true);
document.addEventListener('submit', () => { unsaved = false; report(); }, true);

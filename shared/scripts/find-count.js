// Counts how often params.query appears in the page's visible text, for the
// find island's "3 of 12". WebKit's find API reports only whether there's a match.
// Returns the count, capped at params.limit so huge pages stay cheap.
const query = String(params.query || '');
if (!query || !document.body) return 0;
const caseSensitive = !!params.caseSensitive;
const text = caseSensitive ? document.body.innerText : document.body.innerText.toLowerCase();
const needle = caseSensitive ? query : query.toLowerCase();
const limit = params.limit || 1000;
let count = 0;
let index = text.indexOf(needle);
while (index !== -1 && count < limit) {
  count += 1;
  index = text.indexOf(needle, index + needle.length);
}
return count;

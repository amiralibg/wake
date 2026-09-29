// Search engines, typed-address recognition and results-page recognition
// (ports of SearchEngine.swift, URLInput.swift and SearchQuery.swift).

export type SearchEngineID =
  | 'duckDuckGo' | 'google' | 'brave' | 'bing' | 'ecosia' | 'startpage' | 'kagi' | 'perplexity' | 'yahoo' | 'custom';

export interface SearchEngine {
  id: SearchEngineID;
  name: string;
  tagline: string;
  /** The results page, with `%s` for the query. */
  template: string;
  /** An OpenSearch suggestions endpoint (`["query", ["suggestion", …]]`). */
  suggestions: string;
  icon?: string;
}

const ddgSuggest = 'https://duckduckgo.com/ac/?type=list&q=%s';

export const SEARCH_ENGINES: Record<SearchEngineID, SearchEngine> = {
  duckDuckGo: { id: 'duckDuckGo', name: 'DuckDuckGo', tagline: 'Private, no tracking', template: 'https://duckduckgo.com/?q=%s', suggestions: ddgSuggest },
  google: { id: 'google', name: 'Google', tagline: 'The biggest index', template: 'https://www.google.com/search?q=%s', suggestions: 'https://suggestqueries.google.com/complete/search?client=firefox&ie=utf-8&oe=utf-8&q=%s' },
  brave: { id: 'brave', name: 'Brave Search', tagline: 'Independent index', template: 'https://search.brave.com/search?q=%s', suggestions: 'https://search.brave.com/api/suggest?q=%s', icon: 'https://brave.com/favicon.ico' },
  bing: { id: 'bing', name: 'Bing', tagline: 'Microsoft', template: 'https://www.bing.com/search?q=%s', suggestions: 'https://api.bing.com/osjson.aspx?query=%s' },
  ecosia: { id: 'ecosia', name: 'Ecosia', tagline: 'Plants trees', template: 'https://www.ecosia.org/search?q=%s', suggestions: 'https://ac.ecosia.org/autocomplete?type=list&q=%s' },
  startpage: { id: 'startpage', name: 'Startpage', tagline: 'Google results, privately', template: 'https://www.startpage.com/do/search?q=%s', suggestions: ddgSuggest },
  kagi: { id: 'kagi', name: 'Kagi', tagline: 'Paid, ad-free', template: 'https://kagi.com/search?q=%s', suggestions: ddgSuggest },
  perplexity: { id: 'perplexity', name: 'Perplexity', tagline: 'Answers with sources', template: 'https://www.perplexity.ai/search?q=%s', suggestions: ddgSuggest },
  yahoo: { id: 'yahoo', name: 'Yahoo', tagline: 'Powered by Bing', template: 'https://search.yahoo.com/search?p=%s', suggestions: 'https://api.bing.com/osjson.aspx?query=%s' },
  custom: { id: 'custom', name: 'Custom', tagline: 'Your own URL', template: '', suggestions: ddgSuggest },
};

export const ENGINE_ORDER: SearchEngineID[] = ['duckDuckGo', 'google', 'brave', 'bing', 'ecosia', 'startpage', 'kagi', 'perplexity', 'yahoo', 'custom'];

export function engineIcon(engine: SearchEngine): string | undefined {
  if (engine.icon) return engine.icon;
  if (!engine.template) return undefined;
  try {
    return `https://${new URL(engine.template.replace('%s', 'x')).hostname}/favicon.ico`;
  } catch {
    return undefined;
  }
}

export function searchURL(template: string, query: string): string | null {
  if (!template.includes('%s')) return null;
  return template.replace('%s', encodeURIComponent(query));
}

/** A custom template is usable when it's an http(s) URL with a `%s` placeholder. */
export function isValidTemplate(template: string): boolean {
  const url = searchURL(template.trim(), 'wake');
  if (!url) return false;
  try {
    const parsed = new URL(url);
    return (parsed.protocol === 'http:' || parsed.protocol === 'https:') && !!parsed.hostname;
  } catch {
    return false;
  }
}

// MARK: Typed input

function isLocalHost(host: string): boolean {
  if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) return true;
  const octets = host.split('.');
  return octets.length === 4 && octets.every((o) => /^\d{1,3}$/.test(o) && Number(o) <= 255);
}

/** Whether typed text is an address (and which), or a search. */
export function urlFromInput(text: string): string | null {
  const input = text.trim();
  if (!input || /\s/.test(input)) return null;
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(input)?.[1]?.toLowerCase();
  if (scheme && ['http', 'https', 'file', 'about'].includes(scheme)) {
    try {
      return new URL(input).href;
    } catch {
      return null;
    }
  }
  const hostPart = input.split('/')[0];
  const host = hostPart.split(':')[0];
  if (isLocalHost(host)) return safeURL('http://' + input);
  const labels = host.split('.');
  const tld = labels[labels.length - 1];
  if (labels.length < 2 || !tld || tld.length < 2 || !/^\p{L}+$/u.test(tld)) return null;
  return safeURL('https://' + input);
}

function safeURL(text: string): string | null {
  try {
    return new URL(text).href;
  } catch {
    return null;
  }
}

// MARK: Results pages

export interface SearchMatch {
  engine: string;
  query: string;
}

interface Pattern {
  engine: string;
  host: string;
  path: string;
  parameter: string;
}

function pattern(engine: string, template: string): Pattern | null {
  try {
    const url = new URL(template.replace('%s', '__wake__'));
    let parameter: string | null = null;
    url.searchParams.forEach((value, key) => {
      if (value === '__wake__') parameter = key;
    });
    if (!parameter) return null;
    return { engine, host: url.hostname.toLowerCase(), path: url.pathname || '/', parameter };
  } catch {
    return null;
  }
}

const BUILT_IN: Pattern[] = [
  ...ENGINE_ORDER.map((id) => pattern(SEARCH_ENGINES[id].name, SEARCH_ENGINES[id].template)).filter((p): p is Pattern => !!p),
  { engine: 'DuckDuckGo', host: 'html.duckduckgo.com', path: '/html', parameter: 'q' },
  { engine: 'YouTube', host: 'youtube.com', path: '/results', parameter: 'search_query' },
  { engine: 'GitHub', host: 'github.com', path: '/search', parameter: 'q' },
  { engine: 'Wikipedia', host: 'wikipedia.org', path: '/w/index.php', parameter: 'search' },
  { engine: 'Amazon', host: 'amazon.com', path: '/s', parameter: 'k' },
  { engine: 'Baidu', host: 'baidu.com', path: '/s', parameter: 'wd' },
  { engine: 'Yandex', host: 'yandex.com', path: '/search', parameter: 'text' },
];

/** "www.google.com" also matches google.de, google.co.uk…; other hosts match themselves and subdomains. */
function hostMatches(host: string, patternHost: string): boolean {
  const bare = patternHost.startsWith('www.') ? patternHost.slice(4) : patternHost;
  if (bare === 'google.com') {
    const parts = host.split('.');
    return parts.includes('google') && (parts[0] === 'google' || parts[0] === 'www');
  }
  return host === bare || host.endsWith('.' + bare);
}

/** Recognises a search engine's results page and what was searched for. */
export function matchSearch(url: string, customTemplate?: string | null): SearchMatch | null {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (!parsed.search) return null;
  const host = parsed.hostname.toLowerCase();
  const path = parsed.pathname || '/';
  const patterns = [...BUILT_IN];
  const custom = customTemplate ? pattern('Custom', customTemplate) : null;
  if (custom) patterns.unshift(custom);
  for (const p of patterns) {
    if (!hostMatches(host, p.host) || path !== p.path) continue;
    // URLSearchParams decodes "+" as a space, as results pages mean it.
    const value = parsed.searchParams.get(p.parameter)?.trim();
    if (value) return { engine: p.engine, query: value };
  }
  return null;
}

// MARK: Suggestions

export function parseSuggestions(text: string, query: string): string[] {
  try {
    const json = JSON.parse(text);
    const list = Array.isArray(json) ? json[1] : null;
    if (!Array.isArray(list)) return [];
    return list.filter((s): s is string => typeof s === 'string' && s.toLowerCase() !== query.toLowerCase());
  } catch {
    return [];
  }
}

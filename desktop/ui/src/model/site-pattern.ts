// Matching an address against a site-width rule (port of SitePattern in
// SiteWidthRules.swift). Scheme and a leading `www.` don't count, `*` matches any
// run of characters, and a pattern with no path covers the whole site.

/** `https://www.GitHub.com` and `github.com` are the same rule: `github.com/*`. */
export function normalizePattern(pattern: string): string {
  let text = pattern.trim();
  const scheme = text.indexOf('://');
  if (scheme >= 0) text = text.slice(scheme + 3);
  const slash = text.indexOf('/');
  let host = (slash >= 0 ? text.slice(0, slash) : text).toLowerCase();
  if (host.startsWith('www.')) host = host.slice(4);
  const path = slash >= 0 ? text.slice(slash) : '';
  return host + (!path || path === '/' ? '/*' : path);
}

/** How specific a pattern is: the longest match wins when several apply. */
export function patternSpecificity(pattern: string): number {
  return normalizePattern(pattern).replace(/\*/g, '').length;
}

function subject(url: string): string | null {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return null;
    let host = parsed.host.toLowerCase();
    if (host.startsWith('www.')) host = host.slice(4);
    return host + (parsed.pathname || '/');
  } catch {
    return null;
  }
}

function glob(pattern: string, text: string): boolean {
  const parts = pattern.split('*');
  if (parts.length === 1) return pattern === text;
  if (!text.startsWith(parts[0])) return false;
  let rest = text.slice(parts[0].length);
  for (const part of parts.slice(1, -1)) {
    if (!part) continue;
    const at = rest.indexOf(part);
    if (at < 0) return false;
    rest = rest.slice(at + part.length);
  }
  return rest.endsWith(parts[parts.length - 1]);
}

export function patternMatches(pattern: string, url: string): boolean {
  const text = subject(url);
  return text != null && glob(normalizePattern(pattern), text);
}

/** Only web addresses have a site to remember. */
export function canHaveRule(url: string | null | undefined): boolean {
  return !!url && subject(url) != null;
}

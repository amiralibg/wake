import { describe, expect, it } from 'vitest';
import { canHaveRule, patternMatches, patternSpecificity } from './site-pattern';

describe('patternMatches', () => {
  it.each([
    ['github.com/*', 'https://github.com/a/b', true],
    ['github.com/*', 'https://www.github.com', true],
    ['github.com', 'https://github.com/x', true],
    ['https://www.GitHub.com/', 'https://github.com/x', true],
    ['github.com/*/issues', 'https://github.com/a/b/issues', true],
    ['github.com/*/issues', 'https://github.com/a/b/pulls', false],
    ['github.com/*', 'https://gitlab.com/', false],
    ['*.google.com/*', 'https://mail.google.com/x', true],
    ['*.google.com/*', 'https://google.com/x', false],
    ['github.com/a', 'https://github.com/ab', false],
    ['localhost:3000', 'http://localhost:3000/z', true],
    ['github.com/*', 'file:///github.com/x', false],
  ])('%s against %s', (pattern, url, expected) => {
    expect(patternMatches(pattern, url)).toBe(expected);
  });

  it('prefers the more specific pattern', () => {
    expect(patternSpecificity('github.com/a/*')).toBeGreaterThan(patternSpecificity('github.com/*'));
  });

  it('only offers rules for web addresses', () => {
    expect(canHaveRule('https://a.com')).toBe(true);
    expect(canHaveRule('file:///a.html')).toBe(false);
    expect(canHaveRule(null)).toBe(false);
  });
});

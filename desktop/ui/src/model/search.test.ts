import { describe, expect, it } from 'vitest';
import { fileURLFromPath, urlFromInput } from './search';

describe('urlFromInput', () => {
  it.each([
    ['/home/me/a b.html', 'file:///home/me/a%20b.html'],
    ["'/home/me/a b.html'", 'file:///home/me/a%20b.html'],
    ['/home/me/a\\ b.html', 'file:///home/me/a%20b.html'],
    ['C:\\Users\\me\\a b.html', 'file:///C:/Users/me/a%20b.html'],
    ['c:/Users/me/a.html', 'file:///c:/Users/me/a.html'],
    ['file:///tmp/a b.html', 'file:///tmp/a%20b.html'],
    ['github.com', 'https://github.com/'],
    ['localhost:3000/x', 'http://localhost:3000/x'],
  ])('%s is an address', (input, expected) => {
    expect(urlFromInput(input)).toBe(expected);
  });

  it.each(['/r/swift', 'hello world', 'hello'])('%s is a search', (input) => {
    expect(urlFromInput(input)).toBeNull();
  });
});

describe('fileURLFromPath', () => {
  it('escapes what a URL path can\'t hold', () => {
    expect(fileURLFromPath('/home/me/a#1?.html')).toBe('file:///home/me/a%231%3F.html');
    expect(fileURLFromPath('C:\\a\\b.html')).toBe('file:///C:/a/b.html');
  });
});

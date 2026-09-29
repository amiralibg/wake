// A site's icon, or a coloured monogram until (or unless) it loads
// (Favicon.swift). The shell loads icons straight from the site; the engine's
// own cache keeps them.

import { useEffect, useState } from 'react';

const failed = new Set<string>();

export function monogramColor(host: string) {
  let hash = 0;
  for (const ch of host) hash = (hash * 31 + ch.codePointAt(0)!) & 0xffff;
  return `hsl(${hash % 360} 45% 58%)`;
}

export function Favicon({ url, host, size = 14 }: { url?: string | null; host: string; size?: number }) {
  const source = url ?? (host ? `https://${host}/favicon.ico` : null);
  const [broken, setBroken] = useState(!source || failed.has(source));
  useEffect(() => setBroken(!source || failed.has(source)), [source]);
  const radius = size / 4;
  if (broken || !source) {
    const letter = (host.replace(/^www\./, '')[0] ?? '•').toUpperCase();
    return (
      <span
        className="favicon monogram"
        style={{ width: size, height: size, borderRadius: radius, background: monogramColor(host), fontSize: size * 0.58 }}
        aria-hidden
      >
        {letter}
      </span>
    );
  }
  return (
    <img
      className="favicon"
      src={source}
      width={size}
      height={size}
      style={{ borderRadius: radius }}
      alt=""
      draggable={false}
      onError={() => {
        failed.add(source);
        setBroken(true);
      }}
    />
  );
}

import { startWater } from './water.js';

const still = matchMedia('(prefers-reduced-motion: reduce)').matches;
const clamp = (v, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v));
const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/* ---------- Split headlines into words ---------- */

document.querySelectorAll('[data-split]').forEach((heading) => {
  let i = 0;
  const walk = (node) => {
    for (const child of [...node.childNodes]) {
      if (child.nodeType === Node.TEXT_NODE) {
        const fragment = document.createDocumentFragment();
        for (const part of child.textContent.split(/(\s+)/)) {
          if (!part) continue;
          if (/^\s+$/.test(part)) {
            fragment.append(' ');
            continue;
          }
          const outer = document.createElement('span');
          outer.className = 'w';
          const inner = document.createElement('span');
          inner.textContent = part;
          inner.style.setProperty('--i', i++);
          outer.append(inner);
          fragment.append(outer);
        }
        child.replaceWith(fragment);
      } else if (child.nodeType === Node.ELEMENT_NODE && child.tagName !== 'BR') {
        walk(child);
      }
    }
  };
  walk(heading);
});

/* ---------- Reveal on scroll ---------- */

const reveal = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('in');
        reveal.unobserve(entry.target);
      }
    }
  },
  { rootMargin: '0px 0px -8% 0px', threshold: 0.12 }
);
document.querySelectorAll('[data-reveal], [data-split], .mark, .principle').forEach((el) => reveal.observe(el));

// Card illustrations animate only while on screen.
const play = new IntersectionObserver((entries) => {
  for (const entry of entries) entry.target.classList.toggle('play', entry.isIntersecting);
});
document.querySelectorAll('.card').forEach((el) => play.observe(el));

/* ---------- Water ---------- */

document.querySelectorAll('[data-water]').forEach((host) => {
  const canvas = host.querySelector('canvas');
  const drift = host.dataset.water === 'scroll';
  startWater(canvas, {
    bowY: Number(host.dataset.bowY || 0.8),
    // On the hero the boat sails on as you scroll away from it.
    progress: () => {
      if (!drift) return 0.42;
      const rect = host.getBoundingClientRect();
      return 0.3 + clamp(-rect.top / rect.height) * 0.6;
    },
  });
});

/* ---------- Nav: glass over water, paper elsewhere ---------- */

const nav = document.querySelector('.nav');
const waters = [...document.querySelectorAll('.water')];
const updateNav = () => {
  if (!nav) return;
  const y = 36;
  const overWater = waters.some((w) => {
    const r = w.getBoundingClientRect();
    return r.top <= y && r.bottom >= y;
  });
  nav.dataset.state = overWater ? 'water' : 'paper';
};

/* ---------- Trail demo (index) ---------- */

const trail = document.querySelector('.trail');
let updateTrail = () => {};
if (trail) {
  const viewport = trail.querySelector('.cols');
  const cols = [...trail.querySelectorAll('.col')];
  const steps = [...trail.querySelectorAll('.steps li')];
  const url = trail.querySelector('[data-url]');
  const GAP = 8;
  // n: columns open; w: widths as a share of the window; align: which end the view shows.
  const states = [
    { n: 1, w: [1, 0.5, 0.5, 0.5], focus: 0, align: 'end' },
    { n: 2, w: [0.5, 0.5, 0.5, 0.5], focus: 1, align: 'end' },
    { n: 3, w: [0.5, 0.5, 0.5, 0.5], focus: 2, align: 'end' },
    { n: 4, w: [0.5, 0.5, 0.5, 0.5], focus: 3, align: 'end' },
    { n: 4, w: [0.5, 0.5, 0.5, 0.72], focus: 3, align: 'end', resizing: 3 },
    { n: 4, w: [0.5, 0.5, 0.5, 0.72], focus: 0, align: 'start' },
  ];
  let current = -1;

  const layout = (index) => {
    const s = states[index];
    const V = viewport.clientWidth;
    const widths = s.w.map((w) => w * (V + GAP) - GAP);
    const xs = [];
    let x = 0;
    widths.forEach((w) => {
      xs.push(x);
      x += w + GAP;
    });
    const last = s.n - 1;
    const offset = s.align === 'end' ? Math.max(0, xs[last] + widths[last] - V) : 0;
    cols.forEach((col, i) => {
      const open = i < s.n;
      const shift = open ? 0 : 60;
      col.style.width = `${widths[i]}px`;
      col.style.transform = `translateX(${xs[i] - offset + shift}px)`;
      col.classList.toggle('is-hidden', !open);
      col.classList.toggle('is-focus', i === s.focus && s.n > 1);
      col.classList.toggle('is-resizing', i === s.resizing);
      col.setAttribute('aria-hidden', String(!open));
      col.querySelector('.lnk')?.classList.toggle('hit', i < s.n - 1);
    });
    steps.forEach((li, i) => li.classList.toggle('on', i === index));
    if (url) url.textContent = cols[s.focus].dataset.host;
  };

  updateTrail = (force) => {
    const rect = trail.getBoundingClientRect();
    const travel = rect.height - innerHeight;
    const progress = clamp(-rect.top / travel);
    const index = Math.min(states.length - 1, Math.floor(progress * states.length));
    if (index !== current || force) {
      current = index;
      layout(index);
    }
  };
  new ResizeObserver(() => updateTrail(true)).observe(viewport);
}

/* ---------- Tabs become a trail (about) ---------- */

const morph = document.querySelector('.morph');
let updateMorph = () => {};
if (morph) {
  const canvas = morph.querySelector('.morph-canvas');
  const items = [...morph.querySelectorAll('.morph-item')];
  const bodies = items.map((item) => item.querySelector('.body'));
  const tabsLabel = morph.querySelector('.tabs-label');
  const trailLabel = morph.querySelector('.trail-label');
  // The finished trail echoes the icon: older columns slimmer and fainter.
  const shares = [0.07, 0.11, 0.17, 0.25];
  const fades = [0.4, 0.55, 0.72, 0.88, 1];

  updateMorph = () => {
    const rect = morph.getBoundingClientRect();
    const travel = rect.height - innerHeight;
    const p = ease(clamp((-rect.top / travel - 0.12) / 0.62));
    const W = canvas.clientWidth;
    const H = canvas.clientHeight;
    const pad = 12;
    const gap = 8;
    const tabW = Math.min(190, (W - pad * 2 - gap * 4) / 5);
    const inner = W - pad * 2 - gap * 4;
    let x = pad;
    items.forEach((item, i) => {
      const colW = i < 4 ? inner * shares[i] : inner * (1 - shares.reduce((a, b) => a + b, 0));
      const from = { x: pad + i * (tabW + gap), y: pad, w: tabW, h: 36 };
      const to = { x, y: pad, w: colW, h: H - pad * 2 };
      x += colW + gap;
      const active = i === 4;
      const lx = from.x + (to.x - from.x) * p;
      const ly = from.y + (to.y - from.y) * p;
      const lw = from.w + (to.w - from.w) * p;
      const lh = from.h + (to.h - from.h) * p;
      item.style.transform = `translate(${lx}px, ${ly}px)`;
      item.style.width = `${lw}px`;
      item.style.height = `${lh}px`;
      item.style.opacity = String(active ? 1 : 1 + (fades[i] - 1) * p);
      bodies[i].style.opacity = String(active ? 1 : p);
    });
    // Under the tab strip, the one visible page.
    const sheet = morph.querySelector('.morph-sheet');
    if (sheet) {
      sheet.style.opacity = String(clamp(1 - p * 2.5));
      sheet.style.transform = `translateY(${p * 24}px)`;
    }
    if (tabsLabel) tabsLabel.style.opacity = String(1 - p * 0.7);
    if (trailLabel) trailLabel.style.opacity = String(0.3 + p * 0.7);
  };
  new ResizeObserver(() => updateMorph()).observe(canvas);
}

/* ---------- Scroll-linked marquee (about) ---------- */

const marquee = document.querySelector('.marquee');
let updateMarquee = () => {};
if (marquee && !still) {
  const track = marquee.querySelector('.marquee-track');
  updateMarquee = () => {
    const rect = marquee.getBoundingClientRect();
    const progress = clamp((innerHeight - rect.top) / (innerHeight + rect.height));
    const distance = Math.max(0, track.scrollWidth - marquee.clientWidth);
    track.style.transform = `translateX(${-progress * distance}px)`;
  };
}

/* ---------- One scroll loop ---------- */

let ticking = false;
const onScroll = () => {
  if (ticking) return;
  ticking = true;
  requestAnimationFrame(() => {
    ticking = false;
    updateNav();
    updateTrail();
    updateMorph();
    updateMarquee();
  });
};
addEventListener('scroll', onScroll, { passive: true });
addEventListener('resize', onScroll);
onScroll();

/* ---------- Copy buttons ---------- */

document.querySelectorAll('[data-copy]').forEach((button) => {
  const status = document.getElementById(button.getAttribute('aria-describedby') || '');
  let timer;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      button.classList.add('copied');
      if (status) status.textContent = 'Command copied';
      clearTimeout(timer);
      timer = setTimeout(() => {
        button.classList.remove('copied');
        if (status) status.textContent = '';
      }, 1800);
    } catch {
      if (status) status.textContent = 'Copy failed. Select the command and copy it by hand.';
    }
  });
});

/* ---------- Download buttons also show the install steps ---------- */

// The disk image alone lands people on macOS's "can't be opened" warning. The
// download still starts (the link is followed as usual), and the page moves to
// the steps that get past it, and to the Homebrew line that avoids it.
const installSteps = document.querySelector('.howto');
if (installSteps) {
  document.querySelectorAll('[data-dmg], [data-asset]').forEach((button) => {
    button.addEventListener('click', () => {
      const nav = document.querySelector('.nav')?.getBoundingClientRect().height ?? 0;
      const top = installSteps.getBoundingClientRect().top + scrollY - nav - 16;
      // Smooth unless reduced motion is on: html's scroll-behavior decides.
      scrollTo({ top });
    });
  });
}

/* ---------- Latest release from GitHub ---------- */

// The Windows installer and the Linux AppImage, by their names in a release.
const desktopAssets = {
  windows: (name) => name.endsWith('-windows-x64-setup.exe'),
  linux: (name) => name.endsWith('-linux-x86_64.AppImage'),
};
// Which download the hero button offers: this visitor's platform, if the latest
// release has a package for it (else the Mac's, as the HTML says).
const visitorPlatform = (() => {
  const platform = (navigator.userAgentData?.platform || navigator.platform || '').toLowerCase();
  if (platform.includes('win')) return 'windows';
  if (platform.includes('linux') && !/android/i.test(navigator.userAgent)) return 'linux';
  return null;
})();

const releaseTargets = document.querySelectorAll('[data-dmg], [data-asset], [data-version], [data-date], [data-size]');
if (releaseTargets.length) {
  fetch('https://api.github.com/repos/amiralibg/wake/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    .then((response) => (response.ok ? response.json() : Promise.reject(response.status)))
    .then((release) => {
      const dmg = release.assets?.find((asset) => asset.name.endsWith('.dmg'));
      const version = release.tag_name.replace(/^v/, '');
      const date = new Date(release.published_at).toLocaleDateString('en', { year: 'numeric', month: 'long', day: 'numeric' });
      const size = dmg ? `${(dmg.size / 1024 / 1024).toFixed(1)} MB` : null;
      document.querySelectorAll('[data-dmg]').forEach((a) => dmg && (a.href = dmg.browser_download_url));
      // Without a package in the latest release, the link stays on the release page.
      for (const [platform, matches] of Object.entries(desktopAssets)) {
        const asset = release.assets?.find((a) => matches(a.name));
        if (!asset) continue;
        document.querySelectorAll(`[data-asset="${platform}"]`).forEach((a) => (a.href = asset.browser_download_url));
        if (platform === visitorPlatform) {
          const hero = document.querySelector('.hero [data-dmg]');
          const label = hero?.querySelector('[data-hero-label]');
          if (hero && label) {
            hero.removeAttribute('data-dmg');
            hero.href = asset.browser_download_url;
            label.textContent = platform === 'windows' ? 'Download for Windows' : 'Download for Linux';
          }
        }
      }
      document.querySelectorAll('[data-version]').forEach((el) => (el.textContent = version));
      document.querySelectorAll('[data-date]').forEach((el) => (el.textContent = date));
      document.querySelectorAll('[data-size]').forEach((el) => size && (el.textContent = size));
    })
    .catch(() => {
      // The pinned links and text in the HTML stay as they are.
    });
}

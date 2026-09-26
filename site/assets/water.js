// Wake's onboarding water, ported from WakeWaterShader.swift (Metal) to WebGL.
// A height field (swell, a Kelvin wake behind a moving bow, a ring from a click,
// a disturbance under the pointer) shaded by its own slopes. The paper boat is an
// SVG that rides the bow.

const FRAGMENT = `
precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uDropAge;
uniform vec2 uBow;
uniform vec2 uDrop;
uniform vec2 uPointer;
uniform float uPointerStrength;
uniform float uScale;
uniform vec3 uAccent;

float hash21(vec2 p) {
  p = fract(p * vec2(234.34, 435.345));
  p += dot(p, p + 34.23);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  mat2 rotate = mat2(1.6, 1.2, -1.2, 1.6);
  for (int i = 0; i < 4; i++) {
    value += amplitude * noise(p);
    p = rotate * p;
    amplitude *= 0.5;
  }
  return value;
}

float swell(vec2 p, float t) {
  float h = sin(dot(p, vec2(0.8, 1.3)) * 7.0 + t * 0.9) * 0.35;
  h += sin(dot(p, vec2(-1.1, 0.6)) * 11.0 + t * 1.3) * 0.2;
  h += (fbm(p * 5.0 + vec2(t * 0.12, -t * 0.08)) - 0.5) * 0.9;
  return h * 0.08;
}

float kelvinWake(vec2 p, vec2 bow, float t, out float foam) {
  const float rate = 7.0;
  const float boatSpeed = 0.16;
  const float ringSpeed = 0.06;
  const float reach = 0.12;
  const float oldest = 26.0 / 7.0;
  vec2 q = p - bow;
  foam = 0.0;
  if (q.x > reach || q.x < -(0.012 + (boatSpeed + ringSpeed) * oldest + reach) || abs(q.y) > ringSpeed * oldest + reach) {
    return 0.0;
  }
  float phase = fract(t * rate);
  float jitter = (noise(p * 22.0 + vec2(t * 0.4, 0.0)) - 0.5) * 0.009;
  float h = 0.0;
  for (int k = 0; k < 26; k++) {
    float age = (float(k) + phase) / rate;
    vec2 emitter = bow - vec2(0.012 + boatSpeed * age, 0.0);
    float r = length(p - emitter);
    float d = r - ringSpeed * age + jitter;
    if (abs(d) > reach) continue;
    float band = exp(-d * d * 520.0);
    float crest = cos(d * 170.0 - age * 6.0);
    float life = exp(-age * 0.9) * smoothstep(0.0, 0.07, age);
    h += crest * band * life;
  }
  float behind = max(0.0, -q.x);
  foam = exp(-q.y * q.y * 1500.0) * exp(-behind * 7.0) * smoothstep(0.005, 0.02, behind);
  return h * 0.016;
}

float dropRipple(vec2 p, vec2 center, float age) {
  if (age > 4.0) return 0.0;
  float r = length(p - center);
  float past = age * 0.42 - r;
  float ahead = exp(-max(0.0, -past) * 80.0);
  float trailing = exp(-max(0.0, past) * 6.0);
  return sin(past * 70.0) * ahead * trailing * exp(-age * 1.1) * smoothstep(0.0, 0.18, age) * 0.12 / (1.0 + r * 4.0);
}

float pointerRipple(vec2 p, vec2 pointer, float strength, float t) {
  if (strength <= 0.0) return 0.0;
  float r = length(p - pointer);
  return sin(r * 90.0 - t * 12.0) * exp(-r * 14.0) * strength * 0.05;
}

float heightAt(vec2 p, vec2 bow, vec2 drop, vec2 pointer, out float foam, out float wake) {
  wake = kelvinWake(p, bow, uTime, foam);
  float h = swell(p, uTime) + wake;
  h += dropRipple(p, drop, uDropAge);
  h += pointerRipple(p, pointer, uPointerStrength, uTime);
  return h;
}

void main() {
  // WebGL's origin is bottom-left; the Metal original is top-left.
  vec2 position = vec2(gl_FragCoord.x, uSize.y * uScale - gl_FragCoord.y) / uScale;
  float scale = 1.0 / max(uSize.y, 1.0);
  vec2 p = position * scale;
  vec2 bow = uBow * scale;
  vec2 drop = uDrop * scale;
  vec2 pointer = uPointer * scale;
  float aspect = uSize.x * scale;

  float foam; float wake; float unusedA; float unusedB;
  float eps = 1.5 * scale;
  float h = heightAt(p, bow, drop, pointer, foam, wake);
  float hx = heightAt(p + vec2(eps, 0.0), bow, drop, pointer, unusedA, unusedB);
  float hy = heightAt(p + vec2(0.0, eps), bow, drop, pointer, unusedA, unusedB);
  vec3 normal = normalize(vec3(-(hx - h) / eps * 0.12, -(hy - h) / eps * 0.12, 1.0));

  vec3 ink = vec3(0.045, 0.043, 0.042);
  vec3 water = mix(ink, vec3(0.06, 0.07, 0.09), smoothstep(1.0, 0.0, p.y));

  vec2 glowA = vec2(aspect * (0.3 + 0.06 * sin(uTime * 0.11)), 0.3 + 0.04 * cos(uTime * 0.14));
  vec2 glowB = vec2(aspect * (0.85 + 0.04 * cos(uTime * 0.07)), 0.95);
  float poolA = exp(-dot(p - glowA, p - glowA) * 3.5);
  float poolB = exp(-dot(p - glowB, p - glowB) * 5.0);
  water += uAccent * poolA * 0.16 + vec3(0.9, 0.55, 0.35) * poolB * 0.06;

  vec3 sky = mix(vec3(0.62, 0.68, 0.78), uAccent, 0.35);

  float crest = clamp(wake * 60.0, -1.0, 1.0);
  water += sky * max(crest, 0.0) * 0.2 * (0.8 + poolA);
  water *= 1.0 + min(crest, 0.0) * 0.35;

  vec3 light = normalize(vec3(-0.35, -0.6, 0.72));
  float lit = dot(normal, light) - light.z;
  water += sky * max(lit, 0.0) * 0.5 * (0.9 + poolA * 1.2);
  water *= 1.0 + min(lit, 0.0) * 0.8;

  vec3 halfway = normalize(light + vec3(0.0, 0.0, 1.0));
  float glint = pow(max(dot(normal, halfway), 0.0), 700.0);
  water += vec3(1.0, 0.97, 0.92) * glint * 0.4;

  water += vec3(0.85, 0.9, 0.95) * clamp(foam, 0.0, 1.0) * 0.08;
  vec2 below = (p - bow - vec2(0.0, 0.012)) * vec2(1.0, 3.0);
  water += vec3(0.9, 0.92, 0.95) * exp(-dot(below, below) * 2600.0) * 0.07;

  vec2 centered = (p - vec2(aspect * 0.5, 0.5)) / vec2(aspect, 1.0);
  water *= 1.0 - dot(centered, centered) * 0.8;
  water = 1.0 - exp(-water * 1.15);
  water += (hash21(position + fract(uTime)) - 0.5) * 0.01;

  gl_FragColor = vec4(clamp(water, 0.0, 1.0), 1.0);
}
`;

const VERTEX = `
attribute vec2 aPosition;
void main() { gl_Position = vec4(aPosition, 0.0, 1.0); }
`;

const BOAT_SVG = `
<svg viewBox="0 0 54 36" width="54" height="36" aria-hidden="true">
  <g stroke="rgba(0,0,0,.08)" stroke-width=".5" stroke-linejoin="round">
    <polygon points="0,20 27,20 27,34 11,34" fill="#bdbab0"/>
    <polygon points="27,20 54,20 43,34 27,34" fill="#e6e3da"/>
    <polygon points="15,20 27,0 27,20" fill="#d6d3c9"/>
    <polygon points="27,20 27,0 39,20" fill="#faf8f1"/>
  </g>
</svg>`;

/**
 * Starts the water in `canvas`. Options:
 * - bowY: the boat's height as a fraction of the canvas (0 top, 1 bottom)
 * - progress: () => 0…1, how far across the boat has sailed
 */
export function startWater(canvas, { bowY = 0.8, progress = () => 0.3 } = {}) {
  const host = canvas.parentElement;
  const gl = canvas.getContext('webgl', { antialias: false, alpha: false, powerPreference: 'low-power' });
  if (!gl) {
    host.classList.add('water-fallback');
    return;
  }
  // Without a GPU the shader runs at a couple of frames a second and starves
  // every other animation on the page, so software renderers get one still frame.
  const debug = gl.getExtension('WEBGL_debug_renderer_info');
  const renderer = debug ? String(gl.getParameter(debug.UNMASKED_RENDERER_WEBGL)) : '';
  const software = /swiftshader|llvmpipe|softpipe|software|basic render/i.test(renderer);
  let still = software || matchMedia('(prefers-reduced-motion: reduce)').matches;

  const compile = (type, source) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
    return shader;
  };

  let program;
  try {
    program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAGMENT));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
  } catch (error) {
    console.warn('Wake water shader failed:', error);
    host.classList.add('water-fallback');
    return;
  }
  gl.useProgram(program);

  // One triangle that covers the view.
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const aPosition = gl.getAttribLocation(program, 'aPosition');
  gl.enableVertexAttribArray(aPosition);
  gl.vertexAttribPointer(aPosition, 2, gl.FLOAT, false, 0, 0);

  const u = {};
  for (const name of ['uSize', 'uTime', 'uDropAge', 'uBow', 'uDrop', 'uPointer', 'uPointerStrength', 'uScale', 'uAccent']) {
    u[name] = gl.getUniformLocation(program, name);
  }
  gl.uniform3f(u.uAccent, 0.24, 0.36, 1.0);

  const boat = document.createElement('div');
  boat.className = 'boat';
  boat.innerHTML = BOAT_SVG;
  host.appendChild(boat);

  // The shader runs a 26-ring loop three times per pixel, so it renders below
  // device resolution and the canvas scales up; grain hides the difference.
  let width = 0, height = 0;
  let quality = 1;
  let renderScale = 0.6;
  const resize = () => {
    const rect = host.getBoundingClientRect();
    width = rect.width;
    height = rect.height;
    renderScale = Math.min(window.devicePixelRatio || 1, width > 1600 ? 0.5 : 0.62) * quality;
    canvas.width = Math.round(width * renderScale);
    canvas.height = Math.round(height * renderScale);
    gl.viewport(0, 0, canvas.width, canvas.height);
  };
  resize();
  new ResizeObserver(() => resize()).observe(host);

  const start = performance.now();
  const now = () => (performance.now() - start) / 1000;
  let drop = { x: -999, y: -999, t: -100 };
  let pointer = { x: -999, y: -999, t: -100 };

  const bow = (t) => ({
    x: width * (0.14 + 0.62 * progress()) + 14 * Math.sin(t * 0.4),
    y: height * bowY + 8 * Math.cos(t * 0.33),
  });

  const local = (event) => {
    const rect = host.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };
  host.addEventListener('pointermove', (event) => {
    if (!still) pointer = { ...local(event), t: now() };
  });
  host.addEventListener('pointerdown', (event) => {
    if (still || event.target.closest('a, button')) return;
    drop = { ...local(event), t: now() };
  });

  const frame = () => {
    const t = still ? 12 : now();
    const b = bow(t);
    gl.uniform2f(u.uSize, width, height);
    gl.uniform1f(u.uScale, renderScale);
    gl.uniform1f(u.uTime, t);
    gl.uniform2f(u.uBow, b.x, b.y);
    gl.uniform2f(u.uDrop, drop.x, drop.y);
    gl.uniform1f(u.uDropAge, t - drop.t);
    gl.uniform2f(u.uPointer, pointer.x, pointer.y);
    gl.uniform1f(u.uPointerStrength, Math.max(0, 1 - (t - pointer.t) / 1.4));
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    const bob = still ? 0 : 1.6 * Math.sin(t * 2.1);
    const rock = still ? 0 : 0.045 * Math.sin(t * 1.7 + 0.6);
    // The boat's waterline sits at (27, 29) in its own box.
    boat.style.transform = `translate(${b.x - 27}px, ${b.y - 29 + bob}px) rotate(${rock}rad)`;
  };

  // Slow frames lower the resolution; still slow at the lowest, the water stops.
  let last = 0;
  let slow = 0;
  let sampled = 0;
  const pace = (stamp) => {
    if (last) {
      sampled++;
      if (stamp - last > 40) slow++;
    }
    last = stamp;
    if (sampled < 24) return;
    if (slow > sampled / 2) {
      if (quality > 0.5) {
        quality *= 0.7;
        resize();
      } else {
        still = true;
        running = false;
        host.classList.add('water-still');
        frame();
      }
    }
    sampled = 0;
    slow = 0;
  };

  let running = false;
  let visible = true;
  const loop = (stamp) => {
    if (!running) return;
    frame();
    pace(stamp);
    if (running) requestAnimationFrame(loop);
  };
  const update = () => {
    const should = visible && !document.hidden && !still;
    if (should && !running) {
      running = true;
      last = 0;
      requestAnimationFrame(loop);
    } else if (!should) {
      running = false;
    }
  };
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    update();
  }).observe(host);
  document.addEventListener('visibilitychange', update);

  frame();
  host.classList.add('water-ready');
  if (still) host.classList.add('water-still');
  update();
  new ResizeObserver(() => still && frame()).observe(host);
}

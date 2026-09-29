// The onboarding stage (WakeWaterShader.swift + WakeWaterView.swift): dark water
// with a Kelvin wake behind a paper boat that travels across as you go through
// the steps. Each step change drops a ring into the water from the bow; the
// pointer disturbs the surface under it. WebGL 1, one full-screen triangle.
//
// Software GL (no GPU, some VMs) can't keep up at full size, so the canvas
// renders at a lower resolution when frames run long; the water is soft enough
// that it still reads.

const VERTEX = `
attribute vec2 corner;
void main() { gl_Position = vec4(corner, 0.0, 1.0); }
`;

// A line-by-line port of the Metal fragment shader. Coordinates are in "height
// units": y runs 0…1 down the view, x 0…aspect.
const FRAGMENT = `
precision highp float;

uniform vec2 size;          // CSS pixels
uniform float pixelScale;   // canvas pixels per CSS pixel
uniform float time;
uniform float dropAge;
uniform vec2 bowPoint;
uniform vec2 dropPoint;
uniform vec2 pointerPoint;
uniform float pointerStrength;
uniform vec3 accent;

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

// Rings sent out from the bow as it moves; where they overlap they draw the V.
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
  wake = kelvinWake(p, bow, time, foam);
  float h = swell(p, time) + wake;
  h += dropRipple(p, drop, dropAge);
  h += pointerRipple(p, pointer, pointerStrength, time);
  return h;
}

void main() {
  // GL counts y from the bottom; the maths, from the top.
  vec2 position = vec2(gl_FragCoord.x, size.y * pixelScale - gl_FragCoord.y) / pixelScale;
  float scale = 1.0 / max(size.y, 1.0);
  vec2 p = position * scale;
  vec2 bow = bowPoint * scale;
  vec2 drop = dropPoint * scale;
  vec2 pointer = pointerPoint * scale;
  float aspect = size.x * scale;

  float foam = 0.0;
  float wake = 0.0;
  float unusedFoam = 0.0;
  float unusedWake = 0.0;
  float eps = 1.5 * scale;
  float h = heightAt(p, bow, drop, pointer, foam, wake);
  float hx = heightAt(p + vec2(eps, 0.0), bow, drop, pointer, unusedFoam, unusedWake);
  float hy = heightAt(p + vec2(0.0, eps), bow, drop, pointer, unusedFoam, unusedWake);
  vec3 normal = normalize(vec3(-(hx - h) / eps * 0.12, -(hy - h) / eps * 0.12, 1.0));

  vec3 ink = vec3(0.045, 0.043, 0.042);
  vec3 water = mix(ink, vec3(0.06, 0.07, 0.09), smoothstep(1.0, 0.0, p.y));

  vec2 glowA = vec2(aspect * (0.3 + 0.06 * sin(time * 0.11)), 0.3 + 0.04 * cos(time * 0.14));
  vec2 glowB = vec2(aspect * (0.85 + 0.04 * cos(time * 0.07)), 0.95);
  float poolA = exp(-dot(p - glowA, p - glowA) * 3.5);
  float poolB = exp(-dot(p - glowB, p - glowB) * 5.0);
  water += accent * poolA * 0.16 + vec3(0.9, 0.55, 0.35) * poolB * 0.06;

  vec3 sky = mix(vec3(0.62, 0.68, 0.78), accent, 0.35);

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
  water += (hash21(position + fract(time)) - 0.5) * 0.01;

  gl_FragColor = vec4(clamp(water, 0.0, 1.0), 1.0);
}
`;

export class WaterRenderer {
  private gl: WebGLRenderingContext | null;
  private program: WebGLProgram | null = null;
  private uniforms: Record<string, WebGLUniformLocation | null> = {};
  private frame = 0;
  private start = performance.now();
  private width = 0;
  private height = 0;
  /** Canvas pixels per CSS pixel: one per point, like the Mac, less when slow. */
  private pixelScale = 1;
  private slowFrames = 0;
  private lastFrame = 0;
  private progressFrom = 0;
  private progressTo = 0;
  private progressStart = -10;
  private drop: { x: number; y: number; time: number } | null = null;
  private pointer: { x: number; y: number; time: number } | null = null;
  private accent: [number, number, number] = [0.2, 0.5, 1];
  private resize: ResizeObserver;

  constructor(
    private canvas: HTMLCanvasElement,
    private boat: HTMLElement | null,
    private still: boolean,
  ) {
    this.gl = canvas.getContext('webgl', { antialias: false, alpha: false, depth: false, powerPreference: 'low-power' });
    if (this.gl) this.prepare(this.gl);
    this.resize = new ResizeObserver(() => this.fit());
    this.resize.observe(canvas);
    this.fit();
    document.addEventListener('visibilitychange', this.visibility);
    this.schedule();
  }

  /** Whether the shader runs (otherwise the canvas's ink background shows). */
  get isRunning() {
    return !!this.program;
  }

  private prepare(gl: WebGLRenderingContext) {
    const compile = (type: number, source: string) => {
      const shader = gl.createShader(type)!;
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        console.warn('Wake water shader:', gl.getShaderInfoLog(shader));
        return null;
      }
      return shader;
    };
    const vertex = compile(gl.VERTEX_SHADER, VERTEX);
    const fragment = compile(gl.FRAGMENT_SHADER, FRAGMENT);
    if (!vertex || !fragment) return;
    const program = gl.createProgram()!;
    gl.attachShader(program, vertex);
    gl.attachShader(program, fragment);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      console.warn('Wake water shader:', gl.getProgramInfoLog(program));
      return;
    }
    gl.useProgram(program);
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    // One triangle that covers the whole view.
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const corner = gl.getAttribLocation(program, 'corner');
    gl.enableVertexAttribArray(corner);
    gl.vertexAttribPointer(corner, 2, gl.FLOAT, false, 0, 0);
    for (const name of ['size', 'pixelScale', 'time', 'dropAge', 'bowPoint', 'dropPoint', 'pointerPoint', 'pointerStrength', 'accent']) {
      this.uniforms[name] = gl.getUniformLocation(program, name);
    }
    this.program = program;
  }

  private get now() {
    return this.still ? 0 : (performance.now() - this.start) / 1000;
  }

  setAccent(hex: string) {
    const n = parseInt(hex.replace('#', ''), 16);
    this.accent = [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
    if (this.still) this.schedule();
  }

  /** 0…1 across the steps: the bow glides there (ease in-out, 1.2 s). */
  setProgress(progress: number, drop: boolean) {
    const t = this.now;
    this.progressFrom = this.progressAt(t);
    this.progressTo = progress;
    this.progressStart = this.still ? -10 : t;
    if (drop && !this.still) {
      const bow = this.bow(t);
      this.drop = { x: bow[0], y: bow[1], time: t };
    }
    if (this.still) this.schedule();
  }

  pointerMoved(x: number, y: number) {
    if (this.still) return;
    this.pointer = { x, y, time: this.now };
  }

  private progressAt(t: number) {
    const k = Math.min(1, Math.max(0, (t - this.progressStart) / 1.2));
    const eased = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
    return this.progressFrom + (this.progressTo - this.progressFrom) * eased;
  }

  /** The head of the wake, in CSS pixels. */
  private bow(t: number): [number, number] {
    return [this.width * (0.2 + 0.6 * this.progressAt(t)) + 14 * Math.sin(t * 0.4), this.height * 0.82 + 8 * Math.cos(t * 0.33)];
  }

  private fit() {
    const rect = this.canvas.getBoundingClientRect();
    this.width = rect.width;
    this.height = rect.height;
    this.applyScale();
    if (this.still) this.schedule();
  }

  private applyScale() {
    const w = Math.max(1, Math.round(this.width * this.pixelScale));
    const h = Math.max(1, Math.round(this.height * this.pixelScale));
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
  }

  private visibility = () => {
    if (document.visibilityState === 'visible') this.schedule();
  };

  private schedule() {
    if (!this.frame) this.frame = requestAnimationFrame(this.render);
  }

  private render = (stamp: number) => {
    this.frame = 0;
    // Frames running long: drop the resolution a step (never below a third).
    if (this.lastFrame && !this.still) {
      const spent = stamp - this.lastFrame;
      this.slowFrames = spent > 40 ? this.slowFrames + 1 : Math.max(0, this.slowFrames - 1);
      if (this.slowFrames > 6 && this.pixelScale > 0.34) {
        this.pixelScale = Math.max(0.33, this.pixelScale * 0.7);
        this.slowFrames = 0;
        this.applyScale();
      }
    }
    this.lastFrame = stamp;
    const t = this.now;
    const bow = this.bow(t);
    if (this.boat) {
      const bob = this.still ? 0 : 1.6 * Math.sin(t * 2.1);
      const rock = this.still ? 0 : 0.045 * Math.sin(t * 1.7 + 0.6);
      this.boat.style.transform = `translate(${bow[0]}px, ${bow[1] - bob}px) rotate(${-rock}rad)`;
    }
    const gl = this.gl;
    if (gl && this.program && this.width > 0 && this.height > 0) {
      const u = this.uniforms;
      gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      gl.uniform2f(u.size, this.width, this.height);
      gl.uniform1f(u.pixelScale, this.canvas.height / this.height);
      gl.uniform1f(u.time, t);
      gl.uniform1f(u.dropAge, this.drop ? t - this.drop.time : 100);
      gl.uniform2f(u.bowPoint, bow[0], bow[1]);
      gl.uniform2f(u.dropPoint, this.drop?.x ?? 0, this.drop?.y ?? 0);
      gl.uniform2f(u.pointerPoint, this.pointer?.x ?? 0, this.pointer?.y ?? 0);
      gl.uniform1f(u.pointerStrength, this.pointer ? Math.max(0, 1 - (t - this.pointer.time) / 1.4) : 0);
      gl.uniform3f(u.accent, ...this.accent);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }
    // Still water draws on demand; moving water, while the window is visible.
    if (!this.still && document.visibilityState === 'visible') this.schedule();
  };

  dispose() {
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.resize.disconnect();
    document.removeEventListener('visibilitychange', this.visibility);
    this.gl?.getExtension('WEBGL_lose_context')?.loseContext();
  }
}

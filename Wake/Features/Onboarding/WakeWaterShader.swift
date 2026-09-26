import Foundation

/// Metal source for `WakeWaterView`, compiled when the view first appears.
///
/// Limitation: a `.metal` file (and SwiftUI's `ShaderLibrary`) needs Xcode's Metal
/// Toolchain, a separate download since Xcode 26 that every build machine would need.
/// Compiling the source with the Metal compiler built into macOS avoids that; the
/// cost is a one-off compile (a few milliseconds) the first time onboarding shows.
enum WakeWaterShader {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

// Water for the onboarding stage: a height field (swell, a Kelvin wake behind a moving
// bow, ring ripples from a drop, a disturbance under the pointer), shaded from its
// wake by its own crests and everything else by its slopes, with glints and a soft
// accent-coloured pool of light. The paper boat itself is drawn by WakeWaterView.
// Coordinates are in "height units": y runs 0…1 down the view, x 0…aspect.

struct Uniforms {
    float2 size;
    float time;
    float dropAge;
    float2 bowPoint;
    float2 dropPoint;
    float2 pointerPoint;
    float pointerStrength;
    float contentScale;
    float4 accent;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut wakeVertex(uint id [[vertex_id]]) {
    // One triangle that covers the whole view.
    float2 corners[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    out.position = float4(corners[id], 0, 1);
    return out;
}

static float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

static float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), u.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), u.x), u.y);
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    const float2x2 rotate = float2x2(1.6, 1.2, -1.2, 1.6);
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p = rotate * p;
        amplitude *= 0.5;
    }
    return value;
}

// Open water: two long swells and a little chop.
static float swell(float2 p, float t) {
    float h = sin(dot(p, float2(0.8, 1.3)) * 7.0 + t * 0.9) * 0.35;
    h += sin(dot(p, float2(-1.1, 0.6)) * 11.0 + t * 1.3) * 0.2;
    h += (fbm(p * 5.0 + float2(t * 0.12, -t * 0.08)) - 0.5) * 0.9;
    return h * 0.08;
}

// The pattern a boat leaves, built the way water makes it: the bow sends out a ring
// seven times a second as it moves, each ring spreads slower than the bow travels, and
// where the rings overlap they draw the V of the wake. Water flows past the bow (it
// keeps its place on screen), so emitters sit at fixed spots behind it and the
// emission phase scrolls with time.
static float kelvinWake(float2 p, float2 bow, float t, thread float &foam) {
    const float rate = 7.0;       // rings per second
    const float boatSpeed = 0.16; // height units per second
    const float ringSpeed = 0.06;
    const int rings = 26;
    // A ring only moves the water within `reach` of its front, and the oldest ring is
    // this far behind the bow and this wide: outside that box there's no wake to
    // add up. Most of the screen is outside it.
    const float reach = 0.12;
    const float oldest = float(rings) / rate;
    float2 q = p - bow;
    foam = 0.0;
    if (q.x > reach || q.x < -(0.012 + (boatSpeed + ringSpeed) * oldest + reach) || abs(q.y) > ringSpeed * oldest + reach) {
        return 0.0;
    }
    float phase = fract(t * rate);
    // Real water never spaces its crests perfectly: nudge every ring a little.
    float jitter = (noise(p * 22.0 + float2(t * 0.4, 0.0)) - 0.5) * 0.009;
    float h = 0.0;
    for (int k = 0; k < rings; k++) {
        float age = (float(k) + phase) / rate;
        // Emitted from the stern, just behind the hull's middle.
        float2 emitter = bow - float2(0.012 + boatSpeed * age, 0.0);
        float r = length(p - emitter);
        float front = ringSpeed * age;
        float d = r - front + jitter;
        if (abs(d) > reach) continue;
        float band = exp(-d * d * 520.0);
        float crest = cos(d * 170.0 - age * 6.0);
        // Rings fade as they grow; the newest fades in so emission doesn't pop.
        float life = exp(-age * 0.9) * smoothstep(0.0, 0.07, age);
        h += crest * band * life;
    }
    float behind = max(0.0, -q.x);
    foam = exp(-q.y * q.y * 1500.0) * exp(-behind * 7.0) * smoothstep(0.005, 0.02, behind);
    return h * 0.016;
}

// A ring spreading from where the last step change dropped into the water.
static float dropRipple(float2 p, float2 center, float age) {
    if (age > 4.0) return 0.0;
    float r = length(p - center);
    float front = age * 0.42;
    float past = front - r;
    float ahead = exp(-max(0.0, -past) * 80.0);
    float trailing = exp(-max(0.0, past) * 6.0);
    // Eased in, so the first frames are a ring opening rather than a dome.
    return sin(past * 70.0) * ahead * trailing * exp(-age * 1.1) * smoothstep(0.0, 0.18, age) * 0.12 / (1.0 + r * 4.0);
}

// A fingertip in the water under the pointer.
static float pointerRipple(float2 p, float2 pointer, float strength, float t) {
    if (strength <= 0.0) return 0.0;
    float r = length(p - pointer);
    return sin(r * 90.0 - t * 12.0) * exp(-r * 14.0) * strength * 0.05;
}

static float heightAt(float2 p, float t, float2 bow, float2 drop, float dropAge,
                      float2 pointer, float pointerStrength, thread float &foam, thread float &wake) {
    wake = kelvinWake(p, bow, t, foam);
    float h = swell(p, t) + wake;
    h += dropRipple(p, drop, dropAge);
    h += pointerRipple(p, pointer, pointerStrength, t);
    return h;
}

fragment half4 wakeFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    // Metal's framebuffer origin is top-left, like SwiftUI's, so only the scale changes.
    float2 position = in.position.xy / u.contentScale;
    float2 size = u.size;
    float time = u.time;
    float2 bowPoint = u.bowPoint;
    float2 dropPoint = u.dropPoint;
    float dropAge = u.dropAge;
    float2 pointerPoint = u.pointerPoint;
    float pointerStrength = u.pointerStrength;
    half4 accent = half4(u.accent);

    float scale = 1.0 / max(size.y, 1.0);
    float2 p = position * scale;
    float2 bow = bowPoint * scale;
    float2 drop = dropPoint * scale;
    float2 pointer = pointerPoint * scale;
    float aspect = size.x * scale;

    float foam = 0.0;
    float wake = 0.0;
    float unused = 0.0;
    float eps = 1.5 * scale;
    float h = heightAt(p, time, bow, drop, dropAge, pointer, pointerStrength, foam, wake);
    float hx = heightAt(p + float2(eps, 0), time, bow, drop, dropAge, pointer, pointerStrength, unused, unused);
    float hy = heightAt(p + float2(0, eps), time, bow, drop, dropAge, pointer, pointerStrength, unused, unused);
    float3 normal = normalize(float3(-(hx - h) / eps * 0.12, -(hy - h) / eps * 0.12, 1.0));

    float3 accentColor = float3(accent.rgb);
    float3 ink = float3(0.045, 0.043, 0.042);
    // A little lighter towards the horizon (the top), as open water reads.
    float3 water = mix(ink, float3(0.06, 0.07, 0.09), smoothstep(1.0, 0.0, p.y));

    // Pools of light the water reflects: the accent, and a warm one low on the right.
    float2 glowA = float2(aspect * (0.3 + 0.06 * sin(time * 0.11)), 0.3 + 0.04 * cos(time * 0.14));
    float2 glowB = float2(aspect * (0.85 + 0.04 * cos(time * 0.07)), 0.95);
    float poolA = exp(-dot(p - glowA, p - glowA) * 3.5);
    float poolB = exp(-dot(p - glowB, p - glowB) * 5.0);
    water += accentColor * poolA * 0.16 + float3(0.9, 0.55, 0.35) * poolB * 0.06;

    float3 sky = mix(float3(0.62, 0.68, 0.78), accentColor, 0.35);

    // The wake is lit by its own height: every crest catches the sky and every
    // trough darkens, whichever way it runs, so both arms and the water between
    // them read as one continuous wake.
    float crest = clamp(wake * 60.0, -1.0, 1.0);
    water += sky * max(crest, 0.0) * 0.2 * (0.8 + poolA);
    water *= 1.0 + min(crest, 0.0) * 0.35;

    // A softer directional light on every slope (swell, drops, the pointer).
    float3 light = normalize(float3(-0.35, -0.6, 0.72));
    float lit = dot(normal, light) - light.z;
    water += sky * max(lit, 0.0) * 0.5 * (0.9 + poolA * 1.2);
    water *= 1.0 + min(lit, 0.0) * 0.8;

    // Sharp glints where a ridge mirrors the light.
    float3 halfway = normalize(light + float3(0, 0, 1));
    float glint = pow(max(dot(normal, halfway), 0.0), 700.0);
    water += float3(1.0, 0.97, 0.92) * glint * 0.4;

    // Churned water at the boat's stern, and its reflection just below the hull.
    water += float3(0.85, 0.9, 0.95) * clamp(foam, 0.0, 1.0) * 0.08;
    float2 below = (p - bow - float2(0.0, 0.012)) * float2(1.0, 3.0);
    water += float3(0.9, 0.92, 0.95) * exp(-dot(below, below) * 2600.0) * 0.07;

    // Vignette, a soft shoulder so nothing clips, and grain against banding.
    float2 centered = (p - float2(aspect * 0.5, 0.5)) / float2(aspect, 1.0);
    water *= 1.0 - dot(centered, centered) * 0.8;
    water = 1.0 - exp(-water * 1.15);
    water += (hash21(position + fract(time)) - 0.5) * 0.01;

    return half4(half3(clamp(water, 0.0, 1.0)), 1.0);
}
"""#
}

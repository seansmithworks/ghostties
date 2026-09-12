//
//  Fog.metal
//  Ghostties
//
//  Round 8 (Sean, live look): "a fog shader with a central focal point."
//  `composerFogDensity` backs `ComposerZeroChromeFogLayer`
//  (`ComposerZeroChromeStyle.swift`) via SwiftUI's `.colorEffect` — macOS 14+
//  only. A cheap, hand-tuned fractal (octaved value) noise, not a physically
//  simulated fog; drifts slowly over `time`, and its alpha is shaped by
//  `ramp` (the summon density/radius ramp) and distance from `focalCenter`
//  (fraction of `size`) so it reads densest at the composer's text block and
//  fades toward the window edges.
//

#include <metal_stdlib>
using namespace metal;

static float2 fogHash(float2 p) {
    float2 k = float2(127.1, 311.7);
    float n = sin(dot(p, k)) * 43758.5453;
    return fract(float2(n, n * 1.618));
}

static float fogValueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = fogHash(i).x;
    float b = fogHash(i + float2(1.0, 0.0)).x;
    float c = fogHash(i + float2(0.0, 1.0)).x;
    float d = fogHash(i + float2(1.0, 1.0)).x;
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Four-octave fractal sum of `fogValueNoise` — cheap "fractal noise" in the
/// colloquial sense (self-similar detail at multiple scales), not a
/// reference fBm implementation.
static float fogFractalNoise(float2 p) {
    float total = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        total += amplitude * fogValueNoise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return total;
}

/// `color` is the pixel already rendered by the SwiftUI view this shader is
/// attached to (a solid, window-background-tinted `Rectangle`) — SwiftUI's
/// `.colorEffect` passes and expects PREMULTIPLIED alpha, so this function
/// reshapes density by scaling all four channels (rgb and alpha together)
/// by a single factor: drifting noise, gated by `ramp` (0 = invisible,
/// 1 = fully summoned) and an outward falloff from `focalCenter` whose
/// reach also grows with `ramp` ("spreading outward from the focal center"
/// per the brief).
[[ stitchable ]] half4 composerFogDensity(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float2 focalCenter,
    float ramp,
    float reach
) {
    float2 safeSize = max(size, float2(1.0, 1.0));
    float2 uv = position / safeSize;
    float2 drift = float2(time * 0.015, time * 0.01);
    float noise = fogFractalNoise(uv * 3.0 + drift);

    float2 focalPx = focalCenter * safeSize;
    float dist = distance(position, focalPx) / max(length(safeSize), 1.0);
    float falloff = 1.0 - smoothstep(0.0, reach, dist);

    float alpha = noise * falloff * ramp;
    half a = half(clamp(alpha, 0.0, 1.0));
    return color * a;
}

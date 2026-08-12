#include <metal_stdlib>
using namespace metal;

// MARK: - Simplex noise
//
// Metal's standard library has no noise function, so this is the classic
// Ashima/Gustavson 3D simplex implementation ported from GLSL. It is used
// rather than value or Perlin noise for one reason: simplex has no axis-aligned
// grid artefacts, and this effect samples it at low frequency over a wide strip,
// which is exactly where a grid would show up as visible horizontal banding.
//
// The third dimension is time. Animating a 2D field by scrolling it looks like a
// texture sliding past; animating a slice through a 3D field looks like the
// shape itself is changing, which is the whole point of the effect.

static float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
static float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);

    // First corner.
    float3 i  = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);

    // Other corners.
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);

    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;

    // Permutations.
    i = mod289(i);
    float4 p = permute(permute(permute(
                 i.z + float4(0.0, i1.z, i2.z, 1.0))
               + i.y + float4(0.0, i1.y, i2.y, 1.0))
               + i.x + float4(0.0, i1.x, i2.x, 1.0));

    // Gradients: 7x7 points over a square, mapped onto an octahedron.
    float n_ = 0.142857142857;
    float3 ns = n_ * D.wyz - D.xzx;

    float4 j = p - 49.0 * floor(p * ns.z * ns.z);

    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);

    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);

    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);

    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));

    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);

    // Normalise gradients.
    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    // Mix final noise value.
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// MARK: - Liquid wave

/// The mock interview's voice visualiser: a body of liquid that folds and swells
/// with the microphone.
///
/// Four things about the signature are load-bearing:
///
/// - `size` is the **view's** size in points, not the screen's. `position` in a
///   `colorEffect` arrives in the view's own coordinate space, so dividing by
///   anything else yields a device-dependent `uv` and the shape stretches.
/// - `time` is seconds since the view appeared, never since a fixed epoch. A
///   32-bit float holds about seven significant digits, so feeding it a
///   reference-date interval (~8e8) leaves under a second of resolution and the
///   motion visibly ratchets.
/// - `tint` carries the theme's accent, so the whole effect is one hue and
///   repaints with the palette. There is deliberately no second colour here.
/// - The result is **premultiplied** — SwiftUI's colour effects require it, and
///   returning straight alpha makes the soft edges glow a halo of full-strength
///   accent instead of fading out.
[[stitchable]] half4 ppLiquidWave(float2 position,
                                  half4 currentColor,
                                  float2 size,
                                  float time,
                                  float level,
                                  half4 tint) {
    if (size.x <= 0.0 || size.y <= 0.0) { return half4(0.0); }

    float2 uv = position / size;
    float u = clamp(uv.x, 0.0, 1.0);
    // 0 at the top edge, 1 at the bottom. The body hangs *from* the top rather
    // than floating around a centre line: anchored to the chrome above it, it
    // reads as part of the screen that the voice is disturbing, where a free
    // beam read as a separate instrument parked in a gap.
    float v = clamp(uv.y, 0.0, 1.0);

    // Low frequency on purpose — around two cells across the whole width. The
    // shapes have to be **big**: at any higher frequency the warp produces fine
    // contour detail and the strip reads as wood grain or smoke rather than as
    // one body of liquid. Sampled anisotropically because the strip is far wider
    // than it is tall, and sampling it squarely would fit several cells across
    // and less than one down, which reads as vertical stripes.
    float2 p = float2(u * 2.6, v * 0.85);

    // Domain warp — the step that separates liquid from fog. Two samples of the
    // field *displace the coordinates* of a third, so the noise folds over
    // itself and shapes stretch and pinch instead of merely sliding past.
    //
    // The voice drives the displacement, and it's the effect's whole dynamic
    // range: at rest the warp is gentle and the blobs drift, and a loud answer
    // more than quadruples it, which is what makes the body visibly churn and
    // tear rather than just grow.
    float warpAmount = 0.28 + clamp(level, 0.0, 1.0) * 1.25;
    float3 seed = float3(p, time);
    float w1 = snoise(seed);
    float w2 = snoise(seed + float3(3.7, 8.3, 1.9));
    float2 warped = p + float2(w1, w2) * warpAmount;

    // Interior shading comes from a **separate** low-frequency field, not from a
    // deeper contour of the one that cuts the silhouettes below: contours of the
    // same field all run parallel to the edge, which bands the body like a
    // hillside instead of lighting it like a fluid. This one is broad and soft —
    // big pools of thick and thin — because fine interior detail is exactly what
    // turned an earlier version into grain. Shared by every layer, so they read
    // as one substance lit once rather than three unrelated sheets.
    float shade = 0.5 + 0.5 * snoise(float3(warped * 0.85 + 21.0, time * 0.6));

    // How far the liquid reaches, before the layers divide it up.
    float depth = 0.36 + 0.56 * clamp(level, 0.0, 1.0);
    // The contour band has to be narrow or there is no surface at all — this is
    // the difference between a body of liquid and a stain. Wider when quiet, so
    // silence still dissolves rather than sitting there with a hard rim.
    float softness = 0.09 + 0.11 * (1.0 - clamp(level, 0.0, 1.0));
    float sides = smoothstep(0.0, 0.16, u) * smoothstep(0.0, 0.16, 1.0 - u);

    // Three sheets of the same liquid, stacked. Each hangs further than the one
    // before it and carries less weight, and they composite over one another —
    // so near the top all three overlap into the darkest band on the screen, and
    // further down progressively fewer of them reach, which is what makes it
    // fade out in strata instead of as one even gradient.
    //
    // Their contours come from the same warped field sampled at **different
    // points on the time axis**, so the sheets are the same substance a moment
    // apart rather than three unrelated shapes — that's what keeps the strata
    // reading as depth in one body of liquid.
    float alpha = 0.0;
    for (int layer = 0; layer < 3; ++layer) {
        float index = float(layer);
        float layerDepth = depth * (0.42 + 0.34 * index);
        // Solid at the top, gone by this layer's depth. This is the one hard
        // boundary that stays, because the body hangs off the chrome above it —
        // fading the top as well would leave it floating in the gap.
        float column = 1.0 - smoothstep(0.0, layerDepth, v);

        // The silhouette is a threshold of the warped field rather than a height
        // function, so the hanging edge is a contour of the fluid itself — lobes,
        // necks and the occasional detached pocket — and it morphs in place
        // instead of undulating past.
        //
        // The field is **added** to the mask, not multiplied by it: multiplying
        // only scales the mask's own gradient, so the boundary stays a smooth arc
        // and the whole thing blurs. Added, the field pushes the contour up in
        // some columns and down in others, which is where the lobes come from.
        float field = snoise(float3(warped, time * 0.75 + 11.0 + index * 4.5));
        float mass = column + field * (0.30 + 0.22 * clamp(level, 0.0, 1.0));
        // Only the topmost sheet is pinned to the edge: it covers the others, so
        // letting theirs tear costs nothing and keeps the strata uneven.
        if (layer == 0) {
            mass = max(mass, 1.0 - smoothstep(0.0, 0.09, v));
        }
        float body = smoothstep(0.5 - softness, 0.5 + softness, mass);

        // The sides fade over a wide margin, not a hairline. This is where the
        // frame actually showed: a short taper reads as the liquid being clipped
        // by a rectangle, and the whole point is that it has no container.
        body *= sides;
        // And a last dissolve at the bottom, so a loud burst that reaches the end
        // of the frame still fades out instead of meeting a straight cut.
        body *= 1.0 - smoothstep(0.72, 1.0, v);

        float weight = 0.38 - 0.09 * index;
        float layerAlpha = body * weight * (0.45 + 0.55 * shade);
        // Composited **over**, not summed: summing saturates to a flat slab
        // wherever the sheets overlap, which is precisely the top band where the
        // layering is supposed to be legible.
        alpha += layerAlpha * (1.0 - alpha);
    }

    alpha = clamp(alpha, 0.0, 1.0) * float(tint.a);

    return half4(tint.rgb * half(alpha), half(alpha));
}

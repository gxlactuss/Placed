#include <metal_stdlib>
using namespace metal;

static float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float4 permute(float4 x) { return mod289(((x * 34.0) + 1.0) * x); }
static float4 taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

static float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);

    float3 i  = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);

    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);

    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;

    i = mod289(i);
    float4 p = permute(permute(permute(
                 i.z + float4(0.0, i1.z, i2.z, 1.0))
               + i.y + float4(0.0, i1.y, i2.y, 1.0))
               + i.x + float4(0.0, i1.x, i2.x, 1.0));

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

    float4 norm = taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x;
    p1 *= norm.y;
    p2 *= norm.z;
    p3 *= norm.w;

    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

[[stitchable]] half4 ppLiquidWave(float2 position,
                                  half4 currentColor,
                                  float2 size,
                                  float time,
                                  float level,
                                  half4 tint) {
    if (size.x <= 0.0 || size.y <= 0.0) { return half4(0.0); }

    float2 uv = position / size;
    float u = clamp(uv.x, 0.0, 1.0);
    float v = clamp(uv.y, 0.0, 1.0);

    float2 p = float2(u * 2.6, v * 0.85);

    float warpAmount = 0.28 + clamp(level, 0.0, 1.0) * 1.25;
    float3 seed = float3(p, time);
    float w1 = snoise(seed);
    float w2 = snoise(seed + float3(3.7, 8.3, 1.9));
    float2 warped = p + float2(w1, w2) * warpAmount;

    float shade = 0.5 + 0.5 * snoise(float3(warped * 0.85 + 21.0, time * 0.6));

    float depth = 0.36 + 0.56 * clamp(level, 0.0, 1.0);
    float softness = 0.09 + 0.11 * (1.0 - clamp(level, 0.0, 1.0));
    float sides = smoothstep(0.0, 0.16, u) * smoothstep(0.0, 0.16, 1.0 - u);

    float alpha = 0.0;
    for (int layer = 0; layer < 3; ++layer) {
        float index = float(layer);
        float layerDepth = depth * (0.42 + 0.34 * index);
        float column = 1.0 - smoothstep(0.0, layerDepth, v);

        float field = snoise(float3(warped, time * 0.75 + 11.0 + index * 4.5));
        float mass = column + field * (0.30 + 0.22 * clamp(level, 0.0, 1.0));
        if (layer == 0) {
            mass = max(mass, 1.0 - smoothstep(0.0, 0.09, v));
        }
        float body = smoothstep(0.5 - softness, 0.5 + softness, mass);

        body *= sides;
        body *= 1.0 - smoothstep(0.72, 1.0, v);

        float weight = 0.38 - 0.09 * index;
        float layerAlpha = body * weight * (0.45 + 0.55 * shade);
        alpha += layerAlpha * (1.0 - alpha);
    }

    alpha = clamp(alpha, 0.0, 1.0) * float(tint.a);

    return half4(tint.rgb * half(alpha), half(alpha));
}

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;
using namespace realitykit;

inline float hash21(float2 p)
{
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p + 34.123);
    return fract(p.x * p.y);
}

inline float noise2(float2 p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Brushed aluminum: true silver satin with clear anisotropic streaks.
[[visible]]
void brushedAluminumSurface(realitykit::surface_parameters params)
{
    float2 uv = params.geometry().uv0();
    float2 p = (uv - 0.5) * 52.0;

    // Light aluminum base (slightly cool), not dark.
    float3 base = float3(0.88, 0.89, 0.90);

    // Fine brushed pattern: very high frequency on Y (horizontal lines),
    // with slight irregular drift on X to avoid periodic "rails".
    float yWarp = noise2(float2(uv.x * 7.0, uv.y * 5.0 + 1.7)) * 10.0
                + noise2(float2(uv.x * 17.0 + 3.1, uv.y * 9.0)) * 4.0;
    float fineA = noise2(float2(uv.y * 3400.0 + yWarp, 0.17));
    float fineB = noise2(float2(uv.y * 6200.0 + yWarp * 1.6 + 13.0, 0.43));
    float fineC = noise2(float2(uv.y * 9100.0 + yWarp * 0.8 + 27.0, 0.71));

    // Very low-amplitude broad component, just to break uniformity.
    float broad = noise2(float2(uv.y * 160.0 + uv.x * 2.0, 0.29));

    // Tiny isotropic grain to avoid synthetic smoothness.
    float grain = hash21(p * 14.0);

    float brushed = fineA * 0.42 + fineB * 0.34 + fineC * 0.18 + broad * 0.03 + grain * 0.03;
    brushed = (brushed - 0.5) * 1.45 + 0.5;
    brushed = clamp(brushed, 0.0, 1.0);

    // Low-frequency patchy variation (real sheet non-uniformity).
    float patchA = noise2(uv * 3.1);
    float patchB = noise2(uv * 6.7 + float2(2.7, 1.9));
    float patch = (patchA * 0.7 + patchB * 0.3 - 0.5) * 0.12;

    // Sparse micro-scratches aligned with brushing direction.
    float scratchNoise = noise2(float2(uv.x * 220.0, uv.y * 30.0 + noise2(uv * 9.0) * 8.0));
    float scratches = smoothstep(0.965, 0.998, scratchNoise) * 0.05;

    // Light map: broad top-left soft key + subtle lower-right cool falloff.
    float key = clamp(1.10 - distance(uv, float2(0.18, 0.20)) * 1.35, 0.0, 1.0);
    float fill = clamp(1.05 - distance(uv, float2(0.86, 0.78)) * 1.55, 0.0, 1.0);
    float lighting = 0.97 + key * 0.16 + fill * 0.05;

    // Curved-edge panel feel.
    float2 d = uv - 0.5;
    float edgeShadow = 1.0 - clamp(dot(d, d) * 1.35, 0.0, 0.16);

    // Brushed modulation around base.
    float brushedFactor = 0.87 + brushed * 0.20;

    float3 color = base * (brushedFactor + patch) * lighting * edgeShadow;
    color += scratches;
    color = clamp(color, float3(0.70), float3(0.99));

    // Neutral silver response (no colored anodized tint).
    float neutral = clamp(key * 0.18, 0.0, 0.18);
    color += float3(0.02, 0.02, 0.02) * neutral;
    color = clamp(color, float3(0.0), float3(1.0));

    // Metal response.
    float rough = 0.24 + (1.0 - brushed) * 0.09 + max(0.0, -patch) * 0.08;
    rough = clamp(rough, 0.20, 0.34);

    params.surface().set_base_color(half3(color));
    // Keep a strong metallic feel but preserve diffuse visibility in low-light AR.
    params.surface().set_metallic(0.60);
    params.surface().set_roughness(rough);
}

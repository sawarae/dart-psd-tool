#include <metal_stdlib>
using namespace metal;

// ── Per-channel blend functions ──

static float3 blendNormal(float3 s, float3 d)     { return s; }
static float3 blendMultiply(float3 s, float3 d)   { return s * d; }
static float3 blendScreen(float3 s, float3 d)     { return s + d - s * d; }

static float3 blendOverlay(float3 s, float3 d) {
    return mix(
        2.0 * s * d,
        1.0 - 2.0 * (1.0 - s) * (1.0 - d),
        step(0.5, d)
    );
}

static float3 blendDarken(float3 s, float3 d)     { return min(s, d); }
static float3 blendLighten(float3 s, float3 d)    { return max(s, d); }

static float3 blendColorDodge(float3 s, float3 d) {
    return mix(
        mix(min(float3(1.0), d / max(1.0 - s, 1.0 / 255.0)), float3(1.0), step(1.0, s)),
        float3(0.0),
        step(d, float3(0.0))
    );
}

static float3 blendColorBurn(float3 s, float3 d) {
    return mix(
        mix(1.0 - min(float3(1.0), (1.0 - d) / max(s, 1.0 / 255.0)), float3(0.0), step(s, float3(0.0))),
        float3(1.0),
        step(1.0, d)
    );
}

static float3 blendHardLight(float3 s, float3 d) {
    return mix(
        2.0 * s * d,
        1.0 - 2.0 * (1.0 - s) * (1.0 - d),
        step(0.5, s)
    );
}

static float3 blendSoftLight(float3 s, float3 d) {
    float3 dd = mix(
        sqrt(d),
        ((16.0 * d - 12.0) * d + 4.0) * d,
        step(d, float3(0.25))
    );
    return mix(
        d - (1.0 - 2.0 * s) * d * (1.0 - d),
        d + (2.0 * s - 1.0) * (dd - d),
        step(0.5, s)
    );
}

static float3 blendDifference(float3 s, float3 d) { return abs(s - d); }
static float3 blendSubtract(float3 s, float3 d)   { return max(float3(0.0), d - s); }
static float3 blendLinearDodge(float3 s, float3 d) { return min(float3(1.0), s + d); }

static float3 blendDivide(float3 s, float3 d) {
    float3 eps = float3(1.0 / 255.0);
    return mix(
        min(float3(1.0), d / max(s, eps)),
        mix(float3(0.0), float3(1.0), step(eps, d)),
        step(s, float3(0.0))
    );
}

static float3 blendExclusion(float3 s, float3 d) { return s + d - 2.0 * s * d; }
static float3 blendLinearBurn(float3 s, float3 d) { return max(float3(0.0), s + d - 1.0); }

static float3 blendVividLight(float3 s, float3 d) {
    return mix(
        blendColorBurn(2.0 * s, d),
        blendColorDodge(2.0 * s - 1.0, d),
        step(0.5, s)
    );
}

static float3 blendLinearLight(float3 s, float3 d) { return clamp(d + 2.0 * s - 1.0, 0.0, 1.0); }

static float3 blendPinLight(float3 s, float3 d) {
    return mix(
        min(d, 2.0 * s),
        max(d, 2.0 * s - 1.0),
        step(0.5, s)
    );
}

static float3 blendHardMix(float3 s, float3 d) {
    return step(0.5, blendVividLight(s, d));
}

// ── HSL helper functions (W3C Compositing and Blending Level 1) ──

static float lum(float3 c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b; }

static float sat(float3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }

static float3 clipColor(float3 c) {
    float l = lum(c);
    float n = min(c.r, min(c.g, c.b));
    float x = max(c.r, max(c.g, c.b));
    if (n < 0.0) {
        c = l + (c - l) * l / (l - n);
    }
    if (x > 1.0) {
        c = l + (c - l) * (1.0 - l) / (x - l);
    }
    return clamp(c, 0.0, 1.0);
}

static float3 setLum(float3 c, float l) {
    float d = l - lum(c);
    return clipColor(c + d);
}

static float3 setSat(float3 c, float s) {
    float cmin = min(c.r, min(c.g, c.b));
    float cmax = max(c.r, max(c.g, c.b));

    if (cmax > cmin) {
        return (c - cmin) * s / (cmax - cmin);
    }
    return float3(0.0);
}

// ── Per-pixel blend modes (index 20-25) ──

static float3 blendDarkerColor(float3 s, float3 d) {
    return lum(s) < lum(d) ? s : d;
}

static float3 blendLighterColor(float3 s, float3 d) {
    return lum(s) > lum(d) ? s : d;
}

static float3 blendHue(float3 s, float3 d) {
    return setLum(setSat(s, sat(d)), lum(d));
}

static float3 blendSaturation(float3 s, float3 d) {
    return setLum(setSat(d, sat(s)), lum(d));
}

static float3 blendColor(float3 s, float3 d) {
    return setLum(s, lum(d));
}

static float3 blendLuminosity(float3 s, float3 d) {
    return setLum(d, lum(s));
}

// ── Dispatch blend mode by index ──

static float3 blendPixels(float3 s, float3 d, int mode) {
    switch (mode) {
        case 0:  return blendNormal(s, d);
        case 1:  return blendMultiply(s, d);
        case 2:  return blendScreen(s, d);
        case 3:  return blendOverlay(s, d);
        case 4:  return blendDarken(s, d);
        case 5:  return blendLighten(s, d);
        case 6:  return blendColorDodge(s, d);
        case 7:  return blendColorBurn(s, d);
        case 8:  return blendHardLight(s, d);
        case 9:  return blendSoftLight(s, d);
        case 10: return blendDifference(s, d);
        case 11: return blendSubtract(s, d);
        case 12: return blendLinearDodge(s, d);
        case 13: return blendDivide(s, d);
        case 14: return blendExclusion(s, d);
        case 15: return blendLinearBurn(s, d);
        case 16: return blendVividLight(s, d);
        case 17: return blendLinearLight(s, d);
        case 18: return blendPinLight(s, d);
        case 19: return blendHardMix(s, d);
        case 20: return blendDarkerColor(s, d);
        case 21: return blendLighterColor(s, d);
        case 22: return blendHue(s, d);
        case 23: return blendSaturation(s, d);
        case 24: return blendColor(s, d);
        case 25: return blendLuminosity(s, d);
        default: return blendNormal(s, d);
    }
}

// ── Uniforms ──

struct CompositeParams {
    uint width;
    uint height;
    float opacity;
    int blendMode;  // 0=Normal .. 25=Luminosity
};

// ── Un-premultiply alpha ──

static float4 unpremultiply(float4 c) {
    if (c.a < 1.0 / 255.0) return float4(0.0);
    return float4(c.rgb / c.a, c.a);
}

// ── Compute kernel ──
// Input/output buffers: RGBA8 pixels packed as uint32 (ABGR on little-endian).
// The kernel reads src and dst, composites using PSDTool's 3-component alpha
// blending, and writes the result to the output buffer.

kernel void psdComposite(
    device const uchar4* src      [[buffer(0)]],
    device const uchar4* dst      [[buffer(1)]],
    device uchar4*       output   [[buffer(2)]],
    constant CompositeParams& params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.width || gid.y >= params.height) return;

    uint idx = gid.y * params.width + gid.x;

    // Read RGBA pixels and convert to float [0,1]
    float4 srcPixel = float4(src[idx]) / 255.0;
    float4 dstPixel = float4(dst[idx]) / 255.0;

    // Source and dest are straight alpha
    float sa = srcPixel.a;
    float da = dstPixel.a;

    if (sa < 1.0 / 255.0) {
        output[idx] = dst[idx];
        return;
    }

    float3 sRgb = srcPixel.rgb;
    float3 dRgb = dstPixel.rgb;

    // PSDTool 3-component alpha compositing
    float tmp = sa * params.opacity;
    float a1 = tmp * da;           // blend result contribution
    float a2 = tmp * (1.0 - da);  // source-only
    float a3 = (1.0 - tmp) * da;  // dest-only
    float a  = a1 + a2 + a3;

    if (a < 1.0 / 255.0) {
        output[idx] = uchar4(0);
        return;
    }

    // Apply blend function
    float3 blended = blendPixels(sRgb, dRgb, params.blendMode);

    // Final composite
    float3 outRgb = (blended * a1 + sRgb * a2 + dRgb * a3) / a;
    outRgb = clamp(outRgb, 0.0, 1.0);

    // Write straight-alpha RGBA output
    output[idx] = uchar4(
        uchar(outRgb.r * 255.0 + 0.5),
        uchar(outRgb.g * 255.0 + 0.5),
        uchar(outRgb.b * 255.0 + 0.5),
        uchar(a * 255.0 + 0.5)
    );
}

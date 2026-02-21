#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uOpacity;
uniform float uBlendMode;  // 0=Normal .. 25=Luminosity
uniform sampler2D uSrc;
uniform sampler2D uDst;

out vec4 fragColor;

// Un-premultiply alpha
vec4 unpremultiply(vec4 c) {
  if (c.a < 1.0 / 255.0) return vec4(0.0);
  return vec4(c.rgb / c.a, c.a);
}

// ── Per-channel blend functions ──

vec3 blendNormal(vec3 s, vec3 d)     { return s; }
vec3 blendMultiply(vec3 s, vec3 d)   { return s * d; }
vec3 blendScreen(vec3 s, vec3 d)     { return s + d - s * d; }

vec3 blendOverlay(vec3 s, vec3 d) {
  return mix(
    2.0 * s * d,
    1.0 - 2.0 * (1.0 - s) * (1.0 - d),
    step(0.5, d)
  );
}

vec3 blendDarken(vec3 s, vec3 d)     { return min(s, d); }
vec3 blendLighten(vec3 s, vec3 d)    { return max(s, d); }

vec3 blendColorDodge(vec3 s, vec3 d) {
  return mix(
    mix(min(vec3(1.0), d / max(1.0 - s, 1.0 / 255.0)), vec3(1.0), step(1.0, s)),
    vec3(0.0),
    step(d, vec3(0.0))
  );
}

vec3 blendColorBurn(vec3 s, vec3 d) {
  return mix(
    mix(1.0 - min(vec3(1.0), (1.0 - d) / max(s, 1.0 / 255.0)), vec3(0.0), step(s, vec3(0.0))),
    vec3(1.0),
    step(1.0, d)
  );
}

vec3 blendHardLight(vec3 s, vec3 d) {
  return mix(
    2.0 * s * d,
    1.0 - 2.0 * (1.0 - s) * (1.0 - d),
    step(0.5, s)
  );
}

vec3 blendSoftLight(vec3 s, vec3 d) {
  vec3 dd = mix(
    sqrt(d),
    ((16.0 * d - 12.0) * d + 4.0) * d,
    step(d, vec3(0.25))
  );
  return mix(
    d - (1.0 - 2.0 * s) * d * (1.0 - d),
    d + (2.0 * s - 1.0) * (dd - d),
    step(0.5, s)
  );
}

vec3 blendDifference(vec3 s, vec3 d) { return abs(s - d); }
vec3 blendSubtract(vec3 s, vec3 d)   { return max(vec3(0.0), d - s); }
vec3 blendLinearDodge(vec3 s, vec3 d) { return min(vec3(1.0), s + d); }

// ── New per-channel blend modes (index 13-19) ──

vec3 blendDivide(vec3 s, vec3 d) {
  // d/s, but if s==0: d>0 → 1, d==0 → 0
  vec3 eps = vec3(1.0 / 255.0);
  return mix(
    min(vec3(1.0), d / max(s, eps)),
    mix(vec3(0.0), vec3(1.0), step(eps, d)),
    step(s, vec3(0.0))
  );
}

vec3 blendExclusion(vec3 s, vec3 d) { return s + d - 2.0 * s * d; }
vec3 blendLinearBurn(vec3 s, vec3 d) { return max(vec3(0.0), s + d - 1.0); }

vec3 blendVividLight(vec3 s, vec3 d) {
  return mix(
    blendColorBurn(2.0 * s, d),
    blendColorDodge(2.0 * s - 1.0, d),
    step(0.5, s)
  );
}

vec3 blendLinearLight(vec3 s, vec3 d) { return clamp(d + 2.0 * s - 1.0, 0.0, 1.0); }

vec3 blendPinLight(vec3 s, vec3 d) {
  return mix(
    min(d, 2.0 * s),
    max(d, 2.0 * s - 1.0),
    step(0.5, s)
  );
}

vec3 blendHardMix(vec3 s, vec3 d) {
  return step(0.5, blendVividLight(s, d));
}

// ── HSL helper functions (W3C Compositing and Blending Level 1) ──

float lum(vec3 c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b; }

float sat(vec3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }

vec3 clipColor(vec3 c) {
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

vec3 setLum(vec3 c, float l) {
  float d = l - lum(c);
  return clipColor(c + d);
}

vec3 setSat(vec3 c, float s) {
  // Sort channels: find min, mid, max
  float cmin = min(c.r, min(c.g, c.b));
  float cmax = max(c.r, max(c.g, c.b));

  if (cmax > cmin) {
    // Scale: (channel - cmin) * s / (cmax - cmin), then min=0, max=s
    vec3 result = (c - cmin) * s / (cmax - cmin);
    // Fix: ensure min channel is exactly 0 and max is exactly s
    // The min channels map to 0, max maps to s, mid scales proportionally
    return result;
  }
  return vec3(0.0);
}

// ── Per-pixel blend modes (index 20-25) ──

vec3 blendDarkerColor(vec3 s, vec3 d) {
  return lum(s) < lum(d) ? s : d;
}

vec3 blendLighterColor(vec3 s, vec3 d) {
  return lum(s) > lum(d) ? s : d;
}

vec3 blendHue(vec3 s, vec3 d) {
  return setLum(setSat(s, sat(d)), lum(d));
}

vec3 blendSaturation(vec3 s, vec3 d) {
  return setLum(setSat(d, sat(s)), lum(d));
}

vec3 blendColor(vec3 s, vec3 d) {
  return setLum(s, lum(d));
}

vec3 blendLuminosity(vec3 s, vec3 d) {
  return setLum(d, lum(s));
}

// ── Dispatch blend mode by index ──

vec3 blendPixels(vec3 s, vec3 d, float mode) {
  int m = int(mode + 0.5);
  if (m == 0)  return blendNormal(s, d);
  if (m == 1)  return blendMultiply(s, d);
  if (m == 2)  return blendScreen(s, d);
  if (m == 3)  return blendOverlay(s, d);
  if (m == 4)  return blendDarken(s, d);
  if (m == 5)  return blendLighten(s, d);
  if (m == 6)  return blendColorDodge(s, d);
  if (m == 7)  return blendColorBurn(s, d);
  if (m == 8)  return blendHardLight(s, d);
  if (m == 9)  return blendSoftLight(s, d);
  if (m == 10) return blendDifference(s, d);
  if (m == 11) return blendSubtract(s, d);
  if (m == 12) return blendLinearDodge(s, d);
  if (m == 13) return blendDivide(s, d);
  if (m == 14) return blendExclusion(s, d);
  if (m == 15) return blendLinearBurn(s, d);
  if (m == 16) return blendVividLight(s, d);
  if (m == 17) return blendLinearLight(s, d);
  if (m == 18) return blendPinLight(s, d);
  if (m == 19) return blendHardMix(s, d);
  if (m == 20) return blendDarkerColor(s, d);
  if (m == 21) return blendLighterColor(s, d);
  if (m == 22) return blendHue(s, d);
  if (m == 23) return blendSaturation(s, d);
  if (m == 24) return blendColor(s, d);
  if (m == 25) return blendLuminosity(s, d);
  return blendNormal(s, d);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;

  // Sample source and destination (premultiplied alpha from Flutter)
  vec4 srcPre = texture(uSrc, uv);
  vec4 dstPre = texture(uDst, uv);

  // Un-premultiply to get straight alpha
  vec4 s = unpremultiply(srcPre);
  vec4 d = unpremultiply(dstPre);

  // PSDTool 3-component alpha compositing
  float tmp = s.a * uOpacity;
  float a1 = tmp * d.a;           // blend result contribution
  float a2 = tmp * (1.0 - d.a);  // source-only
  float a3 = (1.0 - tmp) * d.a;  // dest-only
  float a  = a1 + a2 + a3;

  if (a < 1.0 / 255.0) {
    fragColor = vec4(0.0);
    return;
  }

  // Apply blend function
  vec3 blended = blendPixels(s.rgb, d.rgb, uBlendMode);

  // Final composite
  vec3 outRgb = (blended * a1 + s.rgb * a2 + d.rgb * a3) / a;

  // Re-premultiply for Flutter compositing
  fragColor = vec4(outRgb * a, a);
}

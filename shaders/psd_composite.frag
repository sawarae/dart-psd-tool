#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uOpacity;
uniform float uBlendMode;  // 0=Normal, 1=Multiply, 2=Screen, 3=Overlay, etc.
uniform sampler2D uSrc;
uniform sampler2D uDst;

out vec4 fragColor;

// Un-premultiply alpha
vec4 unpremultiply(vec4 c) {
  if (c.a < 1.0 / 255.0) return vec4(0.0);
  return vec4(c.rgb / c.a, c.a);
}

// Per-channel blend functions (matching PsdBlendModes integer math)
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

// Dispatch blend mode by index
vec3 blendChannels(vec3 s, vec3 d, float mode) {
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
  vec3 blended = blendChannels(s.rgb, d.rgb, uBlendMode);

  // Final composite
  vec3 outRgb = (blended * a1 + s.rgb * a2 + d.rgb * a3) / a;

  // Re-premultiply for Flutter compositing
  fragColor = vec4(outRgb * a, a);
}

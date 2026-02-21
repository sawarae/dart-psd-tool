import 'dart:math' as math;

/// Per-channel blend function: (source, destination) → blended value.
/// All values are 0-255 integers.
typedef BlendFn = int Function(int s, int d);

/// Per-pixel blend function operating on all 3 RGB channels at once.
/// Used for blend modes that need cross-channel information (HSL modes,
/// DarkerColor, LighterColor).
typedef PixelBlendFn = (int r, int g, int b) Function(
    int sr, int sg, int sb, int dr, int dg, int db);

/// PSDTool-compatible blend mode functions (0-255 integer math).
///
/// Reference: PSDTool src/blend/blend.ts + W3C Compositing and Blending L1.
/// Uses 32897 fixed-point scaling: `(a * b * 32897) >> 23` ≈ `a * b / 255`.
///
/// Supports all 27 PSD blend modes:
/// - 20 per-channel modes in [functions]
/// - 6 per-pixel modes in [pixelFunctions]
/// - Dissolve (handled specially by the compositor)
class PsdBlendModes {
  PsdBlendModes._();

  // ── Per-channel blend functions ──

  /// Map of blend mode name → per-channel blend function.
  static const Map<String, BlendFn> functions = {
    'Normal': normal,
    'Multiply': multiply,
    'Screen': screen,
    'Overlay': overlay,
    'Darken': darken,
    'Lighten': lighten,
    'ColorDodge': colorDodge,
    'ColorBurn': colorBurn,
    'HardLight': hardLight,
    'SoftLight': softLight,
    'Difference': difference,
    'Subtract': subtract,
    'LinearDodge': linearDodge,
    'Divide': divide,
    'Exclusion': exclusion,
    'LinearBurn': linearBurn,
    'VividLight': vividLight,
    'LinearLight': linearLight,
    'PinLight': pinLight,
    'HardMix': hardMix,
  };

  /// Resolve a per-channel blend mode string to its function.
  /// Defaults to [normal].
  static BlendFn resolve(String mode) => functions[mode] ?? normal;

  // ── Per-pixel blend functions (need all 3 RGB channels) ──

  /// Map of blend mode name → per-pixel blend function.
  static final Map<String, PixelBlendFn> pixelFunctions = {
    'DarkerColor': darkerColor,
    'LighterColor': lighterColor,
    'Hue': hue,
    'Saturation': saturation,
    'Color': color,
    'Luminosity': luminosity,
  };

  /// Resolve any blend mode to a unified per-pixel function.
  ///
  /// Per-channel modes are wrapped to operate on all 3 channels.
  /// Returns null for 'Dissolve' (handled specially by the compositor).
  static PixelBlendFn? resolveComposite(String mode) {
    if (mode == 'Dissolve') return null;
    final pixelFn = pixelFunctions[mode];
    if (pixelFn != null) return pixelFn;
    final chFn = functions[mode] ?? normal;
    return (sr, sg, sb, dr, dg, db) =>
        (chFn(sr, dr), chFn(sg, dg), chFn(sb, db));
  }

  // ── Per-channel implementations ──

  static int normal(int s, int d) => s;

  /// Multiply: src * dst / 255
  static int multiply(int s, int d) => (s * d * 32897) >> 23;

  /// Screen: s + d - s*d/255
  static int screen(int s, int d) => s + d - ((s * d * 32897) >> 23);

  /// Overlay: if d < 128 → 2*s*d/255, else 255 - 2*(255-s)*(255-d)/255
  static int overlay(int s, int d) => d < 128
      ? (2 * s * d * 32897) >> 23
      : 255 - ((2 * (255 - s) * (255 - d) * 32897) >> 23);

  static int darken(int s, int d) => math.min(s, d);

  static int lighten(int s, int d) => math.max(s, d);

  /// ColorDodge: d == 0 → 0, s == 255 → 255, else min(255, d*255/(255-s))
  static int colorDodge(int s, int d) {
    if (d == 0) return 0;
    if (s == 255) return 255;
    return math.min(255, (d * 255) ~/ (255 - s));
  }

  /// ColorBurn: d == 255 → 255, s == 0 → 0, else 255 - min(255, (255-d)*255/s)
  static int colorBurn(int s, int d) {
    if (d == 255) return 255;
    if (s == 0) return 0;
    return 255 - math.min(255, ((255 - d) * 255) ~/ s);
  }

  /// HardLight: if s < 128 → 2*s*d/255, else 255 - 2*(255-s)*(255-d)/255
  static int hardLight(int s, int d) => s < 128
      ? (2 * s * d * 32897) >> 23
      : 255 - ((2 * (255 - s) * (255 - d) * 32897) >> 23);

  /// SoftLight (W3C formula)
  ///
  /// If Cs <= 0.5: B = Cb - (1-2*Cs)*Cb*(1-Cb)
  /// If Cs > 0.5:
  ///   D(Cb) = if Cb<=0.25: ((16*Cb-12)*Cb+4)*Cb else: sqrt(Cb)
  ///   B = Cb + (2*Cs-1)*(D(Cb)-Cb)
  static int softLight(int s, int d) {
    if (s < 128) {
      // d - (255-2s) * d * (255-d) / 255 / 255
      final t = (((255 - 2 * s) * d * (255 - d)) * 32897) >> 23;
      return d - ((t * 32897) >> 23);
    }
    final int dd;
    if (d < 64) {
      // ((16*d - 12*255) * d / 255 + 4*255) * d / 255
      final t = (((16 * d - 12 * 255) * d * 32897) >> 23) + 4 * 255;
      dd = (t * d * 32897) >> 23;
    } else {
      dd = (math.sqrt(d / 255.0) * 255).round();
    }
    // d + (2*s - 255) * (dd - d) / 255
    return d + (((2 * s - 255) * (dd - d) * 32897) >> 23);
  }

  static int difference(int s, int d) => (s - d).abs();

  static int subtract(int s, int d) => math.max(0, d - s);

  /// LinearDodge (Add): min(255, s + d)
  static int linearDodge(int s, int d) => math.min(255, s + d);

  /// Divide: min(255, d * 255 / s). Division by zero → 255 if d>0, else 0.
  static int divide(int s, int d) {
    if (s == 0) return d > 0 ? 255 : 0;
    return math.min(255, (d * 255) ~/ s);
  }

  /// Exclusion: s + d - 2*s*d/255
  static int exclusion(int s, int d) => s + d - ((2 * s * d * 32897) >> 23);

  /// LinearBurn: max(0, s + d - 255)
  static int linearBurn(int s, int d) => math.max(0, s + d - 255);

  /// VividLight: if s < 128 → ColorBurn(2*s, d), else ColorDodge(2*s-255, d)
  static int vividLight(int s, int d) =>
      s < 128 ? colorBurn(2 * s, d) : colorDodge(2 * s - 255, d);

  /// LinearLight: clamp(d + 2*s - 255)
  static int linearLight(int s, int d) =>
      (d + 2 * s - 255).clamp(0, 255);

  /// PinLight: if s < 128 → min(d, 2*s), else max(d, 2*s - 255)
  static int pinLight(int s, int d) =>
      s < 128 ? math.min(d, 2 * s) : math.max(d, 2 * s - 255);

  /// HardMix: threshold based on VividLight result.
  /// Photoshop: if VividLight(s, d) >= 128 → 255, else 0.
  static int hardMix(int s, int d) => vividLight(s, d) >= 128 ? 255 : 0;

  // ── Per-pixel implementations ──

  /// DarkerColor: pick the pixel with lower luminance.
  static (int, int, int) darkerColor(
      int sr, int sg, int sb, int dr, int dg, int db) {
    return _lum(sr, sg, sb) < _lum(dr, dg, db)
        ? (sr, sg, sb)
        : (dr, dg, db);
  }

  /// LighterColor: pick the pixel with higher luminance.
  static (int, int, int) lighterColor(
      int sr, int sg, int sb, int dr, int dg, int db) {
    return _lum(sr, sg, sb) > _lum(dr, dg, db)
        ? (sr, sg, sb)
        : (dr, dg, db);
  }

  /// Hue: keep dst luminosity and saturation, use src hue.
  /// W3C: SetLum(SetSat(Cs, Sat(Cb)), Lum(Cb))
  static (int, int, int) hue(
      int sr, int sg, int sb, int dr, int dg, int db) {
    final (r, g, b) = _setSat(sr, sg, sb, _sat(dr, dg, db));
    return _setLum(r, g, b, _lum(dr, dg, db));
  }

  /// Saturation: keep dst luminosity and hue, use src saturation.
  /// W3C: SetLum(SetSat(Cb, Sat(Cs)), Lum(Cb))
  static (int, int, int) saturation(
      int sr, int sg, int sb, int dr, int dg, int db) {
    final (r, g, b) = _setSat(dr, dg, db, _sat(sr, sg, sb));
    return _setLum(r, g, b, _lum(dr, dg, db));
  }

  /// Color: keep dst luminosity, use src hue and saturation.
  /// W3C: SetLum(Cs, Lum(Cb))
  static (int, int, int) color(
      int sr, int sg, int sb, int dr, int dg, int db) {
    return _setLum(sr, sg, sb, _lum(dr, dg, db));
  }

  /// Luminosity: keep dst hue and saturation, use src luminosity.
  /// W3C: SetLum(Cb, Lum(Cs))
  static (int, int, int) luminosity(
      int sr, int sg, int sb, int dr, int dg, int db) {
    return _setLum(dr, dg, db, _lum(sr, sg, sb));
  }

  // ── HSL helpers (W3C Compositing and Blending Level 1) ──

  /// BT.601 luminance: 0.299*R + 0.587*G + 0.114*B
  static int _lum(int r, int g, int b) => (299 * r + 587 * g + 114 * b) ~/ 1000;

  /// Saturation: max(R,G,B) - min(R,G,B)
  static int _sat(int r, int g, int b) =>
      math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));

  /// ClipColor: clamp RGB so all channels stay in 0-255 while preserving hue.
  static (int, int, int) _clipColor(int r, int g, int b) {
    final l = _lum(r, g, b);
    final n = math.min(r, math.min(g, b));
    final x = math.max(r, math.max(g, b));

    int cr = r, cg = g, cb = b;
    if (n < 0) {
      final d = l - n; // always > 0
      cr = l + ((cr - l) * l) ~/ d;
      cg = l + ((cg - l) * l) ~/ d;
      cb = l + ((cb - l) * l) ~/ d;
    }
    if (x > 255) {
      final d = x - l; // always > 0
      final f = 255 - l;
      cr = l + ((cr - l) * f) ~/ d;
      cg = l + ((cg - l) * f) ~/ d;
      cb = l + ((cb - l) * f) ~/ d;
    }
    return (cr.clamp(0, 255), cg.clamp(0, 255), cb.clamp(0, 255));
  }

  /// SetLum: shift RGB to target luminance, then clip.
  static (int, int, int) _setLum(int r, int g, int b, int l) {
    final d = l - _lum(r, g, b);
    return _clipColor(r + d, g + d, b + d);
  }

  /// SetSat: scale RGB channels to target saturation, preserving hue.
  ///
  /// Sorts channels into min/mid/max, then redistributes:
  /// min=0, mid=(mid-min)*s/(max-min), max=s.
  static (int, int, int) _setSat(int r, int g, int b, int s) {
    // Identify min, mid, max channel indices
    // 0=R, 1=G, 2=B
    int minI = 0, midI = 1, maxI = 2;
    final vals = [r, g, b];

    if (vals[minI] > vals[midI]) {
      final t = minI;
      minI = midI;
      midI = t;
    }
    if (vals[midI] > vals[maxI]) {
      final t = midI;
      midI = maxI;
      maxI = t;
    }
    if (vals[minI] > vals[midI]) {
      final t = minI;
      minI = midI;
      midI = t;
    }

    final result = [0, 0, 0];
    if (vals[maxI] > vals[minI]) {
      result[midI] =
          ((vals[midI] - vals[minI]) * s) ~/ (vals[maxI] - vals[minI]);
      result[maxI] = s;
    }
    // result[minI] is already 0
    return (result[0], result[1], result[2]);
  }
}

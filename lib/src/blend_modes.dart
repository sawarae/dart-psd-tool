import 'dart:math' as math;

/// Per-channel blend function: (source, destination) → blended value.
/// All values are 0-255 integers.
typedef BlendFn = int Function(int s, int d);

/// PSDTool-compatible blend mode functions (per-channel, 0-255 integer math).
///
/// Reference: PSDTool src/blend/blend.ts + W3C Compositing and Blending L1.
/// Uses 32897 fixed-point scaling: `(a * b * 32897) >> 23` ≈ `a * b / 255`.
class PsdBlendModes {
  PsdBlendModes._();

  /// Map of blend mode name → blend function.
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
  };

  /// Resolve a blend mode string to its function. Defaults to [normal].
  static BlendFn resolve(String mode) => functions[mode] ?? normal;

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
  static int softLight(int s, int d) {
    if (s < 128) {
      return d - ((255 - 2 * s) * d * (255 - d) * 32897 >> 23) * 32897 >> 23;
    }
    final dd = d < 64
        ? ((16 * d - 12 * 255) * d * 32897 >> 23 + 4 * 255) * d * 32897 >> 23
        : (math.sqrt(d / 255.0) * 255).round();
    return d + ((2 * s - 255) * (dd - d) * 32897) >> 23;
  }

  static int difference(int s, int d) => (s - d).abs();

  static int subtract(int s, int d) => math.max(0, d - s);

  /// LinearDodge (Add): min(255, s + d)
  static int linearDodge(int s, int d) => math.min(255, s + d);
}

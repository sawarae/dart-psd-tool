import 'package:flutter_test/flutter_test.dart';
import 'package:dart_psd_tool/dart_psd_tool.dart';

void main() {
  group('PsdBlendModes', () {
    // ── Existing per-channel modes ──

    test('normal returns source', () {
      expect(PsdBlendModes.normal(100, 200), 100);
      expect(PsdBlendModes.normal(0, 255), 0);
      expect(PsdBlendModes.normal(255, 0), 255);
    });

    test('multiply', () {
      // 128 * 128 / 255 ≈ 64
      expect(PsdBlendModes.multiply(128, 128), closeTo(64, 1));
      expect(PsdBlendModes.multiply(255, 255), 255);
      expect(PsdBlendModes.multiply(0, 255), 0);
      expect(PsdBlendModes.multiply(255, 0), 0);
    });

    test('screen', () {
      // s + d - s*d/255 = 128 + 128 - 64 ≈ 192
      expect(PsdBlendModes.screen(128, 128), closeTo(192, 1));
      expect(PsdBlendModes.screen(0, 0), 0);
      expect(PsdBlendModes.screen(255, 255), 255);
    });

    test('overlay', () {
      // d < 128: 2*s*d/255
      expect(PsdBlendModes.overlay(128, 64), closeTo(64, 1));
      // d >= 128: 255 - 2*(255-s)*(255-d)/255
      expect(PsdBlendModes.overlay(128, 192), closeTo(192, 1));
    });

    test('darken returns minimum', () {
      expect(PsdBlendModes.darken(100, 200), 100);
      expect(PsdBlendModes.darken(200, 100), 100);
    });

    test('lighten returns maximum', () {
      expect(PsdBlendModes.lighten(100, 200), 200);
      expect(PsdBlendModes.lighten(200, 100), 200);
    });

    test('colorDodge', () {
      expect(PsdBlendModes.colorDodge(0, 0), 0);
      expect(PsdBlendModes.colorDodge(255, 128), 255);
      expect(PsdBlendModes.colorDodge(128, 0), 0);
      // 128 * 255 / (255 - 128) = 256.94.. → clamped to 255
      expect(PsdBlendModes.colorDodge(128, 128), 255);
    });

    test('colorBurn', () {
      expect(PsdBlendModes.colorBurn(128, 255), 255);
      expect(PsdBlendModes.colorBurn(0, 128), 0);
      // 255 - min(255, (255-128)*255/128) = 255 - 253 = 2
      expect(PsdBlendModes.colorBurn(128, 128), closeTo(2, 1));
    });

    test('hardLight', () {
      // s < 128: 2*s*d/255
      expect(PsdBlendModes.hardLight(64, 128), closeTo(64, 1));
      // s >= 128: 255 - 2*(255-s)*(255-d)/255
      expect(PsdBlendModes.hardLight(192, 128), closeTo(192, 1));
    });

    test('difference', () {
      expect(PsdBlendModes.difference(200, 100), 100);
      expect(PsdBlendModes.difference(100, 200), 100);
      expect(PsdBlendModes.difference(128, 128), 0);
    });

    test('subtract', () {
      expect(PsdBlendModes.subtract(100, 200), 100);
      expect(PsdBlendModes.subtract(200, 100), 0);
    });

    test('linearDodge', () {
      expect(PsdBlendModes.linearDodge(100, 100), 200);
      expect(PsdBlendModes.linearDodge(200, 200), 255);
    });

    // ── New per-channel modes ──

    test('divide', () {
      // d * 255 / s
      expect(PsdBlendModes.divide(255, 128), 128);
      expect(PsdBlendModes.divide(128, 255), 255); // clamped
      expect(PsdBlendModes.divide(0, 128), 255); // s==0, d>0 → 255
      expect(PsdBlendModes.divide(0, 0), 0); // s==0, d==0 → 0
      expect(PsdBlendModes.divide(255, 0), 0);
      expect(PsdBlendModes.divide(255, 255), 255);
    });

    test('exclusion', () {
      // s + d - 2*s*d/255
      expect(PsdBlendModes.exclusion(0, 0), 0);
      expect(PsdBlendModes.exclusion(255, 255), 0); // 255+255-2*255 = 0 (approx)
      expect(PsdBlendModes.exclusion(255, 0), 255);
      expect(PsdBlendModes.exclusion(0, 255), 255);
      expect(PsdBlendModes.exclusion(128, 128), closeTo(128, 1)); // 128+128-128 ≈ 128
    });

    test('linearBurn', () {
      // max(0, s + d - 255)
      expect(PsdBlendModes.linearBurn(200, 200), 145);
      expect(PsdBlendModes.linearBurn(100, 100), 0);
      expect(PsdBlendModes.linearBurn(255, 255), 255);
      expect(PsdBlendModes.linearBurn(0, 0), 0);
    });

    test('vividLight', () {
      // s < 128: colorBurn(2*s, d), s >= 128: colorDodge(2*s-255, d)
      // s=64 → colorBurn(128, 128) ≈ 2
      expect(PsdBlendModes.vividLight(64, 128), closeTo(2, 1));
      // s=192 → colorDodge(129, 128) ≈ min(255, 128*255/126) = 255
      expect(PsdBlendModes.vividLight(192, 128), 255);
      // Edge cases
      expect(PsdBlendModes.vividLight(0, 128), 0); // colorBurn(0, 128) = 0
      expect(PsdBlendModes.vividLight(255, 128), 255); // colorDodge(255, 128) = 255
    });

    test('linearLight', () {
      // clamp(d + 2*s - 255)
      expect(PsdBlendModes.linearLight(128, 128), closeTo(129, 1));
      expect(PsdBlendModes.linearLight(0, 0), 0); // 0+0-255 → clamped to 0
      expect(PsdBlendModes.linearLight(255, 255), 255); // clamped
      expect(PsdBlendModes.linearLight(64, 128), 1); // 128+128-255 = 1
    });

    test('pinLight', () {
      // s < 128: min(d, 2*s), s >= 128: max(d, 2*s-255)
      expect(PsdBlendModes.pinLight(32, 200), 64); // min(200, 64)
      expect(PsdBlendModes.pinLight(200, 50), 145); // max(50, 145)
      expect(PsdBlendModes.pinLight(128, 128), 128); // max(128, 1) = 128
    });

    test('hardMix', () {
      // VividLight-based threshold: vividLight(s,d) >= 128 → 255, else 0
      // vL(255,0)=cD(255,0)=0 → 0
      expect(PsdBlendModes.hardMix(255, 0), 0);
      expect(PsdBlendModes.hardMix(0, 0), 0);
      expect(PsdBlendModes.hardMix(255, 255), 255);
      // vL(0,255)=cB(0,255)=255 → 255
      expect(PsdBlendModes.hardMix(0, 255), 255);
      // vL(128,128)=cD(1,128)=128 → 255
      expect(PsdBlendModes.hardMix(128, 128), 255);
      // vL(128,127)=cD(1,127)=127 → 0
      expect(PsdBlendModes.hardMix(128, 127), 0);
    });

    // ── Per-pixel modes ──

    test('darkerColor picks pixel with lower luminance', () {
      // Red (255,0,0) lum ≈ 76, Blue (0,0,255) lum ≈ 29
      final (r, g, b) = PsdBlendModes.darkerColor(255, 0, 0, 0, 0, 255);
      expect((r, g, b), (0, 0, 255)); // blue is darker
    });

    test('lighterColor picks pixel with higher luminance', () {
      // Red (255,0,0) lum ≈ 76, Blue (0,0,255) lum ≈ 29
      final (r, g, b) = PsdBlendModes.lighterColor(255, 0, 0, 0, 0, 255);
      expect((r, g, b), (255, 0, 0)); // red is lighter
    });

    test('hue: keeps dst luminosity and saturation, uses src hue', () {
      // src = red (255,0,0), dst = green (0,255,0)
      final (r, g, b) = PsdBlendModes.hue(255, 0, 0, 0, 255, 0);
      // Result should have green's luminosity (150) and saturation (255)
      // but red's hue (R dominant)
      expect(r, greaterThan(g));
      expect(b, lessThanOrEqualTo(g));
    });

    test('saturation: keeps dst luminosity and hue, uses src saturation', () {
      // src = gray (128,128,128) sat=0, dst = red (255,0,0)
      final (r, g, b) = PsdBlendModes.saturation(128, 128, 128, 255, 0, 0);
      // With 0 saturation from src, result should be neutral gray
      // at dst's luminosity (≈76)
      expect(r, closeTo(g, 1));
      expect(g, closeTo(b, 1));
    });

    test('color: keeps dst luminosity, uses src hue+saturation', () {
      // SetLum(src, Lum(dst))
      final (r, g, b) = PsdBlendModes.color(255, 0, 0, 0, 255, 0);
      // Green's luminosity is 150, red hue → result has lum≈150 with red tint
      expect(r, greaterThan(g));
    });

    test('luminosity: keeps dst hue+saturation, uses src luminosity', () {
      // SetLum(dst, Lum(src))
      final (r, g, b) = PsdBlendModes.luminosity(128, 128, 128, 255, 0, 0);
      // src gray lum=128, dst red hue → result has lum≈128 with red tint
      expect(r, greaterThan(g));
      expect(r, greaterThan(b));
    });

    // ── Map and resolve tests ──

    test('resolve returns correct function', () {
      expect(PsdBlendModes.resolve('Multiply'), PsdBlendModes.multiply);
      expect(PsdBlendModes.resolve('Screen'), PsdBlendModes.screen);
    });

    test('resolve defaults to normal for unknown mode', () {
      expect(PsdBlendModes.resolve('Unknown'), PsdBlendModes.normal);
      expect(PsdBlendModes.resolve(''), PsdBlendModes.normal);
    });

    test('functions map contains all 20 per-channel modes', () {
      expect(PsdBlendModes.functions.length, 20);
      for (final mode in [
        'Normal', 'Multiply', 'Screen', 'Overlay', 'Darken', 'Lighten',
        'ColorDodge', 'ColorBurn', 'HardLight', 'SoftLight', 'Difference',
        'Subtract', 'LinearDodge', 'Divide', 'Exclusion', 'LinearBurn',
        'VividLight', 'LinearLight', 'PinLight', 'HardMix',
      ]) {
        expect(PsdBlendModes.functions.containsKey(mode), true,
            reason: 'Missing per-channel mode: $mode');
      }
    });

    test('pixelFunctions map contains all 6 per-pixel modes', () {
      expect(PsdBlendModes.pixelFunctions.length, 6);
      for (final mode in [
        'DarkerColor', 'LighterColor', 'Hue', 'Saturation', 'Color',
        'Luminosity',
      ]) {
        expect(PsdBlendModes.pixelFunctions.containsKey(mode), true,
            reason: 'Missing per-pixel mode: $mode');
      }
    });

    test('resolveComposite wraps per-channel into per-pixel', () {
      final fn = PsdBlendModes.resolveComposite('Multiply')!;
      final (r, g, b) = fn(128, 64, 255, 255, 128, 0);
      // multiply(128,255)≈128, multiply(64,128)≈32, multiply(255,0)=0
      expect(r, closeTo(128, 1));
      expect(g, closeTo(32, 1));
      expect(b, 0);
    });

    test('resolveComposite returns pixel fn for HSL modes', () {
      final fn = PsdBlendModes.resolveComposite('Hue');
      expect(fn, isNotNull);
    });

    test('resolveComposite returns null for Dissolve', () {
      expect(PsdBlendModes.resolveComposite('Dissolve'), isNull);
    });
  });
}

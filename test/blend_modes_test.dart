import 'package:flutter_test/flutter_test.dart';
import 'package:dart_psd_tool/dart_psd_tool.dart';

void main() {
  group('PsdBlendModes', () {
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

    test('resolve returns correct function', () {
      expect(PsdBlendModes.resolve('Multiply'), PsdBlendModes.multiply);
      expect(PsdBlendModes.resolve('Screen'), PsdBlendModes.screen);
    });

    test('resolve defaults to normal for unknown mode', () {
      expect(PsdBlendModes.resolve('Unknown'), PsdBlendModes.normal);
      expect(PsdBlendModes.resolve(''), PsdBlendModes.normal);
    });

    test('functions map contains all 13 modes', () {
      expect(PsdBlendModes.functions.length, 13);
      expect(PsdBlendModes.functions.containsKey('Normal'), true);
      expect(PsdBlendModes.functions.containsKey('Multiply'), true);
      expect(PsdBlendModes.functions.containsKey('Screen'), true);
      expect(PsdBlendModes.functions.containsKey('Overlay'), true);
      expect(PsdBlendModes.functions.containsKey('Darken'), true);
      expect(PsdBlendModes.functions.containsKey('Lighten'), true);
      expect(PsdBlendModes.functions.containsKey('ColorDodge'), true);
      expect(PsdBlendModes.functions.containsKey('ColorBurn'), true);
      expect(PsdBlendModes.functions.containsKey('HardLight'), true);
      expect(PsdBlendModes.functions.containsKey('SoftLight'), true);
      expect(PsdBlendModes.functions.containsKey('Difference'), true);
      expect(PsdBlendModes.functions.containsKey('Subtract'), true);
      expect(PsdBlendModes.functions.containsKey('LinearDodge'), true);
    });
  });
}

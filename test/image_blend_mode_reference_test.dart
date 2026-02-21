import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:dart_psd_tool/dart_psd_tool.dart';

import 'test_utils.dart';

/// Mapping of Dart `image` package BlendMode to PSD blend mode name.
const Map<img.BlendMode, String> _imageBlendModeMapping = {
  img.BlendMode.alpha: 'Normal',
  img.BlendMode.multiply: 'Multiply',
  img.BlendMode.screen: 'Screen',
  img.BlendMode.overlay: 'Overlay',
  img.BlendMode.darken: 'Darken',
  img.BlendMode.lighten: 'Lighten',
  img.BlendMode.hardLight: 'HardLight',
  img.BlendMode.softLight: 'SoftLight',
  img.BlendMode.dodge: 'ColorDodge',
  img.BlendMode.burn: 'ColorBurn',
  img.BlendMode.difference: 'Difference',
  img.BlendMode.subtract: 'Subtract',
  img.BlendMode.divide: 'Divide',
  img.BlendMode.addition: 'LinearDodge',
};

/// All 27 PSD blend modes to test with our PsdCompositor.
/// (Dissolve excluded — it's non-deterministic vs psd-tools' random)
const List<String> _allPsdModes = [
  'Normal',
  'Darken', 'Multiply', 'ColorBurn', 'LinearBurn', 'DarkerColor',
  'Lighten', 'Screen', 'ColorDodge', 'LinearDodge', 'LighterColor',
  'Overlay', 'SoftLight', 'HardLight', 'VividLight', 'LinearLight',
  'PinLight', 'HardMix',
  'Difference', 'Exclusion', 'Subtract', 'Divide',
  'Hue', 'Saturation', 'Color', 'Luminosity',
];

const List<String> _overlays = ['circle', 'color', 'alpha'];

/// RMSE thresholds for pass/warn/fail classification.
const double _thresholdPass = 2.0;
const double _thresholdWarn = 5.0;

void main() {
  final fixtureDir = Directory('test/fixtures/blend-mode-test');
  final psdDir = Directory('${fixtureDir.path}/psd');
  final resultsDir = Directory('${fixtureDir.path}/results');

  // Skip all tests if fixtures are not downloaded
  if (!fixtureDir.existsSync()) {
    test('fixtures not present — run tool/download_fixtures.sh', () {
      // ignore: avoid_print
      print('SKIP: Blend mode fixtures not found at ${fixtureDir.path}');
      print('Run: bash tool/download_fixtures.sh');
    }, skip: 'Fixtures not downloaded. Run: bash tool/download_fixtures.sh');
    return;
  }

  late img.Image baseImage;

  setUpAll(() {
    final baseFile = File('${psdDir.path}/_base.png');
    expect(baseFile.existsSync(), isTrue,
        reason: 'Missing _base.png in fixtures');
    baseImage = img.decodePng(baseFile.readAsBytesSync())!;
  });

  // Sanity check: reference images should not all be identical
  test('sanity: references are not all identical to base', () {
    final normalRef = File('${resultsDir.path}/Normal_circle.png');
    final multiplyRef = File('${resultsDir.path}/Multiply_color.png');
    if (!normalRef.existsSync() || !multiplyRef.existsSync()) {
      fail('Missing reference files for sanity check');
    }

    final normalImg = img.decodePng(normalRef.readAsBytesSync())!;
    final multiplyImg = img.decodePng(multiplyRef.readAsBytesSync())!;

    final rmseNormal = computeRmse(baseImage, normalImg);
    final rmseMultiply = computeRmse(baseImage, multiplyImg);

    expect(rmseNormal > 1.0 || rmseMultiply > 1.0, isTrue,
        reason: 'All references appear identical to base — '
            'regenerate with tool/run_blend_tests.py');
  });

  // ── Test 1: image package blend modes vs psd-tools ──

  group('image package vs psd-tools', () {
    for (final entry in _imageBlendModeMapping.entries) {
      final blendMode = entry.key;
      final psdName = entry.value;

      for (final overlay in _overlays) {
        test('$psdName × $overlay', () {
          final overlayFile = File('${psdDir.path}/_overlay_$overlay.png');
          final overlayImage = img.decodePng(overlayFile.readAsBytesSync())!;

          final refFile = File('${resultsDir.path}/${psdName}_$overlay.png');
          expect(refFile.existsSync(), isTrue,
              reason: 'Missing reference: ${psdName}_$overlay.png');
          final refImage = img.decodePng(refFile.readAsBytesSync())!;

          final dst = baseImage.clone();
          img.compositeImage(dst, overlayImage, blend: blendMode);

          final rmse = computeRmse(dst, refImage);
          final status =
              rmse < _thresholdPass ? 'PASS' : rmse < _thresholdWarn ? 'WARN' : 'FAIL';
          // ignore: avoid_print
          print('  $status  $psdName × $overlay  RMSE=${rmse.toStringAsFixed(2)}');

          if (rmse >= _thresholdWarn) {
            fail('$psdName × $overlay: RMSE ${rmse.toStringAsFixed(2)} '
                'exceeds threshold $_thresholdWarn — '
                'custom implementation needed');
          }
        });
      }
    }
  });

  // ── Test 2: PsdCompositor vs psd-tools (our implementation) ──

  group('PsdCompositor vs psd-tools', () {
    for (final psdName in _allPsdModes) {
      for (final overlay in _overlays) {
        test('$psdName × $overlay', () {
          final overlayFile = File('${psdDir.path}/_overlay_$overlay.png');
          final overlayImage = img.decodePng(overlayFile.readAsBytesSync())!;

          final refFile = File('${resultsDir.path}/${psdName}_$overlay.png');
          expect(refFile.existsSync(), isTrue,
              reason: 'Missing reference: ${psdName}_$overlay.png');
          final refImage = img.decodePng(refFile.readAsBytesSync())!;

          // Composite using our PsdCompositor
          final dst = baseImage.clone();
          PsdCompositor.composite(dst, overlayImage, blendMode: psdName);

          final rmse = computeRmse(dst, refImage);
          final status =
              rmse < _thresholdPass ? 'PASS' : rmse < _thresholdWarn ? 'WARN' : 'FAIL';
          // ignore: avoid_print
          print('  $status  $psdName × $overlay  RMSE=${rmse.toStringAsFixed(2)}');

          if (rmse >= _thresholdWarn) {
            fail('$psdName × $overlay: RMSE ${rmse.toStringAsFixed(2)} '
                'exceeds threshold $_thresholdWarn');
          }
        });
      }
    }
  });
}

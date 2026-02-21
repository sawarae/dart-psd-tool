import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:dart_psd_tool/dart_psd_tool.dart';

import 'test_utils.dart';

/// All 26 PSD blend modes (Dissolve excluded).
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

/// RMSE thresholds.
const double _thresholdShaderVsRef = 5.0;
const double _thresholdShaderVsCpu = 3.0;

/// HardMix uses step() thresholding on VividLight, so tiny float precision
/// differences produce 0-or-255 output swings. Allow a wider tolerance.
const double _thresholdHardMixVsRef = 5.0;
const double _thresholdHardMixVsCpu = 6.0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixtureDir = Directory('test/fixtures/blend-mode-test');
  final psdDir = Directory('${fixtureDir.path}/psd');
  final resultsDir = Directory('${fixtureDir.path}/results');

  if (!fixtureDir.existsSync()) {
    test('fixtures not present — run tool/download_fixtures.sh', () {
      // ignore: avoid_print
      print('SKIP: Blend mode fixtures not found at ${fixtureDir.path}');
    }, skip: 'Fixtures not downloaded. Run: bash tool/download_fixtures.sh');
    return;
  }

  late img.Image baseImage;
  late PsdCanvasCompositor compositor;

  setUpAll(() async {
    final baseFile = File('${psdDir.path}/_base.png');
    expect(baseFile.existsSync(), isTrue, reason: 'Missing _base.png');
    baseImage = img.decodePng(baseFile.readAsBytesSync())!;
    compositor = await PsdCanvasCompositor.create();
  });

  // ── Shader vs psd-tools reference ──

  group('Shader vs psd-tools', () {
    for (final psdName in _allPsdModes) {
      for (final overlay in _overlays) {
        test('$psdName × $overlay', () async {
          final overlayFile = File('${psdDir.path}/_overlay_$overlay.png');
          final overlayImage = img.decodePng(overlayFile.readAsBytesSync())!;

          final refFile = File('${resultsDir.path}/${psdName}_$overlay.png');
          expect(refFile.existsSync(), isTrue,
              reason: 'Missing reference: ${psdName}_$overlay.png');
          final refImage = img.decodePng(refFile.readAsBytesSync())!;

          final shaderResult = await renderShaderComposite(
            compositor,
            overlayImage,
            baseImage,
            baseImage.width,
            baseImage.height,
            psdName,
          );

          final rmse = computeRmse(shaderResult, refImage);
          final threshold = psdName == 'HardMix' ? _thresholdHardMixVsRef : _thresholdShaderVsRef;
          final status = rmse < 2.0 ? 'PASS' : rmse < threshold ? 'WARN' : 'FAIL';
          // ignore: avoid_print
          print('  $status  Shader vs ref: $psdName × $overlay  RMSE=${rmse.toStringAsFixed(2)}');

          expect(rmse, lessThan(threshold),
              reason: '$psdName × $overlay: Shader vs psd-tools RMSE '
                  '${rmse.toStringAsFixed(2)} exceeds $threshold');
        });
      }
    }
  });

  // ── Shader vs CPU (PsdCompositor) ──

  group('Shader vs CPU', () {
    for (final psdName in _allPsdModes) {
      for (final overlay in _overlays) {
        test('$psdName × $overlay', () async {
          final overlayFile = File('${psdDir.path}/_overlay_$overlay.png');
          final overlayImage = img.decodePng(overlayFile.readAsBytesSync())!;

          // CPU reference
          final cpuDst = baseImage.clone();
          PsdCompositor.composite(cpuDst, overlayImage, blendMode: psdName);

          // Shader result
          final shaderResult = await renderShaderComposite(
            compositor,
            overlayImage,
            baseImage,
            baseImage.width,
            baseImage.height,
            psdName,
          );

          final rmse = computeRmse(shaderResult, cpuDst);
          final threshold = psdName == 'HardMix' ? _thresholdHardMixVsCpu : _thresholdShaderVsCpu;
          final status = rmse < 1.0 ? 'PASS' : rmse < threshold ? 'WARN' : 'FAIL';
          // ignore: avoid_print
          print('  $status  Shader vs CPU: $psdName × $overlay  RMSE=${rmse.toStringAsFixed(2)}');

          expect(rmse, lessThan(threshold),
              reason: '$psdName × $overlay: Shader vs CPU RMSE '
                  '${rmse.toStringAsFixed(2)} exceeds $threshold');
        });
      }
    }
  });
}

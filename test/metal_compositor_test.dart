import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:dart_psd_tool/dart_psd_tool.dart';

/// Mock Metal MethodChannel handler that simulates Metal compositing
/// using the CPU compositor for verification in unit tests.
///
/// This allows testing the Dart-side API, serialization, and blend mode
/// mapping without requiring actual Metal hardware.
class MockMetalHandler {
  bool _initialized = false;

  Future<dynamic> handle(MethodCall call) async {
    switch (call.method) {
      case 'isAvailable':
        return true;
      case 'initialize':
        _initialized = true;
        return true;
      case 'composite':
        if (!_initialized) {
          throw PlatformException(code: 'NOT_INITIALIZED');
        }
        final args = call.arguments as Map<dynamic, dynamic>;
        final srcBytes = args['src'] as Uint8List;
        final dstBytes = args['dst'] as Uint8List;
        final width = args['width'] as int;
        final height = args['height'] as int;
        final blendModeIndex = args['blendMode'] as int;
        final opacity = args['opacity'] as double;

        // Reverse map blend mode index to name
        final blendModeName = _blendModeNames[blendModeIndex] ?? 'Normal';

        // Reconstruct images from bytes
        final src = _bytesToImage(srcBytes, width, height);
        final dst = _bytesToImage(dstBytes, width, height);

        // Use CPU compositor for the actual blending
        PsdCompositor.composite(dst, src,
            blendMode: blendModeName, opacity: opacity);

        // Return result as RGBA bytes
        return _imageToBytes(dst);
      case 'dispose':
        _initialized = false;
        return null;
      default:
        throw MissingPluginException();
    }
  }

  static img.Image _bytesToImage(Uint8List bytes, int width, int height) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        image.setPixelRgba(x, y, bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
      }
    }
    return image;
  }

  static Uint8List _imageToBytes(img.Image image) {
    final bytes = Uint8List(image.width * image.height * 4);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final i = (y * image.width + x) * 4;
        bytes[i] = p.r.toInt();
        bytes[i + 1] = p.g.toInt();
        bytes[i + 2] = p.b.toInt();
        bytes[i + 3] = p.a.toInt();
      }
    }
    return bytes;
  }

  static const _blendModeNames = <int, String>{
    0: 'Normal',
    1: 'Multiply',
    2: 'Screen',
    3: 'Overlay',
    4: 'Darken',
    5: 'Lighten',
    6: 'ColorDodge',
    7: 'ColorBurn',
    8: 'HardLight',
    9: 'SoftLight',
    10: 'Difference',
    11: 'Subtract',
    12: 'LinearDodge',
    13: 'Divide',
    14: 'Exclusion',
    15: 'LinearBurn',
    16: 'VividLight',
    17: 'LinearLight',
    18: 'PinLight',
    19: 'HardMix',
    20: 'DarkerColor',
    21: 'LighterColor',
    22: 'Hue',
    23: 'Saturation',
    24: 'Color',
    25: 'Luminosity',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMetalHandler mockHandler;

  setUp(() {
    mockHandler = MockMetalHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dart_psd_tool/metal'),
      mockHandler.handle,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dart_psd_tool/metal'),
      null,
    );
  });

  group('PsdMetalCompositor', () {
    test('isAvailable returns true with mock', () async {
      expect(await PsdMetalCompositor.isAvailable, isTrue);
    });

    test('create initializes successfully', () async {
      final compositor = await PsdMetalCompositor.create();
      await compositor.dispose();
    });

    test('composite normal blend - opaque over transparent', () async {
      final compositor = await PsdMetalCompositor.create();

      final src = img.Image(width: 4, height: 4, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255));
      final dst = img.Image(width: 4, height: 4, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));

      final result = await compositor.composite(src, dst);

      final p = result.getPixel(0, 0);
      expect(p.r.toInt(), 255);
      expect(p.g.toInt(), 0);
      expect(p.b.toInt(), 0);
      expect(p.a.toInt(), 255);

      await compositor.dispose();
    });

    test('composite multiply blend mode', () async {
      final compositor = await PsdMetalCompositor.create();

      final src = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(128, 64, 32, 255));
      final dst = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(255, 255, 255, 255));

      final result =
          await compositor.composite(src, dst, blendMode: 'Multiply');

      final p = result.getPixel(0, 0);
      expect(p.r.toInt(), closeTo(128, 1));
      expect(p.g.toInt(), closeTo(64, 1));
      expect(p.b.toInt(), closeTo(32, 1));

      await compositor.dispose();
    });

    test('composite screen blend mode', () async {
      final compositor = await PsdMetalCompositor.create();

      final src = img.Image(width: 1, height: 1, numChannels: 4);
      src.setPixelRgba(0, 0, 128, 128, 128, 255);
      final dst = img.Image(width: 1, height: 1, numChannels: 4);
      dst.setPixelRgba(0, 0, 128, 128, 128, 255);

      final result = await compositor.composite(src, dst, blendMode: 'Screen');

      final p = result.getPixel(0, 0);
      expect(p.r.toInt(), closeTo(192, 1));

      await compositor.dispose();
    });

    test('compositeInPlace modifies destination', () async {
      final compositor = await PsdMetalCompositor.create();

      final dst = img.Image(width: 4, height: 4, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));
      final src = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255));

      await compositor.compositeInPlace(dst, src, offsetX: 1, offsetY: 1);

      // Source pixel should be composited at offset
      final p = dst.getPixel(1, 1);
      expect(p.r.toInt(), 255);
      expect(p.a.toInt(), 255);

      // Outside source area should remain transparent
      expect(dst.getPixel(0, 0).a.toInt(), 0);

      await compositor.dispose();
    });

    test('renderLayerTree renders visible layers', () async {
      final compositor = await PsdMetalCompositor.create();

      final redPng = img.encodePng(
        img.Image(width: 2, height: 2, numChannels: 4)
          ..clear(img.ColorRgba8(255, 0, 0, 255)),
      );

      final layers = [
        PsdLayerNode(
          name: 'red',
          isGroup: false,
          isDefault: false,
          isVariant: false,
          psdVisible: true,
          left: 0,
          top: 0,
          right: 2,
          bottom: 2,
          pngBytes: redPng,
        ),
      ];

      final result = await compositor.renderLayerTree(layers, 4, 4);
      expect(result.width, 4);
      expect(result.height, 4);

      final p = result.getPixel(0, 0);
      expect(p.r.toInt(), 255);
      expect(p.a.toInt(), 255);

      expect(result.getPixel(3, 3).a.toInt(), 0);

      await compositor.dispose();
    });

    test('renderLayerTree skips invisible layers', () async {
      final compositor = await PsdMetalCompositor.create();

      final redPng = img.encodePng(
        img.Image(width: 2, height: 2, numChannels: 4)
          ..clear(img.ColorRgba8(255, 0, 0, 255)),
      );

      final layers = [
        PsdLayerNode(
          name: 'hidden',
          isGroup: false,
          isDefault: false,
          isVariant: false,
          psdVisible: false,
          left: 0,
          top: 0,
          right: 2,
          bottom: 2,
          pngBytes: redPng,
        ),
      ];

      final result = await compositor.renderLayerTree(layers, 4, 4);
      expect(result.getPixel(0, 0).a.toInt(), 0);

      await compositor.dispose();
    });

    test('dispose prevents further operations', () async {
      final compositor = await PsdMetalCompositor.create();
      await compositor.dispose();

      final src = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255));
      final dst = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));

      expect(
        () => compositor.composite(src, dst),
        throwsStateError,
      );
    });

    test('all blend modes are mapped', () async {
      // Verify all 26 blend modes have valid index mappings
      const allModes = [
        'Normal', 'Multiply', 'Screen', 'Overlay',
        'Darken', 'Lighten', 'ColorDodge', 'ColorBurn',
        'HardLight', 'SoftLight', 'Difference', 'Subtract',
        'LinearDodge', 'Divide', 'Exclusion', 'LinearBurn',
        'VividLight', 'LinearLight', 'PinLight', 'HardMix',
        'DarkerColor', 'LighterColor',
        'Hue', 'Saturation', 'Color', 'Luminosity',
      ];

      final compositor = await PsdMetalCompositor.create();

      final src = img.Image(width: 1, height: 1, numChannels: 4);
      src.setPixelRgba(0, 0, 128, 64, 32, 200);
      final dst = img.Image(width: 1, height: 1, numChannels: 4);
      dst.setPixelRgba(0, 0, 200, 100, 50, 255);

      for (final mode in allModes) {
        // Should not throw for any supported blend mode
        final result = await compositor.composite(src, dst, blendMode: mode);
        expect(result.width, 1, reason: '$mode should produce valid output');
      }

      await compositor.dispose();
    });
  });
}

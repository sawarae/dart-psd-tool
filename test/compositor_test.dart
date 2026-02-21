import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:dart_psd_tool/dart_psd_tool.dart';

void main() {
  group('PsdCompositor', () {
    test('composite normal blend mode - opaque over transparent', () {
      final dst = img.Image(width: 4, height: 4, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));
      final src = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255));

      PsdCompositor.composite(dst, src, offsetX: 1, offsetY: 1);

      // Source pixel should be copied over
      final p = dst.getPixel(1, 1);
      expect(p.r.toInt(), 255);
      expect(p.g.toInt(), 0);
      expect(p.b.toInt(), 0);
      expect(p.a.toInt(), 255);

      // Outside source area should remain transparent
      final p0 = dst.getPixel(0, 0);
      expect(p0.a.toInt(), 0);
    });

    test('composite with opacity', () {
      final dst = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));
      final src = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255));

      PsdCompositor.composite(dst, src, opacity: 0.5);

      final p = dst.getPixel(0, 0);
      // With opacity 0.5 over transparent: alpha ≈ 128, RGB = source
      expect(p.a.toInt(), closeTo(128, 2));
      expect(p.r.toInt(), closeTo(255, 2));
    });

    test('composite multiply blend mode', () {
      // White * color = color (no change)
      final dst = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(255, 255, 255, 255));
      final src = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(128, 64, 32, 255));

      PsdCompositor.composite(dst, src, blendMode: 'Multiply');

      final p = dst.getPixel(0, 0);
      // multiply(128, 255) = 128, multiply(64, 255) = 64, multiply(32, 255) = 32
      expect(p.r.toInt(), closeTo(128, 1));
      expect(p.g.toInt(), closeTo(64, 1));
      expect(p.b.toInt(), closeTo(32, 1));
    });

    test('composite respects offset bounds', () {
      final dst = img.Image(width: 4, height: 4, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));
      final src = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255));

      // Offset partially off-canvas
      PsdCompositor.composite(dst, src, offsetX: 3, offsetY: 3);

      // Only (3,3) should be affected
      final p = dst.getPixel(3, 3);
      expect(p.r.toInt(), 255);
      expect(p.a.toInt(), 255);

      // (3,2) and (2,3) should still be transparent
      expect(dst.getPixel(2, 3).a.toInt(), 0);
      expect(dst.getPixel(3, 2).a.toInt(), 0);
    });

    test('composite skips fully transparent source pixels', () {
      final dst = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(100, 100, 100, 255));
      final src = img.Image(width: 2, height: 2, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));

      PsdCompositor.composite(dst, src);

      // Destination should be unchanged
      final p = dst.getPixel(0, 0);
      expect(p.r.toInt(), 100);
      expect(p.g.toInt(), 100);
      expect(p.b.toInt(), 100);
      expect(p.a.toInt(), 255);
    });

    test('composite screen blend mode', () {
      final dst = img.Image(width: 1, height: 1, numChannels: 4);
      dst.setPixelRgba(0, 0, 128, 128, 128, 255);
      final src = img.Image(width: 1, height: 1, numChannels: 4);
      src.setPixelRgba(0, 0, 128, 128, 128, 255);

      PsdCompositor.composite(dst, src, blendMode: 'Screen');

      final p = dst.getPixel(0, 0);
      // screen(128, 128) = 128 + 128 - 128*128/255 ≈ 192
      expect(p.r.toInt(), closeTo(192, 1));
    });
  });

  group('PsdCompositor.renderLayerTree', () {
    test('renders visible leaf layers', () {
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

      final result = PsdCompositor.renderLayerTree(layers, 4, 4);
      expect(result.width, 4);
      expect(result.height, 4);

      final p = result.getPixel(0, 0);
      expect(p.r.toInt(), 255);
      expect(p.a.toInt(), 255);

      // Outside layer bounds should be transparent
      expect(result.getPixel(3, 3).a.toInt(), 0);
    });

    test('skips invisible layers', () {
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

      final result = PsdCompositor.renderLayerTree(layers, 4, 4);
      expect(result.getPixel(0, 0).a.toInt(), 0);
    });

    test('custom visibilityFilter overrides psdVisible', () {
      final redPng = img.encodePng(
        img.Image(width: 2, height: 2, numChannels: 4)
          ..clear(img.ColorRgba8(255, 0, 0, 255)),
      );

      final layers = [
        PsdLayerNode(
          name: 'hidden-by-psd',
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

      // Force all layers visible
      final result = PsdCompositor.renderLayerTree(
        layers, 4, 4,
        visibilityFilter: (_) => true,
      );
      expect(result.getPixel(0, 0).r.toInt(), 255);
    });
  });
}

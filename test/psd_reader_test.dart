import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_psd_tool/dart_psd_tool.dart';

void main() {
  group('PsdLayerNode', () {
    test('baseName strips ! prefix', () {
      final node = PsdLayerNode(
        name: '!background',
        isGroup: false,
        isDefault: true,
        isVariant: false,
        left: 0, top: 0, right: 100, bottom: 100,
      );
      expect(node.baseName, 'background');
    });

    test('baseName strips * prefix', () {
      final node = PsdLayerNode(
        name: '*variant1',
        isGroup: false,
        isDefault: false,
        isVariant: true,
        left: 0, top: 0, right: 100, bottom: 100,
      );
      expect(node.baseName, 'variant1');
    });

    test('baseName returns name when no prefix', () {
      final node = PsdLayerNode(
        name: 'layer',
        isGroup: false,
        isDefault: false,
        isVariant: false,
        left: 0, top: 0, right: 100, bottom: 100,
      );
      expect(node.baseName, 'layer');
    });

    test('width and height computed from bounds', () {
      final node = PsdLayerNode(
        name: 'test',
        isGroup: false,
        isDefault: false,
        isVariant: false,
        left: 10, top: 20, right: 110, bottom: 220,
      );
      expect(node.width, 100);
      expect(node.height, 200);
    });

    test('children defaults to empty list', () {
      final node = PsdLayerNode(
        name: 'test',
        isGroup: true,
        isDefault: false,
        isVariant: false,
        left: 0, top: 0, right: 0, bottom: 0,
      );
      expect(node.children, isEmpty);
    });

    test('toString', () {
      final node = PsdLayerNode(
        name: 'test',
        isGroup: true,
        isDefault: false,
        isVariant: false,
        left: 0, top: 0, right: 0, bottom: 0,
      );
      expect(node.toString(), 'PsdLayerNode(test, group=true, children=0)');
    });
  });

  group('Utf16Decoder', () {
    test('decodes ASCII as UTF-16BE', () {
      final decoder = const Utf16Decoder();
      // 'AB' in UTF-16BE
      final bytes = Uint8List.fromList([0x00, 0x41, 0x00, 0x42]);
      expect(decoder.decodeUtf16Be(bytes), 'AB');
    });

    test('decodes Japanese characters', () {
      final decoder = const Utf16Decoder();
      // 'あ' U+3042 = 0x30 0x42
      final bytes = Uint8List.fromList([0x30, 0x42]);
      expect(decoder.decodeUtf16Be(bytes), 'あ');
    });
  });

  group('PsdReader', () {
    test('fromBytes returns null for invalid data', () {
      final result = PsdReader.fromBytes(Uint8List.fromList([0, 0, 0, 0]));
      expect(result, isNull);
    });

    test('fromBytes returns null for empty data', () {
      final result = PsdReader.fromBytes(Uint8List(0));
      expect(result, isNull);
    });
  });
}

import 'dart:typed_data';
import 'package:image/image.dart' as img;

import 'psd_layer_node.dart';

/// Reads a PSD file and returns a layer tree using the image package.
///
/// Layer names are read from the `luni` additional data block (UTF-16BE),
/// which is the Unicode name stored by Photoshop for Japanese and other
/// non-ASCII layer names. Falls back to the Pascal string name if absent.
///
/// PSD naming convention (psdtools style):
/// - `!` prefix = default display layer (always visible, background)
/// - `*` prefix = variant layer (controlled by parameter)
/// - No prefix = normal layer
class PsdReader {
  final img.PsdImage _psdImage;
  final int _canvasWidth;
  final int _canvasHeight;

  PsdReader._(this._psdImage, this._canvasWidth, this._canvasHeight);

  /// Parse a PSD file and return a [PsdReader] for accessing layers.
  static PsdReader? fromBytes(Uint8List bytes) {
    try {
      final psd = img.PsdImage(bytes);
      if (!psd.isValid) return null;
      if (!psd.decode()) return null;
      return PsdReader._(psd, psd.width, psd.height);
    } catch (_) {
      return null;
    }
  }

  int get canvasWidth => _canvasWidth;
  int get canvasHeight => _canvasHeight;

  /// Read the proper Unicode layer name from the `luni` additional data block.
  ///
  /// PSD stores Pascal strings in system encoding (Shift-JIS for Japanese files).
  /// The `luni` block always contains the UTF-16BE name regardless of locale.
  ///
  /// `luni` data layout (after the length prefix):
  ///   uint32 BE — character count
  ///   [count × 2 bytes] — UTF-16BE encoded name
  static String _layerName(img.PsdLayer layer) {
    final luniData = layer.additionalData['luni'];
    if (luniData is img.PsdLayerAdditionalData) {
      try {
        final buf = img.InputBuffer.from(luniData.data);
        final charCount = buf.readUint32();
        if (charCount > 0 && charCount < 512) {
          final raw = buf.readBytes(charCount * 2).toUint8List();
          final codec = const Utf16Decoder();
          return codec.decodeUtf16Be(raw);
        }
      } catch (_) {
        // fall through to Pascal name
      }
    }
    return layer.name ?? '';
  }

  /// Build the layer tree from the flat PSD layer list.
  ///
  /// PSD layer order: layers are stored top-to-bottom visually.
  /// Groups: folder record (type 1/2) opens a group, sectionDivider (type 3) closes it.
  List<PsdLayerNode> buildLayerTree() {
    final layers = _psdImage.layers.reversed;
    final root = <PsdLayerNode>[];
    final stack = <List<PsdLayerNode>>[root];
    final effectiveVisStack = <bool>[true];

    for (final layer in layers) {
      final type = layer.type();
      final name = _layerName(layer);

      final parentVisible = effectiveVisStack.last;
      final ownVisible = layer.isVisible();

      if (type == img.PsdLayerSectionDivider.openFolder ||
          type == img.PsdLayerSectionDivider.closedFolder) {
        final isDefaultGroup = name.startsWith('!');
        final effectiveVisible =
            isDefaultGroup ? parentVisible : (parentVisible && ownVisible);
        final node = PsdLayerNode(
          name: name,
          isGroup: true,
          isDefault: isDefaultGroup,
          isVariant: name.startsWith('*'),
          psdVisible: effectiveVisible,
          left: layer.left ?? 0,
          top: layer.top ?? 0,
          right: layer.right,
          bottom: layer.bottom,
          blendMode: _psdBlendModeString(layer.blendMode),
        );
        stack.last.add(node);
        stack.add(node.children);
        effectiveVisStack.add(effectiveVisible);
      } else if (type == img.PsdLayerSectionDivider.sectionDivider) {
        if (stack.length > 1) {
          stack.removeLast();
          effectiveVisStack.removeLast();
        }
      } else {
        final isDefault = name.startsWith('!');
        final effectiveVisible =
            isDefault ? parentVisible : (parentVisible && ownVisible);
        Uint8List? pngBytes;
        if (layer.width > 0 && layer.height > 0) {
          pngBytes = _buildLayerPng(layer);
        }
        final node = PsdLayerNode(
          name: name,
          isGroup: false,
          isDefault: isDefault,
          isVariant: name.startsWith('*'),
          psdVisible: effectiveVisible,
          left: layer.left ?? 0,
          top: layer.top ?? 0,
          right: layer.right,
          bottom: layer.bottom,
          pngBytes: pngBytes,
          blendMode: _psdBlendModeString(layer.blendMode),
          isClipping: (layer.clipping ?? 0) == 1,
        );
        stack.last.add(node);
      }
    }

    return root;
  }

  /// Build a PNG from raw PSD channel data (straight alpha).
  static Uint8List? _buildLayerPng(img.PsdLayer layer) {
    final w = layer.width;
    final h = layer.height;
    if (w <= 0 || h <= 0) return null;

    Uint8List? alphaData, rData, gData, bData;
    for (final ch in layer.channels) {
      switch (ch.id) {
        case -1:
          alphaData = ch.data;
        case 0:
          rData = ch.data;
        case 1:
          gData = ch.data;
        case 2:
          bData = ch.data;
      }
    }
    if (rData == null || gData == null || bData == null) return null;

    final result = img.Image(width: w, height: h, numChannels: 4);
    final pixelCount = w * h;
    for (int i = 0; i < pixelCount; i++) {
      final r = rData[i];
      final g = gData[i];
      final b = bData[i];
      final a = alphaData != null && i < alphaData.length ? alphaData[i] : 255;
      result.setPixelRgba(i % w, i ~/ w, r, g, b, a);
    }

    return img.encodePng(result);
  }

  /// Map PSD blend mode int to standard blend mode string.
  ///
  /// Returns a string matching the 13 PSDTool blend modes supported by
  /// [PsdBlendModes]: Normal, Multiply, Screen, Overlay, Darken, Lighten,
  /// ColorDodge, ColorBurn, HardLight, SoftLight, Difference, Subtract,
  /// LinearDodge.
  static String _psdBlendModeString(int? psdMode) {
    switch (psdMode) {
      case img.PsdBlendMode.dissolve:
        return 'Dissolve';
      case img.PsdBlendMode.darken:
        return 'Darken';
      case img.PsdBlendMode.multiply:
        return 'Multiply';
      case img.PsdBlendMode.colorBurn:
        return 'ColorBurn';
      case img.PsdBlendMode.linearBurn:
        return 'LinearBurn';
      case img.PsdBlendMode.darkenColor:
        return 'DarkerColor';
      case img.PsdBlendMode.lighten:
        return 'Lighten';
      case img.PsdBlendMode.screen:
        return 'Screen';
      case img.PsdBlendMode.colorDodge:
        return 'ColorDodge';
      case img.PsdBlendMode.linearDodge:
        return 'LinearDodge';
      case img.PsdBlendMode.lighterColor:
        return 'LighterColor';
      case img.PsdBlendMode.overlay:
        return 'Overlay';
      case img.PsdBlendMode.softLight:
        return 'SoftLight';
      case img.PsdBlendMode.hardLight:
        return 'HardLight';
      case img.PsdBlendMode.vividLight:
        return 'VividLight';
      case img.PsdBlendMode.linearLight:
        return 'LinearLight';
      case img.PsdBlendMode.pinLight:
        return 'PinLight';
      case img.PsdBlendMode.hardMix:
        return 'HardMix';
      case img.PsdBlendMode.difference:
        return 'Difference';
      case img.PsdBlendMode.exclusion:
        return 'Exclusion';
      case img.PsdBlendMode.subtract:
        return 'Subtract';
      case img.PsdBlendMode.divide:
        return 'Divide';
      case img.PsdBlendMode.hue:
        return 'Hue';
      case img.PsdBlendMode.saturation:
        return 'Saturation';
      case img.PsdBlendMode.color:
        return 'Color';
      case img.PsdBlendMode.luminosity:
        return 'Luminosity';
      default:
        return 'Normal';
    }
  }

  /// Print the layer tree for debugging.
  static void printTree(List<PsdLayerNode> nodes, {int indent = 0}) {
    for (final node in nodes) {
      final prefix = '  ' * indent;
      final typeLabel = node.isGroup ? '[G]' : '[L]';
      // ignore: avoid_print
      print(
          '$prefix$typeLabel ${node.name} (${node.width}x${node.height} @ ${node.left},${node.top})');
      if (node.isGroup) {
        printTree(node.children, indent: indent + 1);
      }
    }
  }
}

/// Minimal UTF-16BE decoder for PSD layer names.
class Utf16Decoder {
  const Utf16Decoder();

  String decodeUtf16Be(Uint8List bytes) {
    final codeUnits = <int>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(codeUnits);
  }
}

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'psd_layer_node.dart';

/// PSDTool-compatible Metal GPU compositor.
///
/// Uses Apple Metal compute shaders on macOS and iOS to perform PSDTool's
/// 3-component alpha compositing on the GPU. Falls back gracefully when
/// Metal is not available (e.g. on Android, Web, or simulators without GPU).
///
/// All 26 PSD blend modes are supported with output matching the CPU
/// [PsdCompositor] and GLSL [PsdCanvasCompositor].
class PsdMetalCompositor {
  static const MethodChannel _channel = MethodChannel('dart_psd_tool/metal');

  bool _initialized = false;

  PsdMetalCompositor._();

  /// Check if Metal compositing is available on the current platform.
  ///
  /// Returns true on macOS and iOS devices with Metal support.
  /// Returns false on Android, Web, Linux, Windows, and simulators
  /// without GPU access.
  static Future<bool> get isAvailable async {
    if (!_isPlatformSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Whether the current platform could potentially support Metal.
  static bool get _isPlatformSupported {
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Create and initialize a Metal compositor.
  ///
  /// Throws [MetalNotAvailableException] if Metal is not supported on the
  /// current device. Use [isAvailable] to check before calling.
  static Future<PsdMetalCompositor> create() async {
    final compositor = PsdMetalCompositor._();
    try {
      await _channel.invokeMethod<bool>('initialize');
      compositor._initialized = true;
    } on PlatformException catch (e) {
      throw MetalNotAvailableException(e.message ?? 'Metal initialization failed');
    } on MissingPluginException {
      throw MetalNotAvailableException(
          'Metal plugin not registered. Ensure the plugin is included in your app.');
    }
    return compositor;
  }

  /// Blend mode name to shader index mapping.
  static const _blendModeIndex = <String, int>{
    'Normal': 0,
    'Multiply': 1,
    'Screen': 2,
    'Overlay': 3,
    'Darken': 4,
    'Lighten': 5,
    'ColorDodge': 6,
    'ColorBurn': 7,
    'HardLight': 8,
    'SoftLight': 9,
    'Difference': 10,
    'Subtract': 11,
    'LinearDodge': 12,
    'Divide': 13,
    'Exclusion': 14,
    'LinearBurn': 15,
    'VividLight': 16,
    'LinearLight': 17,
    'PinLight': 18,
    'HardMix': 19,
    'DarkerColor': 20,
    'LighterColor': 21,
    'Hue': 22,
    'Saturation': 23,
    'Color': 24,
    'Luminosity': 25,
  };

  /// Composite [src] onto [dst] using PSDTool-accurate blending via Metal GPU.
  ///
  /// Both images must have the same dimensions. Returns a new composited image.
  /// The blend operation uses PSDTool's 3-component alpha algorithm, producing
  /// results that match the CPU [PsdCompositor] and GLSL [PsdCanvasCompositor].
  ///
  /// Throws [StateError] if the compositor has not been initialized or has
  /// been disposed.
  Future<img.Image> composite(
    img.Image src,
    img.Image dst, {
    double opacity = 1.0,
    String blendMode = 'Normal',
  }) async {
    if (!_initialized) {
      throw StateError('Metal compositor not initialized or already disposed');
    }

    final width = dst.width;
    final height = dst.height;

    // Extract straight-alpha RGBA bytes
    final srcBytes = _imageToRgbaBytes(src, width, height);
    final dstBytes = _imageToRgbaBytes(dst, width, height);

    final resultBytes = await _channel.invokeMethod<Uint8List>(
      'composite',
      <String, dynamic>{
        'src': srcBytes,
        'dst': dstBytes,
        'width': width,
        'height': height,
        'blendMode': _blendModeIndex[blendMode] ?? 0,
        'opacity': opacity,
      },
    );

    if (resultBytes == null) {
      throw StateError('Metal compositor returned null result');
    }

    return _rgbaBytesToImage(resultBytes, width, height);
  }

  /// Composite [src] onto [dst] in place, modifying [dst].
  ///
  /// This is a convenience method matching the [PsdCompositor.composite]
  /// signature. The [src] image is composited at [offsetX], [offsetY] within
  /// [dst].
  Future<void> compositeInPlace(
    img.Image dst,
    img.Image src, {
    int offsetX = 0,
    int offsetY = 0,
    double opacity = 1.0,
    String blendMode = 'Normal',
  }) async {
    if (!_initialized) {
      throw StateError('Metal compositor not initialized or already disposed');
    }

    // If src is smaller than dst, we need to create a full-size src buffer
    // with the src image placed at the correct offset
    final width = dst.width;
    final height = dst.height;

    final srcFull = img.Image(width: width, height: height, numChannels: 4)
      ..clear(img.ColorRgba8(0, 0, 0, 0));

    // Copy src pixels to the offset position
    for (int sy = 0; sy < src.height; sy++) {
      final dy = sy + offsetY;
      if (dy < 0 || dy >= height) continue;
      for (int sx = 0; sx < src.width; sx++) {
        final dx = sx + offsetX;
        if (dx < 0 || dx >= width) continue;
        final p = src.getPixel(sx, sy);
        srcFull.setPixelRgba(dx, dy, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
      }
    }

    final result = await composite(srcFull, dst, opacity: opacity, blendMode: blendMode);

    // Copy result back to dst
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final p = result.getPixel(x, y);
        dst.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
      }
    }
  }

  /// Render a PSD layer tree using Metal GPU compositing.
  ///
  /// Equivalent to [PsdCompositor.renderLayerTree] but uses the Metal GPU
  /// for compositing operations.
  Future<img.Image> renderLayerTree(
    List<PsdLayerNode> layers,
    int canvasW,
    int canvasH, {
    bool Function(PsdLayerNode)? visibilityFilter,
  }) async {
    final canvas = img.Image(width: canvasW, height: canvasH, numChannels: 4)
      ..clear(img.ColorRgba8(0, 0, 0, 0));

    await _renderNodes(canvas, layers, canvasW, canvasH, visibilityFilter);
    return canvas;
  }

  Future<void> _renderNodes(
    img.Image canvas,
    List<PsdLayerNode> nodes,
    int canvasW,
    int canvasH,
    bool Function(PsdLayerNode)? filter,
  ) async {
    for (final node in nodes) {
      final visible = filter != null ? filter(node) : node.psdVisible;
      if (!visible) continue;

      if (node.isGroup) {
        final groupBuf =
            img.Image(width: canvasW, height: canvasH, numChannels: 4)
              ..clear(img.ColorRgba8(0, 0, 0, 0));
        await _renderNodes(groupBuf, node.children, canvasW, canvasH, filter);
        final result = await composite(
          groupBuf,
          canvas,
          blendMode: node.blendMode == 'Normal' ? 'Normal' : node.blendMode,
        );
        // Copy result back to canvas
        for (int y = 0; y < canvasH; y++) {
          for (int x = 0; x < canvasW; x++) {
            final p = result.getPixel(x, y);
            canvas.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
          }
        }
      } else if (node.pngBytes != null) {
        final layerImg = img.decodePng(node.pngBytes!);
        if (layerImg != null) {
          await compositeInPlace(
            canvas,
            layerImg,
            offsetX: node.left,
            offsetY: node.top,
            blendMode: node.blendMode,
          );
        }
      }
    }
  }

  /// Release native Metal resources.
  ///
  /// After calling dispose, no further compositing operations can be performed.
  Future<void> dispose() async {
    if (_initialized) {
      _initialized = false;
      try {
        await _channel.invokeMethod<void>('dispose');
      } catch (_) {
        // Ignore errors during dispose
      }
    }
  }

  /// Convert an [img.Image] to straight-alpha RGBA bytes, padded to the
  /// given [width] x [height].
  static Uint8List _imageToRgbaBytes(img.Image image, int width, int height) {
    final bytes = Uint8List(width * height * 4);
    for (int y = 0; y < image.height && y < height; y++) {
      for (int x = 0; x < image.width && x < width; x++) {
        final p = image.getPixel(x, y);
        final i = (y * width + x) * 4;
        bytes[i] = p.r.toInt();
        bytes[i + 1] = p.g.toInt();
        bytes[i + 2] = p.b.toInt();
        bytes[i + 3] = p.a.toInt();
      }
    }
    return bytes;
  }

  /// Convert straight-alpha RGBA bytes back to an [img.Image].
  static img.Image _rgbaBytesToImage(Uint8List bytes, int width, int height) {
    final image = img.Image(width: width, height: height, numChannels: 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        image.setPixelRgba(x, y, bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
      }
    }
    return image;
  }
}

/// Exception thrown when Metal is not available on the current device.
class MetalNotAvailableException implements Exception {
  final String message;
  MetalNotAvailableException(this.message);

  @override
  String toString() => 'MetalNotAvailableException: $message';
}

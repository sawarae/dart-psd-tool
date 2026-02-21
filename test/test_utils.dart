import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:flutter/rendering.dart';
import 'package:dart_psd_tool/dart_psd_tool.dart';

/// Compute RMSE between two images across all RGBA channels.
double computeRmse(img.Image a, img.Image b) {
  assert(a.width == b.width && a.height == b.height);
  final int totalSamples = a.width * a.height * 4;
  double sumSqDiff = 0;

  for (int y = 0; y < a.height; y++) {
    for (int x = 0; x < a.width; x++) {
      final pa = a.getPixel(x, y);
      final pb = b.getPixel(x, y);
      for (int ch = 0; ch < 4; ch++) {
        final double va;
        final double vb;
        switch (ch) {
          case 0:
            va = pa.r.toDouble();
            vb = pb.r.toDouble();
          case 1:
            va = pa.g.toDouble();
            vb = pb.g.toDouble();
          case 2:
            va = pa.b.toDouble();
            vb = pb.b.toDouble();
          case 3:
            va = pa.a.toDouble();
            vb = pb.a.toDouble();
          default:
            va = 0;
            vb = 0;
        }
        sumSqDiff += (va - vb) * (va - vb);
      }
    }
  }

  return sqrt(sumSqDiff / totalSamples);
}

/// Convert a `package:image` Image to a `dart:ui` Image with premultiplied alpha.
Future<ui.Image> imageToUiImage(img.Image source) async {
  final w = source.width;
  final h = source.height;
  final bytes = Uint8List(w * h * 4);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = source.getPixel(x, y);
      final i = (y * w + x) * 4;
      final a = p.a.toInt();
      if (a == 255) {
        bytes[i] = p.r.toInt();
        bytes[i + 1] = p.g.toInt();
        bytes[i + 2] = p.b.toInt();
        bytes[i + 3] = 255;
      } else if (a == 0) {
        bytes[i] = 0;
        bytes[i + 1] = 0;
        bytes[i + 2] = 0;
        bytes[i + 3] = 0;
      } else {
        // Premultiply alpha
        bytes[i] = (p.r.toInt() * a) ~/ 255;
        bytes[i + 1] = (p.g.toInt() * a) ~/ 255;
        bytes[i + 2] = (p.b.toInt() * a) ~/ 255;
        bytes[i + 3] = a;
      }
    }
  }

  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Render a shader composite of [src] onto [dst] using the given [blendMode],
/// then read back the result as a `package:image` Image (un-premultiplied).
Future<img.Image> renderShaderComposite(
  PsdCanvasCompositor compositor,
  img.Image src,
  img.Image dst,
  int width,
  int height,
  String blendMode, {
  double opacity = 1.0,
}) async {
  final srcUi = await imageToUiImage(src);
  final dstUi = await imageToUiImage(dst);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

  compositor.composite(
    canvas,
    srcUi,
    dstUi,
    bounds,
    opacity: opacity,
    blendMode: blendMode,
  );

  final picture = recorder.endRecording();
  final uiImage = await picture.toImage(width, height);
  final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);

  srcUi.dispose();
  dstUi.dispose();
  picture.dispose();
  uiImage.dispose();

  // Convert premultiplied RGBA back to straight alpha
  final result = img.Image(width: width, height: height, numChannels: 4);
  final pixels = byteData!.buffer.asUint8List();

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final a = pixels[i + 3];
      if (a == 0) {
        result.setPixelRgba(x, y, 0, 0, 0, 0);
      } else if (a == 255) {
        result.setPixelRgba(x, y, pixels[i], pixels[i + 1], pixels[i + 2], 255);
      } else {
        // Un-premultiply
        final r = (pixels[i] * 255 ~/ a).clamp(0, 255);
        final g = (pixels[i + 1] * 255 ~/ a).clamp(0, 255);
        final b = (pixels[i + 2] * 255 ~/ a).clamp(0, 255);
        result.setPixelRgba(x, y, r, g, b, a);
      }
    }
  }

  return result;
}

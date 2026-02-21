import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';

/// PSDTool-compatible Flutter Canvas compositor (GPU).
///
/// Uses a custom fragment shader to perform PSDTool's 3-component alpha
/// compositing on the GPU, producing results that match the software
/// [PsdCompositor] exactly.
class PsdCanvasCompositor {
  final ui.FragmentProgram _program;

  PsdCanvasCompositor._(this._program);

  /// Load the PSD composite shader and create a compositor.
  static Future<PsdCanvasCompositor> create() async {
    final program = await ui.FragmentProgram.fromAsset(
      'packages/dart_psd_tool/shaders/psd_composite.frag',
    );
    return PsdCanvasCompositor._(program);
  }

  /// Blend mode name → shader index mapping.
  static const _blendModeIndex = <String, double>{
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
  };

  /// Composite [src] onto [dst] using PSDTool-accurate blending via GPU shader.
  ///
  /// Both [src] and [dst] must be [ui.Image] instances. The result is drawn
  /// to [canvas] within [bounds].
  void composite(
    Canvas canvas,
    ui.Image src,
    ui.Image dst,
    Rect bounds, {
    double opacity = 1.0,
    String blendMode = 'Normal',
  }) {
    final shader = _program.fragmentShader();

    // Uniforms: uSize (0,1), uOpacity (2), uBlendMode (3)
    shader.setFloat(0, bounds.width);
    shader.setFloat(1, bounds.height);
    shader.setFloat(2, opacity);
    shader.setFloat(3, _blendModeIndex[blendMode] ?? 0);

    // Samplers: uSrc (0), uDst (1)
    shader.setImageSampler(0, src);
    shader.setImageSampler(1, dst);

    canvas.drawRect(
      bounds,
      Paint()..shader = shader,
    );

    shader.dispose();
  }

  /// Fast compositing using Flutter's built-in [BlendMode] (approximate).
  ///
  /// Uses the GPU's native blend modes, which may differ slightly from
  /// PSDTool's integer-math implementation. Suitable for real-time preview.
  static void compositeFast(
    Canvas canvas,
    ui.Image src,
    Rect bounds, {
    double opacity = 1.0,
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final paint = Paint()
      ..blendMode = blendMode
      ..color = Color.fromRGBO(255, 255, 255, opacity);

    canvas.saveLayer(bounds, paint);
    canvas.drawImage(src, bounds.topLeft, Paint());
    canvas.restore();
  }

  /// Convert PSD blend mode string to Flutter [BlendMode].
  static BlendMode toFlutterBlendMode(String mode) {
    switch (mode) {
      case 'Multiply':
        return BlendMode.multiply;
      case 'Screen':
        return BlendMode.screen;
      case 'Overlay':
        return BlendMode.overlay;
      case 'Darken':
        return BlendMode.darken;
      case 'Lighten':
        return BlendMode.lighten;
      case 'ColorDodge':
        return BlendMode.colorDodge;
      case 'ColorBurn':
        return BlendMode.colorBurn;
      case 'HardLight':
        return BlendMode.hardLight;
      case 'SoftLight':
        return BlendMode.softLight;
      case 'Difference':
        return BlendMode.difference;
      case 'LinearDodge':
        return BlendMode.plus;
      case 'Subtract':
        return BlendMode.difference; // approximate
      default:
        return BlendMode.srcOver;
    }
  }
}

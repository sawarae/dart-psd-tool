import 'package:image/image.dart' as img;

import 'blend_modes.dart';
import 'psd_layer_node.dart';

/// PSDTool-compatible software compositor (CPU).
///
/// Implements PSDTool's 3-component alpha blending algorithm for accurate
/// compositing that matches PSDTool Go's output.
class PsdCompositor {
  PsdCompositor._();

  /// Composite [src] onto [dst] using PSDTool-compatible 3-component alpha
  /// blending. Reference: PSDTool src/blend/blend.ts
  ///
  /// For each pixel:
  ///   tmp = src_alpha * opacity
  ///   a1 = tmp * dst_alpha            (blend result contribution)
  ///   a2 = tmp * (255 - dst_alpha)    (source-only, where dst is transparent)
  ///   a3 = (255 - tmp) * dst_alpha    (dest-only, where src is transparent)
  ///   out_alpha = a1 + a2 + a3
  ///   out_rgb = (blended * a1 + src_rgb * a2 + dst_rgb * a3) / out_alpha
  static void composite(
    img.Image dst,
    img.Image src, {
    int offsetX = 0,
    int offsetY = 0,
    double opacity = 1.0,
    String blendMode = 'Normal',
    bool srcPremultiplied = false,
  }) {
    final isDissolve = blendMode == 'Dissolve';
    final blendFn = PsdBlendModes.resolveComposite(blendMode);

    for (int sy = 0; sy < src.height; sy++) {
      final dy = sy + offsetY;
      if (dy < 0 || dy >= dst.height) continue;
      for (int sx = 0; sx < src.width; sx++) {
        final dx = sx + offsetX;
        if (dx < 0 || dx >= dst.width) continue;

        final sp = src.getPixel(sx, sy);
        final sa = sp.a.toInt();
        if (sa == 0) continue;

        final dp = dst.getPixel(dx, dy);
        final da = dp.a.toInt();

        // Un-premultiply src RGB if needed
        final int sr, sg, sb;
        if (!srcPremultiplied || sa == 255) {
          sr = sp.r.toInt();
          sg = sp.g.toInt();
          sb = sp.b.toInt();
        } else {
          sr = (sp.r.toInt() * 255 ~/ sa).clamp(0, 255);
          sg = (sp.g.toInt() * 255 ~/ sa).clamp(0, 255);
          sb = (sp.b.toInt() * 255 ~/ sa).clamp(0, 255);
        }
        // Dest canvas is premultiplied from prior compositing
        final int dr, dg, db;
        if (da == 0 || da == 255) {
          dr = dp.r.toInt();
          dg = dp.g.toInt();
          db = dp.b.toInt();
        } else {
          dr = (dp.r.toInt() * 255 ~/ da).clamp(0, 255);
          dg = (dp.g.toInt() * 255 ~/ da).clamp(0, 255);
          db = (dp.b.toInt() * 255 ~/ da).clamp(0, 255);
        }

        // Dissolve: binary alpha based on hash threshold
        if (isDissolve) {
          final effectiveAlpha = (sa * opacity).round();
          // Deterministic hash of pixel position for stable output
          final hash = ((dx * 73856093) ^ (dy * 19349663)) & 0xFF;
          if (hash >= effectiveAlpha) continue;
          // Show source pixel at full opacity
          final a = da == 0 ? 255 : (da + 255 - ((da * 255 * 32897) >> 23));
          dst.setPixelRgba(dx, dy, sr, sg, sb, a.clamp(0, 255));
          continue;
        }

        // PSDTool: tmp = sa * opacity * 32897
        final tmp = (sa * opacity * 32897).toInt();

        // 3-component alpha weights (PSDTool blend.ts lines 91-95)
        final a1 = (tmp * da) >> 23;
        final a2 = (tmp * (255 - da)) >> 23;
        final a3 = ((8388735 - tmp) * da) >> 23;
        final a = a1 + a2 + a3;
        if (a == 0) continue;

        // Blend operation (per-pixel, handles both per-channel and HSL modes)
        final (br, bg, bb) = blendFn!(sr, sg, sb, dr, dg, db);

        // Final composite (PSDTool blend.ts lines 105-107)
        final outR = ((br * a1 + sr * a2 + dr * a3) ~/ a).clamp(0, 255);
        final outG = ((bg * a1 + sg * a2 + dg * a3) ~/ a).clamp(0, 255);
        final outB = ((bb * a1 + sb * a2 + db * a3) ~/ a).clamp(0, 255);

        dst.setPixelRgba(dx, dy, outR, outG, outB, a);
      }
    }
  }

  /// Render a PSD layer tree to a composited image.
  ///
  /// Traverses the layer tree and composites visible leaf layers onto a
  /// canvas. Group nodes are recursively composited to intermediate buffers
  /// to correctly handle group blend modes and opacity.
  ///
  /// [visibilityFilter] controls which layers are rendered. If null, all
  /// layers with [PsdLayerNode.psdVisible] == true are rendered.
  static img.Image renderLayerTree(
    List<PsdLayerNode> layers,
    int canvasW,
    int canvasH, {
    bool Function(PsdLayerNode)? visibilityFilter,
  }) {
    final canvas = img.Image(width: canvasW, height: canvasH, numChannels: 4)
      ..clear(img.ColorRgba8(0, 0, 0, 0));

    _renderNodes(canvas, layers, canvasW, canvasH, visibilityFilter);
    return canvas;
  }

  static void _renderNodes(
    img.Image canvas,
    List<PsdLayerNode> nodes,
    int canvasW,
    int canvasH,
    bool Function(PsdLayerNode)? filter,
  ) {
    for (final node in nodes) {
      final visible = filter != null ? filter(node) : node.psdVisible;
      if (!visible) continue;

      if (node.isGroup) {
        // Composite group children to an intermediate buffer, then
        // composite the buffer onto the canvas with the group's blend mode.
        final groupBuf =
            img.Image(width: canvasW, height: canvasH, numChannels: 4)
              ..clear(img.ColorRgba8(0, 0, 0, 0));
        _renderNodes(groupBuf, node.children, canvasW, canvasH, filter);
        composite(canvas, groupBuf,
            blendMode: node.blendMode == 'Normal'
                ? 'Normal'
                : node.blendMode);
      } else if (node.pngBytes != null) {
        final layerImg = img.decodePng(node.pngBytes!);
        if (layerImg != null) {
          composite(
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
}

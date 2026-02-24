import 'dart:typed_data';

/// Represents a node in the PSD layer tree.
class PsdLayerNode {
  final String name;
  final bool isGroup;
  final bool isDefault; // `!` prefix in psdtools convention
  final bool isVariant; // `*` prefix in psdtools convention

  /// Effective PSD visibility: true if this layer AND all its ancestor groups
  /// are visible in the PSD file's default state (as shown in Photoshop).
  final bool psdVisible;

  final int left;
  final int top;
  final int right;
  final int bottom;
  final List<PsdLayerNode> children;
  Uint8List? pngBytes; // Extracted PNG for leaf layers (straight alpha)

  /// PSD blend mode string (e.g. 'Normal', 'Multiply', 'Screen').
  final String blendMode;

  /// True when this layer has the PSD clipping bit set (clipping = 1).
  ///
  /// A clipping layer is composited only within the opaque pixels of the
  /// first non-clipping layer below it in the same group ("clip to base").
  final bool isClipping;

  PsdLayerNode({
    required this.name,
    required this.isGroup,
    required this.isDefault,
    required this.isVariant,
    this.psdVisible = true,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    List<PsdLayerNode>? children,
    this.pngBytes,
    this.blendMode = 'Normal',
    this.isClipping = false,
  }) : children = children ?? [];

  /// The raw name without `!` or `*` prefix.
  String get baseName {
    if (name.startsWith('!') || name.startsWith('*')) {
      return name.substring(1);
    }
    return name;
  }

  int get width => (right - left).abs();
  int get height => (bottom - top).abs();

  @override
  String toString() =>
      'PsdLayerNode($name, group=$isGroup, children=${children.length})';
}

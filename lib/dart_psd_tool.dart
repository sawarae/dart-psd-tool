/// PSDTool-compatible PSD reader and compositor library.
///
/// Provides software (CPU), GLSL GPU, and Metal GPU compositing that matches
/// PSDTool Go's output exactly using 3-component alpha blending.
library dart_psd_tool;

export 'src/psd_layer_node.dart';
export 'src/psd_reader.dart';
export 'src/blend_modes.dart';
export 'src/compositor.dart';
export 'src/canvas_compositor.dart';
export 'src/metal_compositor.dart';

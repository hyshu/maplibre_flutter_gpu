// Integer ABI values shared with the native DrawCommand export. These values
// must remain synchronized with native. DrawCommand records are decoded using
// their generated field offsets.

/// Shader type ABI values matching `command_export::ShaderType`.
abstract final class ShaderType {
  static const fill = 0;
  static const fillOutline = 1;
  static const line = 2;
  static const background = 3;
  static const fillExtrusion = 4;

  /// Dashed line shader using `line-dasharray`.
  static const lineSDF = 5;
  static const lineGradient = 6;
  static const linePattern = 7;
  static const circle = 8;
  static const raster = 9;

  /// Antialiased triangulated fill outline shader.
  static const fillOutlineTriangulated = 10;

  /// Tile clipping quad that writes only to the stencil attachment.
  static const clippingMask = 11;

  /// Repeating background pattern shader.
  static const backgroundPattern = 12;

  /// Gaussian density accumulation into a heatmap render target.
  static const heatmap = 13;

  /// Color ramp composition from a heatmap density texture.
  static const heatmapTexture = 14;

  /// Ordered control command that selects and clears an offscreen target.
  static const renderTarget = 15;

  /// Encodes terrain derivatives from raster elevation tiles.
  static const hillshadePrepare = 16;

  /// Lights prepared terrain derivatives in map layer order.
  static const hillshade = 17;

  /// Sentinel for an unrecognized shader type.
  static const unknown = 255;
}

/// Resolved stencil behavior matching `command_export::StencilModeType`.
abstract final class StencilModeType {
  static const disabled = 0;

  /// Always passes and replaces the stencil value using write mask `0xff`.
  static const clippingMask = 1;

  /// Tests for equality without changing the stencil value.
  static const clippingTest = 2;

  /// Tests for inequality and replaces the value using write mask `0xff`.
  static const fillExtrusion = 3;

  /// Ordered control command that clears the stencil attachment.
  static const clear = 4;
}

/// Primitive draw mode ABI values matching `command_export::DrawModeType`.
abstract final class DrawModeType {
  static const triangles = 0;
  static const lines = 1;
  static const lineStrip = 2;
  static const points = 3;
}

/// Texture filter ABI values matching `command_export::TextureFilterType`.
abstract final class TextureFilterType {
  static const nearest = 0;
  static const linear = 1;
}

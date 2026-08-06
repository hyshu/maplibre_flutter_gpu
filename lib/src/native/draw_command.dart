// Integer ABI values shared with the native DrawCommand export. These values
// must remain synchronized with native. DrawCommand records are decoded using
// their generated field offsets.

/// Shader type ABI values matching `command_export::ShaderType`.
abstract final class ShaderType {
  static const int fill = 0;
  static const int fillOutline = 1;
  static const int line = 2;
  static const int background = 3;
  static const int fillExtrusion = 4;

  /// Dashed line shader using `line-dasharray`.
  static const int lineSDF = 5;
  static const int lineGradient = 6;
  static const int linePattern = 7;
  static const int circle = 8;
  static const int raster = 9;

  /// Antialiased triangulated fill outline shader.
  static const int fillOutlineTriangulated = 10;

  /// Tile clipping quad that writes only to the stencil attachment.
  static const int clippingMask = 11;

  /// Repeating background pattern shader.
  static const int backgroundPattern = 12;

  /// Sentinel for an unrecognized shader type.
  static const int unknown = 255;
}

/// Resolved stencil behavior matching `command_export::StencilModeType`.
abstract final class StencilModeType {
  static const int disabled = 0;

  /// Always passes and replaces the stencil value using write mask `0xff`.
  static const int clippingMask = 1;

  /// Tests for equality without changing the stencil value.
  static const int clippingTest = 2;

  /// Tests for inequality and replaces the value using write mask `0xff`.
  static const int fillExtrusion = 3;

  /// Ordered control command that clears the stencil attachment.
  static const int clear = 4;
}

/// Primitive draw mode ABI values matching `command_export::DrawModeType`.
abstract final class DrawModeType {
  static const int triangles = 0;
  static const int lines = 1;
  static const int lineStrip = 2;
  static const int points = 3;
}

/// Texture filter ABI values matching `command_export::TextureFilterType`.
abstract final class TextureFilterType {
  static const int nearest = 0;
  static const int linear = 1;
}

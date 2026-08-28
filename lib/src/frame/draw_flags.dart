// DrawCommand flag bits and the vertex-layout decisions derived from them.
//
// The bit values must match command_export::DrawCommand on the C++ side. The
// strides and masks must match the Flutter GPU shaders.
import '../native/draw_command.dart';

/// DrawCommand flag bits matching command_export::DrawCommand::Flags plus
/// bridge-owned transport flags that never reach the shader-facing masks.
///
/// Data-driven bits are grouped per layer type and the group masks are shifted
/// down to the shader-facing mask by the helpers below, so the shift amounts
/// and the bit positions can never drift apart.
abstract final class DrawCommandFlags {
  static const crossTileMerged = 1 << 0;
  static const fillExtrusionDataDriven = 1 << 1;
  static const fillColorDataDriven = 1 << 2;
  static const fillOpacityDataDriven = 1 << 3;
  static const fillExtrusionColorDataDriven = 1 << 4;
  static const circleColorDataDriven = 1 << 5;
  static const circleRadiusDataDriven = 1 << 6;
  static const circleBlurDataDriven = 1 << 7;
  static const circleOpacityDataDriven = 1 << 8;
  static const circleStrokeColorDataDriven = 1 << 9;
  static const circleStrokeWidthDataDriven = 1 << 10;
  static const circleStrokeOpacityDataDriven = 1 << 11;
  static const lineColorDataDriven = 1 << 12;
  static const lineBlurDataDriven = 1 << 13;
  static const lineOpacityDataDriven = 1 << 14;
  static const lineGapWidthDataDriven = 1 << 15;
  static const lineOffsetDataDriven = 1 << 16;
  static const lineWidthDataDriven = 1 << 17;
  static const lineFloorWidthDataDriven = 1 << 18;
  static const linePatternDataDriven = 1 << 19;
  static const fillOutlineColorDataDriven = 1 << 20;
  static const fillOutlineOpacityDataDriven = 1 << 21;
  static const depthTest = 1 << 22;
  static const depthWrite = 1 << 23;

  /// Legacy bridge-only marker: a data-driven fill-extrusion vertex buffer was
  /// expanded from the packed 44-byte source layout to the old 56-byte float
  /// layout. New native builds keep the 44-byte layout packed, but Dart keeps
  /// this marker so already-packaged native artifacts remain compatible.
  static const fillExtrusionGpuReady = 1 << 24;

  /// Bridge-only marker: a line-family vertex buffer has already expanded its
  /// packed layout prefix to float32. Older/current bridge artifacts can export
  /// 24-byte constant or 120-byte DD vertices. Constant-line Flutter GPU
  /// shaders now consume 8-byte packed vertices, so 24-byte compatibility data
  /// is packed back in Dart before upload; DD keeps the 120-byte layout.
  static const lineGpuReady = 1 << 25;

  /// Bit position of the lowest bit in each data-driven group. The helpers
  /// shift by these so a mask and its shift stay defined in one place.
  static const fillDataDrivenShift = 2;
  static const fillExtrusionColorDataDrivenShift = 4;
  static const circleDataDrivenShift = 5;
  static const lineDataDrivenShift = 12;
  static const fillOutlineDataDrivenShift = 20;

  static const fillDataDrivenMask =
      fillColorDataDriven | fillOpacityDataDriven;

  static const fillOutlineDataDrivenMask =
      fillOutlineColorDataDriven | fillOutlineOpacityDataDriven;

  static const circleDataDrivenMask =
      circleColorDataDriven |
      circleRadiusDataDriven |
      circleBlurDataDriven |
      circleOpacityDataDriven |
      circleStrokeColorDataDriven |
      circleStrokeWidthDataDriven |
      circleStrokeOpacityDataDriven;

  static const lineDataDrivenMask =
      lineColorDataDriven |
      lineBlurDataDriven |
      lineOpacityDataDriven |
      lineGapWidthDataDriven |
      lineOffsetDataDriven |
      lineWidthDataDriven |
      lineFloorWidthDataDriven |
      linePatternDataDriven;
}

/// Native vertex stride of a cross-tile merged buffer.
///
/// Merged geometry uses a plain `float x, y` vertex on both the native and
/// Flutter GPU sides, so no repacking is needed.
const mergedVertexStride = 8;

/// Whether the command draws a cross-tile merged buffer.
bool drawCommandIsCrossTileMerged(int flags) =>
    (flags & DrawCommandFlags.crossTileMerged) != 0;

/// Whether the effective MapLibre depth state enables depth testing.
bool drawCommandUsesDepth(int flags) =>
    (flags & DrawCommandFlags.depthTest) != 0;

/// Whether the effective MapLibre depth state writes to the depth buffer.
bool drawCommandWritesDepth(int flags) =>
    (flags & DrawCommandFlags.depthWrite) != 0;

/// Whether the shader belongs to the supported line family.
bool isLineShader(int shader) =>
    shader == ShaderType.line ||
    shader == ShaderType.lineSDF ||
    shader == ShaderType.lineGradient ||
    shader == ShaderType.linePattern;

/// Whether a fill command needs the normalized 28-byte data-driven pipeline.
bool fillUsesDataDrivenPipeline(int flags) =>
    (flags & DrawCommandFlags.fillDataDrivenMask) != 0;

/// Two-bit mask consumed by FillDDVertex (bit0=color, bit1=opacity).
int fillDataDrivenMask(int flags) =>
    (flags & DrawCommandFlags.fillDataDrivenMask) >>
    DrawCommandFlags.fillDataDrivenShift;

/// Exported fill vertex stride for the command flags.
int fillVertexStride(int flags) => fillUsesDataDrivenPipeline(flags) ? 28 : 4;

/// Whether a triangulated fill-outline command carries normalized paint
/// attributes in addition to its native 8-byte line-layout vertex.
bool fillOutlineUsesDataDrivenPipeline(int flags) =>
    (flags & DrawCommandFlags.fillOutlineDataDrivenMask) != 0;

/// Two-bit mask consumed by FillOutlineTriangulatedDDVertex
/// (bit0=outline-color, bit1=opacity).
int fillOutlineDataDrivenMask(int flags) =>
    (flags & DrawCommandFlags.fillOutlineDataDrivenMask) >>
    DrawCommandFlags.fillOutlineDataDrivenShift;

/// Exported triangulated fill-outline stride. The DD layout appends the
/// outline-color and opacity ranges at byte offsets 8 and 24.
int fillOutlineVertexStride(int flags) =>
    fillOutlineUsesDataDrivenPipeline(flags) ? 32 : 8;

/// Whether a fill-extrusion command uses the normalized data-driven layout.
bool fillExtrusionUsesDataDrivenPipeline(int flags) =>
    (flags & DrawCommandFlags.fillExtrusionDataDriven) != 0;

/// Whether this command uses the legacy bridge-expanded 56-byte FE DD layout.
bool fillExtrusionUsesExpandedGpuLayout(int flags) =>
    fillExtrusionUsesDataDrivenPipeline(flags) &&
    (flags & DrawCommandFlags.fillExtrusionGpuReady) != 0;

/// One-bit mask consumed by FillExtrusionDDVertex (bit0=color).
int fillExtrusionDataDrivenMask(int flags) =>
    (flags & DrawCommandFlags.fillExtrusionColorDataDriven) >>
    DrawCommandFlags.fillExtrusionColorDataDrivenShift;

/// Exported fill-extrusion stride. Command Export's normalized DD layout is 44
/// bytes. Older bridge artifacts can instead mark a 56-byte expanded layout.
int fillExtrusionVertexStride(int flags) {
  if (!fillExtrusionUsesDataDrivenPipeline(flags)) return 12;
  return fillExtrusionUsesExpandedGpuLayout(flags) ? 56 : 44;
}

/// Whether fill extrusion needs a depth prepass for [opacity].
///
/// An opacity below 1 or a NaN value requires the prepass.
bool fillExtrusionNeedsDepthPrepass(double opacity) => !(opacity >= 1.0);

/// Whether a circle command needs the normalized 76-byte pipeline.
bool circleUsesDataDrivenPipeline(int flags) =>
    (flags & DrawCommandFlags.circleDataDrivenMask) != 0;

/// Seven-bit mask consumed by CircleDD shaders. The order matches MapLibre's
/// shader attributes from color through stroke-opacity.
int circleDataDrivenMask(int flags) =>
    (flags & DrawCommandFlags.circleDataDrivenMask) >>
    DrawCommandFlags.circleDataDrivenShift;

/// Exported circle vertex stride for the command flags.
int circleVertexStride(int flags) =>
    circleUsesDataDrivenPipeline(flags) ? 76 : 4;

/// Whether a line-family command needs the normalized data-driven pipeline.
bool lineUsesDataDrivenPipeline(int flags) =>
    (flags & DrawCommandFlags.lineDataDrivenMask) != 0;

/// Eight-bit mask consumed by Line DD shaders, ordered color, blur, opacity,
/// gap-width, offset, width, floor-width, and pattern.
int lineDataDrivenMask(int flags) =>
    (flags & DrawCommandFlags.lineDataDrivenMask) >>
    DrawCommandFlags.lineDataDrivenShift;

/// Exported line-family stride. Command Export emits packed 8/88-byte layouts.
/// Bridge-expanded compatibility layouts remain 24/120 bytes when bit25 is set.
int lineVertexStride(int flags) {
  final dataDriven = lineUsesDataDrivenPipeline(flags);
  if ((flags & DrawCommandFlags.lineGpuReady) != 0) {
    return dataDriven ? 120 : 24;
  }
  return dataDriven ? 88 : 8;
}

/// Vertex stride consumed by Flutter GPU after packed integer attributes have
/// been expanded to numeric floats for Impeller's OpenGLES backend.
int gpuVertexStride(int shader, int flags) {
  final usesMergedLayout =
      drawCommandIsCrossTileMerged(flags) &&
      (shader == ShaderType.background ||
          (shader == ShaderType.fill && !fillUsesDataDrivenPipeline(flags)));
  if (usesMergedLayout) return mergedVertexStride;
  return switch (shader) {
    ShaderType.fill => fillVertexStride(flags) + 4,
    ShaderType.fillOutline ||
    ShaderType.background ||
    ShaderType.clippingMask ||
    ShaderType.backgroundPattern => 8,
    ShaderType.circle => circleVertexStride(flags) + 4,
    ShaderType.fillExtrusion =>
      fillExtrusionUsesDataDrivenPipeline(flags) ? 56 : 24,
    ShaderType.line ||
    ShaderType.lineSDF ||
    ShaderType.lineGradient ||
    ShaderType.linePattern => lineUsesDataDrivenPipeline(flags) ? 120 : 24,
    ShaderType.fillOutlineTriangulated =>
      fillOutlineUsesDataDrivenPipeline(flags) ? 48 : 24,
    ShaderType.raster => 16,
    _ => throw ArgumentError.value(shader, 'shader', 'Unsupported shader type'),
  };
}

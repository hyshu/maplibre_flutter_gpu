// Byte-level layout of the uniform buffers the renderer hands to Flutter GPU.
//
// Every offset and size here mirrors a MapLibre UBO struct. The renderer packs
// native bytes into these positions verbatim, so a wrong value corrupts a draw
// without producing an explicit error.
import '../native/draw_command.dart';

/// Byte sizes of the uniform blocks exported for one shader.
typedef RendererUboLayout = ({
  int drawableBytes,
  int propsBytes,
  int tilePropsBytes,
});

/// MapLibre shader UBO ABI values used by the Flutter renderer.
abstract final class RendererUboAbi {
  static const noUniformBytes = 0;
  static const float32Bytes = 4;
  static const vec4Bytes = 16;
  static const fillColorComponentCount = 4;

  static const minimumUniformByteAlignment = 16;
  static const minimumUniformAllocationBytes = 16;

  static const drawableMatrixBytes = 64;
  static const drawableMatrixM11Offset = 20;

  static const fillDrawableBytes = 80;
  static const fillPropsBytes = 48;
  static const fillExtrusionDrawableBytes = 112;
  static const fillExtrusionPropsBytes = 80;
  static const lineDrawableBytes = 96;
  static const lineSdfDrawableBytes = 128;
  static const linePropsBytes = 48;
  static const lineSdfTilePropsBytes = 16;
  static const linePatternTilePropsBytes = 64;
  static const circleDrawableBytes = 112;
  static const circlePropsBytes = 64;
  static const heatmapDrawableBytes = 80;
  static const heatmapPropsBytes = 16;
  static const heatmapTextureDrawableBytes = 80;
  static const hillshadeDrawableBytes = 64;
  static const hillshadePropsBytes = 176;
  static const hillshadeTilePropsBytes = 32;
  static const hillshadePrepareTilePropsBytes = 32;
  static const rasterDrawableBytes = 64;
  static const rasterPropsBytes = 64;
  static const clippingMaskDrawableBytes = 64;
  static const backgroundPatternDrawableBytes = 96;
  static const backgroundPatternPropsBytes = 64;
  static const mapGlobalBytes = 16;

  static const backgroundPatternAtlasWidthOffset = 84;
  static const backgroundPatternAtlasHeightOffset = 88;
  static const circleCameraDistanceOffset = 100;
  static const circleDevicePixelRatioOffset = 104;
  static const circleDataDrivenMaskOffset = 60;
  static const heatmapDataDrivenMaskOffset = 12;
  static const fillExtrusionDataDrivenMaskOffset = 108;
  static const fillExtrusionOpacityOffset = 60;
  static const lineDevicePixelRatioOffset = 92;
  static const lineSdfDevicePixelRatioOffset = 120;
  static const lineDataDrivenMaskOffset = 40;
  static const lineOpacityOffset = 20;
  static const lineWidthOffset = 32;
  static const fillDataDrivenMaskOffset = 72;
  static const fillOutlineDevicePixelRatioOffset = 68;
  static const backgroundOpacityOffset = 16;
  static const fillColorOffset = 0;
  static const fillOutlineColorOffset = 16;
  static const fillOpacityOffset = 32;
  static const fillOutlineDataDrivenMaskOffset = 36;

  static const mapGlobalUnitsXOffset = 0;
  static const mapGlobalUnitsYOffset = 4;
  static const mapGlobalWorldWidthOffset = 8;
  static const mapGlobalWorldHeightOffset = 12;
}

/// Exact shader-to-UBO layout map shared by allocation and packing.
RendererUboLayout rendererUboLayoutForShader(int shader) => switch (shader) {
  ShaderType.fill ||
  ShaderType.fillOutline ||
  ShaderType.background ||
  ShaderType.fillOutlineTriangulated => (
    drawableBytes: RendererUboAbi.fillDrawableBytes,
    propsBytes: RendererUboAbi.fillPropsBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  ShaderType.fillExtrusion => (
    drawableBytes: RendererUboAbi.fillExtrusionDrawableBytes,
    propsBytes: RendererUboAbi.fillExtrusionPropsBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  ShaderType.line || ShaderType.lineGradient => (
    drawableBytes: RendererUboAbi.lineDrawableBytes,
    propsBytes: RendererUboAbi.linePropsBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  ShaderType.lineSDF => (
    drawableBytes: RendererUboAbi.lineSdfDrawableBytes,
    propsBytes: RendererUboAbi.linePropsBytes,
    tilePropsBytes: RendererUboAbi.lineSdfTilePropsBytes,
  ),
  ShaderType.linePattern => (
    drawableBytes: RendererUboAbi.lineDrawableBytes,
    propsBytes: RendererUboAbi.linePropsBytes,
    tilePropsBytes: RendererUboAbi.linePatternTilePropsBytes,
  ),
  ShaderType.circle => (
    drawableBytes: RendererUboAbi.circleDrawableBytes,
    propsBytes: RendererUboAbi.circlePropsBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  ShaderType.raster => (
    drawableBytes: RendererUboAbi.rasterDrawableBytes,
    propsBytes: RendererUboAbi.rasterPropsBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  ShaderType.heatmap => (
    drawableBytes: RendererUboAbi.heatmapDrawableBytes,
    propsBytes: RendererUboAbi.heatmapPropsBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  ShaderType.heatmapTexture => (
    drawableBytes: RendererUboAbi.heatmapTextureDrawableBytes,
    propsBytes: RendererUboAbi.noUniformBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  ShaderType.hillshadePrepare => (
    drawableBytes: RendererUboAbi.hillshadeDrawableBytes,
    propsBytes: RendererUboAbi.noUniformBytes,
    tilePropsBytes: RendererUboAbi.hillshadePrepareTilePropsBytes,
  ),
  ShaderType.hillshade => (
    drawableBytes: RendererUboAbi.hillshadeDrawableBytes,
    propsBytes: RendererUboAbi.hillshadePropsBytes,
    tilePropsBytes: RendererUboAbi.hillshadeTilePropsBytes,
  ),
  ShaderType.clippingMask => (
    drawableBytes: RendererUboAbi.clippingMaskDrawableBytes,
    propsBytes: RendererUboAbi.noUniformBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  ShaderType.backgroundPattern => (
    drawableBytes: RendererUboAbi.backgroundPatternDrawableBytes,
    propsBytes: RendererUboAbi.backgroundPatternPropsBytes,
    tilePropsBytes: RendererUboAbi.noUniformBytes,
  ),
  _ => throw ArgumentError.value(shader, 'shader', 'Unsupported shader type'),
};

/// Whether a byte range contains the complete float at [offset].
bool rendererUboContainsFloat32(int byteLength, int offset) =>
    byteLength >= offset + RendererUboAbi.float32Bytes;

/// Aligns a uniform-buffer offset to the backend's binding requirement.
int alignUniformOffset(int offset, int alignment) {
  assert(offset >= 0);
  assert(alignment > 0);

  return ((offset + alignment - 1) ~/ alignment) * alignment;
}

/// Where one frame's shared uniforms sit, and how large the block must be.
typedef FrameUniformLayout = ({int mapGlobalOffset, int totalBytes});

/// Places `GlobalPaintParamsUBO` after the per-draw uniforms and sizes the
/// frame's uniform block.
///
/// [drawableCursor] is the end of the per-draw uniform range. The returned size
/// is aligned and at least [RendererUboAbi.minimumUniformAllocationBytes].
FrameUniformLayout layoutFrameUniforms({
  required int drawableCursor,
  required int alignment,
  required bool hasMapGlobal,
}) {
  final mapGlobalOffset = hasMapGlobal
      ? alignUniformOffset(drawableCursor, alignment)
      : 0;
  final cursor = hasMapGlobal
      ? mapGlobalOffset + RendererUboAbi.mapGlobalBytes
      : drawableCursor;

  return (
    mapGlobalOffset: mapGlobalOffset,
    totalBytes: alignUniformOffset(
      cursor < RendererUboAbi.minimumUniformAllocationBytes
          ? RendererUboAbi.minimumUniformAllocationBytes
          : cursor,
      alignment,
    ),
  );
}

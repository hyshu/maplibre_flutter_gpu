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
  static const int noUniformBytes = 0;
  static const int float32Bytes = 4;
  static const int vec4Bytes = 16;
  static const int fillColorComponentCount = 4;

  static const int minimumUniformByteAlignment = 16;
  static const int minimumUniformAllocationBytes = 16;

  static const int drawableMatrixBytes = 64;
  static const int drawableMatrixM11Offset = 20;

  static const int fillDrawableBytes = 80;
  static const int fillPropsBytes = 48;
  static const int fillExtrusionDrawableBytes = 112;
  static const int fillExtrusionPropsBytes = 80;
  static const int lineDrawableBytes = 96;
  static const int lineSdfDrawableBytes = 128;
  static const int linePropsBytes = 48;
  static const int lineSdfTilePropsBytes = 16;
  static const int linePatternTilePropsBytes = 64;
  static const int circleDrawableBytes = 112;
  static const int circlePropsBytes = 64;
  static const int rasterDrawableBytes = 64;
  static const int rasterPropsBytes = 64;
  static const int clippingMaskDrawableBytes = 64;
  static const int backgroundPatternDrawableBytes = 96;
  static const int backgroundPatternPropsBytes = 64;
  static const int mapGlobalBytes = 16;

  static const int backgroundPatternAtlasWidthOffset = 84;
  static const int backgroundPatternAtlasHeightOffset = 88;
  static const int circleCameraDistanceOffset = 100;
  static const int circleDevicePixelRatioOffset = 104;
  static const int circleDataDrivenMaskOffset = 60;
  static const int fillExtrusionDataDrivenMaskOffset = 108;
  static const int fillExtrusionOpacityOffset = 60;
  static const int lineDevicePixelRatioOffset = 92;
  static const int lineSdfDevicePixelRatioOffset = 120;
  static const int lineDataDrivenMaskOffset = 40;
  static const int lineOpacityOffset = 20;
  static const int lineWidthOffset = 32;
  static const int fillDataDrivenMaskOffset = 72;
  static const int fillOutlineDevicePixelRatioOffset = 68;
  static const int backgroundOpacityOffset = 16;
  static const int fillColorOffset = 0;
  static const int fillOutlineColorOffset = 16;
  static const int fillOpacityOffset = 32;
  static const int fillOutlineDataDrivenMaskOffset = 36;

  static const int mapGlobalUnitsXOffset = 0;
  static const int mapGlobalUnitsYOffset = 4;
  static const int mapGlobalWorldWidthOffset = 8;
  static const int mapGlobalWorldHeightOffset = 12;
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

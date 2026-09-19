part of '../uniform_packer.dart';

/// Packs fields after the matrix, including renderer values in native padding.
void _packDrawableUniforms({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required Uint8List destination,
  required ByteData destinationData,
  required int shader,
  required int flags,
  required int drawableOffset,
  required int drawableLength,
  required double devicePixelRatio,
  required int textureWidth,
  required int textureHeight,
}) {
  // Raster drawables contain only the matrix, which the caller already copied.
  if (shader == ShaderType.raster) return;

  final isLine = isLineShader(shader);
  final isDataDrivenFill =
      shader == ShaderType.fill && fillUsesDataDrivenPipeline(flags);
  if (isLine ||
      isDataDrivenFill ||
      shader == ShaderType.circle ||
      shader == ShaderType.fillExtrusion ||
      shader == ShaderType.fillOutlineTriangulated ||
      shader == ShaderType.backgroundPattern) {
    _copyDrawableTail(
      source: source,
      commandOffset: commandOffset,
      destination: destination,
      drawableOffset: drawableOffset,
      drawableLength: drawableLength,
    );
  } else {
    // Fixed fill and background shaders consume no fields beyond the matrix.
    destination.fillRange(
      drawableOffset + RendererUboAbi.drawableMatrixBytes,
      drawableOffset + drawableLength,
      0,
    );
  }

  if (shader == ShaderType.backgroundPattern) {
    // Native drawable padding supplies atlas dimensions in place of global UBOs.
    destinationData.setFloat32(
      drawableOffset + RendererUboAbi.backgroundPatternAtlasWidthOffset,
      textureWidth.toDouble(),
      Endian.little,
    );
    destinationData.setFloat32(
      drawableOffset + RendererUboAbi.backgroundPatternAtlasHeightOffset,
      textureHeight.toDouble(),
      Endian.little,
    );
  } else if (shader == ShaderType.circle) {
    destinationData.setFloat32(
      drawableOffset + RendererUboAbi.circleCameraDistanceOffset,
      sourceData.getFloat32(
        commandOffset + DrawCommandAbi.cameraDistance,
        Endian.little,
      ),
      Endian.little,
    );
    destinationData.setFloat32(
      drawableOffset + RendererUboAbi.circleDevicePixelRatioOffset,
      devicePixelRatio,
      Endian.little,
    );
  } else if (shader == ShaderType.fillExtrusion &&
      fillExtrusionUsesDataDrivenPipeline(flags)) {
    destinationData.setUint32(
      drawableOffset + RendererUboAbi.fillExtrusionDataDrivenMaskOffset,
      fillExtrusionDataDrivenMask(flags),
      Endian.little,
    );
  } else if (shader == ShaderType.line || shader == ShaderType.lineGradient) {
    destinationData.setFloat32(
      drawableOffset + RendererUboAbi.lineDevicePixelRatioOffset,
      devicePixelRatio,
      Endian.little,
    );
  } else if (shader == ShaderType.lineSDF) {
    destinationData.setFloat32(
      drawableOffset + RendererUboAbi.lineSdfDevicePixelRatioOffset,
      devicePixelRatio,
      Endian.little,
    );
  } else if (shader == ShaderType.fillOutlineTriangulated) {
    destinationData.setFloat32(
      drawableOffset + RendererUboAbi.fillOutlineDevicePixelRatioOffset,
      devicePixelRatio,
      Endian.little,
    );
  } else if (isDataDrivenFill) {
    destinationData.setUint32(
      drawableOffset + RendererUboAbi.fillDataDrivenMaskOffset,
      fillDataDrivenMask(flags),
      Endian.little,
    );
  }
}

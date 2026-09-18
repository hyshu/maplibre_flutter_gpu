part of '../uniform_packer.dart';

void _packEvaluatedUniforms({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required Uint8List destination,
  required ByteData destinationData,
  required int shader,
  required int flags,
  required int propsOffset,
  required int propsLength,
}) {
  final isLine = isLineShader(shader);
  if (isLine ||
      shader == ShaderType.circle ||
      shader == ShaderType.fillExtrusion ||
      shader == ShaderType.raster ||
      shader == ShaderType.backgroundPattern) {
    _copyEvaluatedProps(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      propsOffset: propsOffset,
      propsLength: propsLength,
    );
  } else {
    _packFillEvaluatedUniforms(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      destinationData: destinationData,
      shader: shader,
      propsOffset: propsOffset,
      propsLength: propsLength,
    );
  }

  if (shader == ShaderType.circle && circleUsesDataDrivenPipeline(flags)) {
    // Native circle padding carries the seven-property runtime mask.
    destinationData.setUint32(
      propsOffset + RendererUboAbi.circleDataDrivenMaskOffset,
      circleDataDrivenMask(flags),
      Endian.little,
    );
  } else if (isLine) {
    if (lineUsesDataDrivenPipeline(flags)) {
      // CPU evaluation leaves the native expression mask available for paint bits.
      destinationData.setUint32(
        propsOffset + RendererUboAbi.lineDataDrivenMaskOffset,
        lineDataDrivenMask(flags),
        Endian.little,
      );
    }
    // Defaults apply only to missing fields. Style values of zero stay zero.
    final exportedProps = _exportedPropsSize(sourceData, commandOffset);
    if (!rendererUboContainsFloat32(
      exportedProps,
      RendererUboAbi.lineOpacityOffset,
    )) {
      destinationData.setFloat32(
        propsOffset + RendererUboAbi.lineOpacityOffset,
        1.0,
        Endian.little,
      );
    }
    if (!rendererUboContainsFloat32(
      exportedProps,
      RendererUboAbi.lineWidthOffset,
    )) {
      destinationData.setFloat32(
        propsOffset + RendererUboAbi.lineWidthOffset,
        1.0,
        Endian.little,
      );
    }
  } else if (shader == ShaderType.fillOutlineTriangulated &&
      fillOutlineUsesDataDrivenPipeline(flags)) {
    // Unpatterned outlines reuse the native fade field for color and opacity bits.
    destinationData.setUint32(
      propsOffset + RendererUboAbi.fillOutlineDataDrivenMaskOffset,
      fillOutlineDataDrivenMask(flags),
      Endian.little,
    );
  }
}

void _packFillEvaluatedUniforms({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required Uint8List destination,
  required ByteData destinationData,
  required int shader,
  required int propsOffset,
  required int propsLength,
}) {
  // Fill, fill outline, and background props use the FillEvaluatedPropsUBO
  // layout. Background stores opacity at byte 16 and has no outline color.
  // Fill stores opacity at byte 32. Repack both into the fill layout.
  destination.fillRange(propsOffset, propsOffset + propsLength, 0);
  final exportedProps = _exportedPropsSize(sourceData, commandOffset);
  final isBackground = shader == ShaderType.background;
  final opacityOffset = isBackground
      ? RendererUboAbi.backgroundOpacityOffset
      : RendererUboAbi.fillOpacityOffset;
  if (rendererUboContainsFloat32(exportedProps, opacityOffset)) {
    destination.setRange(
      propsOffset + RendererUboAbi.fillColorOffset,
      propsOffset + RendererUboAbi.fillColorOffset + RendererUboAbi.vec4Bytes,
      source,
      commandOffset + DrawCommandAbi.propsUBO + RendererUboAbi.fillColorOffset,
    );
    if (!isBackground) {
      destination.setRange(
        propsOffset + RendererUboAbi.fillOutlineColorOffset,
        propsOffset +
            RendererUboAbi.fillOutlineColorOffset +
            RendererUboAbi.vec4Bytes,
        source,
        commandOffset +
            DrawCommandAbi.propsUBO +
            RendererUboAbi.fillOutlineColorOffset,
      );
    }
    destinationData.setFloat32(
      propsOffset + RendererUboAbi.fillOpacityOffset,
      sourceData.getFloat32(
        commandOffset + DrawCommandAbi.propsUBO + opacityOffset,
        Endian.little,
      ),
      Endian.little,
    );
  } else {
    for (
      var component = 0;
      component < RendererUboAbi.fillColorComponentCount;
      component += 1
    ) {
      final colorOffset =
          RendererUboAbi.fillColorOffset +
          component * RendererUboAbi.float32Bytes;
      destinationData.setFloat32(propsOffset + colorOffset, 1.0, Endian.little);
    }
    destinationData.setFloat32(
      propsOffset + RendererUboAbi.fillOpacityOffset,
      1.0,
      Endian.little,
    );
  }
}

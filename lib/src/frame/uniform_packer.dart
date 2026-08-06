// Packs one native DrawCommand's UBO bytes into the frame's uniform buffer.
//
// Each shader family has its own MapLibre UBO layout, and several of them
// carry renderer-only values in padding the native struct leaves unused. These
// values include the device pixel ratio, data-driven attribute masks, and
// pattern atlas dimensions.
// Getting one offset wrong corrupts a draw without any error, so the layout
// lives in ubo_abi.dart and the writes live here, apart from the frame loop.
import 'dart:typed_data';

import '../native/abi_generated.dart';
import '../native/draw_command.dart';
import 'draw_flags.dart';
import 'ubo_abi.dart';

/// Writes the drawable, evaluated-props, and tile-props ranges for one command.
///
/// [source]/[sourceData] are two views of the native command buffer and
/// [destination]/[destinationData] are two views of the frame's uniform bytes.
/// Each pair must address the same memory. The packer copies whole ranges
/// through the list view and patches individual fields through the byte view.
///
/// [textureWidth]/[textureHeight] are only read for `background-pattern`,
/// which carries its atlas size in drawable padding.
void packCommandUniforms({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required Uint8List destination,
  required ByteData destinationData,
  required int shader,
  required int flags,
  required int drawableOffset,
  required int drawableLength,
  required int propsOffset,
  required int propsLength,
  required int tilePropsOffset,
  required int tilePropsLength,
  required double devicePixelRatio,
  required int textureWidth,
  required int textureHeight,
}) {
  final isFECmd = shader == ShaderType.fillExtrusion;
  final isLineCmd = isLineShader(shader);
  final isCircleCmd = shader == ShaderType.circle;
  final isRasterCmd = shader == ShaderType.raster;
  final isBackgroundPatternCmd = shader == ShaderType.backgroundPattern;
  final isTriangulatedOutlineCmd = shader == ShaderType.fillOutlineTriangulated;
  destination.setRange(
    drawableOffset,
    drawableOffset + RendererUboAbi.drawableMatrixBytes,
    source,
    commandOffset + DrawCommandAbi.drawableUBO,
  ); // mat4 for all types
  if (shader == ShaderType.clippingMask) return;
  if (isBackgroundPatternCmd) {
    // Preserve MapLibre's 96-byte drawable and 64-byte props UBOs. The
    // native drawable padding at bytes 84/88 carries atlas dimensions to
    // the Flutter fragment shader in place of GlobalPaintParamsUBO.
    _copyDrawableTail(
      source: source,
      commandOffset: commandOffset,
      destination: destination,
      drawableOffset: drawableOffset,
      drawableLength: drawableLength,
    );
    _copyEvaluatedProps(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      propsOffset: propsOffset,
      propsLength: propsLength,
    );
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
  } else if (isRasterCmd) {
    // RasterDrawableUBO is just the matrix (already copied above).
    // RasterEvaluatedPropsUBO contains spin, tl_parent, scales, and opacity.
    _copyEvaluatedProps(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      propsOffset: propsOffset,
      propsLength: propsLength,
    );
  } else if (isCircleCmd) {
    // CircleDrawableUBO contains extrude_scale and interpolation padding.
    _copyDrawableTail(
      source: source,
      commandOffset: commandOffset,
      destination: destination,
      drawableOffset: drawableOffset,
      drawableLength: drawableLength,
    );
    // The circle shader reads camera distance from byte 100 and the device
    // pixel ratio from byte 104 for sizing and antialiasing.
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
    // CircleEvaluatedPropsUBO contains color, stroke, radius, blur, and opacity.
    _copyEvaluatedProps(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      propsOffset: propsOffset,
      propsLength: propsLength,
    );
    if (circleUsesDataDrivenPipeline(flags)) {
      // CircleEvaluatedPropsUBO::pad1 at byte 60 is unused natively.
      // Carry the seven-property runtime mask without changing the
      // MapLibre UBO or DrawCommand ABI.
      destinationData.setUint32(
        propsOffset + RendererUboAbi.circleDataDrivenMaskOffset,
        circleDataDrivenMask(flags),
        Endian.little,
      );
    }
  } else if (isFECmd) {
    _copyDrawableTail(
      source: source,
      commandOffset: commandOffset,
      destination: destination,
      drawableOffset: drawableOffset,
      drawableLength: drawableLength,
    );
    if (fillExtrusionUsesDataDrivenPipeline(flags)) {
      // Native FillExtrusionDrawableUBO::pad1 at byte 108 is unused by
      // this pipeline. Carry the color attribute mask without changing
      // the native UBO or DrawCommand ABI.
      destinationData.setUint32(
        drawableOffset + RendererUboAbi.fillExtrusionDataDrivenMaskOffset,
        fillExtrusionDataDrivenMask(flags),
        Endian.little,
      );
    }
    _copyEvaluatedProps(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      propsOffset: propsOffset,
      propsLength: propsLength,
    );
  } else if (isLineCmd) {
    // Copy the full drawable UBO as exported by the C++ tweaker
    // (LineDrawableUBO=96 / LineSDFDrawableUBO=128 / gradient/pattern=96)
    _copyDrawableTail(
      source: source,
      commandOffset: commandOffset,
      destination: destination,
      drawableOffset: drawableOffset,
      drawableLength: drawableLength,
    );
    // Line and gradient shaders read the device pixel ratio from byte 92. The
    // SDF shader reads it from byte 120. The pattern shader uses tileProps
    // scale.x, which C++ already fills with the pixel ratio.
    if (shader == ShaderType.line || shader == ShaderType.lineGradient) {
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
    }
    // Line props contain color, blur, opacity, gap width, offset, width, floor
    // width, and padding.
    _copyEvaluatedProps(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      propsOffset: propsOffset,
      propsLength: propsLength,
    );
    if (lineUsesDataDrivenPipeline(flags)) {
      // LineEvaluatedPropsUBO::expressionMask at byte 40 is unused by
      // this backend's CPU-evaluated fixed path. Carry the eight
      // per-vertex paint-property bits to the DD shaders.
      destinationData.setUint32(
        propsOffset + RendererUboAbi.lineDataDrivenMaskOffset,
        lineDataDrivenMask(flags),
        Endian.little,
      );
    }
    // Defaults apply only when the props UBO is too small to contain the field.
    // A real zero from the style must remain zero.
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
    // SDF tile props contain sdfgamma and mix. Pattern tile props contain from,
    // to, scale, texture size, and fade.
    _copyTileProps(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      tilePropsOffset: tilePropsOffset,
      tilePropsLength: tilePropsLength,
    );
  } else {
    final isDataDrivenFill =
        shader == ShaderType.fill && fillUsesDataDrivenPipeline(flags);
    final copiesDrawableTail = isDataDrivenFill || isTriangulatedOutlineCmd;
    if (copiesDrawableTail) {
      // Data-driven fill and triangulated-outline shaders consume fields
      // beyond the matrix, so preserve the complete native drawable UBO.
      _copyDrawableTail(
        source: source,
        commandOffset: commandOffset,
        destination: destination,
        drawableOffset: drawableOffset,
        drawableLength: drawableLength,
      );
      if (isDataDrivenFill) {
        // Replace otherwise-unused pad1 with the two-bit DD mask.
        destinationData.setUint32(
          drawableOffset + RendererUboAbi.fillDataDrivenMaskOffset,
          fillDataDrivenMask(flags),
          Endian.little,
        );
      }
    } else {
      // Fixed fill and background shaders read only the matrix. Keep the
      // remaining drawable range zeroed.
      destination.fillRange(
        drawableOffset + RendererUboAbi.drawableMatrixBytes,
        drawableOffset + drawableLength,
        0,
      );
    }
    if (isTriangulatedOutlineCmd) {
      // FillOutlineTriangulatedDrawableUBO::pad1 (byte 68) carries DPR.
      destinationData.setFloat32(
        drawableOffset + RendererUboAbi.fillOutlineDevicePixelRatioOffset,
        devicePixelRatio,
        Endian.little,
      );
    }
    // Fill, fill outline, and background props use the FillEvaluatedPropsUBO
    // layout. Background stores opacity at byte 16 and has no outline color.
    // Fill stores opacity at byte 32. Repack both into the fill layout.
    destination.fillRange(propsOffset, propsOffset + propsLength, 0);
    final exportedProps = _exportedPropsSize(sourceData, commandOffset);
    final isBg = shader == ShaderType.background;
    final opOff = isBg
        ? RendererUboAbi.backgroundOpacityOffset
        : RendererUboAbi.fillOpacityOffset;
    if (rendererUboContainsFloat32(exportedProps, opOff)) {
      destination.setRange(
        propsOffset + RendererUboAbi.fillColorOffset,
        propsOffset + RendererUboAbi.fillColorOffset + RendererUboAbi.vec4Bytes,
        source,
        commandOffset +
            DrawCommandAbi.propsUBO +
            RendererUboAbi.fillColorOffset,
      ); // color
      if (!isBg) {
        destination.setRange(
          propsOffset + RendererUboAbi.fillOutlineColorOffset,
          propsOffset +
              RendererUboAbi.fillOutlineColorOffset +
              RendererUboAbi.vec4Bytes,
          source,
          commandOffset +
              DrawCommandAbi.propsUBO +
              RendererUboAbi.fillOutlineColorOffset,
        ); // outline_color
      }
      destinationData.setFloat32(
        propsOffset + RendererUboAbi.fillOpacityOffset,
        sourceData.getFloat32(
          commandOffset + DrawCommandAbi.propsUBO + opOff,
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
        final off =
            RendererUboAbi.fillColorOffset +
            component * RendererUboAbi.float32Bytes;
        destinationData.setFloat32(propsOffset + off, 1.0, Endian.little);
      }
      destinationData.setFloat32(
        propsOffset + RendererUboAbi.fillOpacityOffset,
        1.0,
        Endian.little,
      );
    }
    if (isTriangulatedOutlineCmd && fillOutlineUsesDataDrivenPipeline(flags)) {
      // FillEvaluatedPropsUBO::fade is unused by unpatterned outlines.
      // Reinterpret its four bytes as the independent color/opacity mask
      // without changing MapLibre's native UBO or DrawCommand ABI.
      destinationData.setUint32(
        propsOffset + RendererUboAbi.fillOutlineDataDrivenMaskOffset,
        fillOutlineDataDrivenMask(flags),
        Endian.little,
      );
    }
  }
}

/// Returns the evaluated-props byte count reported by the command.
int _exportedPropsSize(ByteData sourceData, int commandOffset) => sourceData
    .getUint32(commandOffset + DrawCommandAbi.propsUBOSize, Endian.little);

/// Copies the drawable UBO past its leading mat4.
///
/// Every shader gets the matrix. Only layouts that add fields after it need
/// this helper. Copying `drawableLength` bytes for a matrix-only layout
/// would pull in unrelated command bytes.
void _copyDrawableTail({
  required Uint8List source,
  required int commandOffset,
  required Uint8List destination,
  required int drawableOffset,
  required int drawableLength,
}) => destination.setRange(
  drawableOffset + RendererUboAbi.drawableMatrixBytes,
  drawableOffset + drawableLength,
  source,
  commandOffset +
      DrawCommandAbi.drawableUBO +
      RendererUboAbi.drawableMatrixBytes,
);

/// Copies one embedded UBO, clamped to what the command actually exported.
///
/// The export can be shorter than the layout when native and Dart disagree on
/// a struct's size. Copying the layout length regardless would read past the
/// embedded buffer into the next field of the command. An exported size of
/// zero means the command carries no such UBO at all.
void _copyExportedUbo({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required int sizeField,
  required int dataField,
  required Uint8List destination,
  required int destinationOffset,
  required int destinationLength,
}) {
  if (destinationLength == 0) return;
  final exported = sourceData.getUint32(
    commandOffset + sizeField,
    Endian.little,
  );
  final length = exported < destinationLength ? exported : destinationLength;
  if (length > 0) {
    destination.setRange(
      destinationOffset,
      destinationOffset + length,
      source,
      commandOffset + dataField,
    );
  }
  if (length < destinationLength) {
    destination.fillRange(
      destinationOffset + length,
      destinationOffset + destinationLength,
      0,
    );
  }
}

/// Copies the evaluated-props UBO when the shader layout includes one.
void _copyEvaluatedProps({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required Uint8List destination,
  required int propsOffset,
  required int propsLength,
}) => _copyExportedUbo(
  source: source,
  sourceData: sourceData,
  commandOffset: commandOffset,
  sizeField: DrawCommandAbi.propsUBOSize,
  dataField: DrawCommandAbi.propsUBO,
  destination: destination,
  destinationOffset: propsOffset,
  destinationLength: propsLength,
);

/// Copies the tile-props UBO.
///
/// Only the SDF and pattern line variants have one. The others pass a zero
/// length and this is a no-op.
void _copyTileProps({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required Uint8List destination,
  required int tilePropsOffset,
  required int tilePropsLength,
}) => _copyExportedUbo(
  source: source,
  sourceData: sourceData,
  commandOffset: commandOffset,
  sizeField: DrawCommandAbi.tilePropsUBOSize,
  dataField: DrawCommandAbi.tilePropsUBO,
  destination: destination,
  destinationOffset: tilePropsOffset,
  destinationLength: tilePropsLength,
);

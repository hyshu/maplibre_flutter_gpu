// Packs one native DrawCommand's UBO bytes into the frame's uniform buffer.
//
// Each shader family has its own MapLibre UBO layout, and several of them
// carry renderer-only values in padding the native struct leaves unused. These
// values include the device pixel ratio, data-driven attribute masks, and
// pattern atlas dimensions.
// Layout offsets live in ubo_abi.dart. Packing is split by UBO range.
import 'dart:typed_data';

import '../native/abi_generated.dart';
import '../native/draw_command.dart';
import 'draw_flags.dart';
import 'ubo_abi.dart';

part 'uniforms/drawable_uniforms.dart';
part 'uniforms/evaluated_uniforms.dart';
part 'uniforms/ubo_copy.dart';

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
  destination.setRange(
    drawableOffset,
    drawableOffset + RendererUboAbi.drawableMatrixBytes,
    source,
    commandOffset + DrawCommandAbi.drawableUBO,
  );
  if (shader == ShaderType.clippingMask) return;

  _packDrawableUniforms(
    source: source,
    sourceData: sourceData,
    commandOffset: commandOffset,
    destination: destination,
    destinationData: destinationData,
    shader: shader,
    flags: flags,
    drawableOffset: drawableOffset,
    drawableLength: drawableLength,
    devicePixelRatio: devicePixelRatio,
    textureWidth: textureWidth,
    textureHeight: textureHeight,
  );
  _packEvaluatedUniforms(
    source: source,
    sourceData: sourceData,
    commandOffset: commandOffset,
    destination: destination,
    destinationData: destinationData,
    shader: shader,
    flags: flags,
    propsOffset: propsOffset,
    propsLength: propsLength,
  );
  if (isLineShader(shader)) {
    _copyTileProps(
      source: source,
      sourceData: sourceData,
      commandOffset: commandOffset,
      destination: destination,
      tilePropsOffset: tilePropsOffset,
      tilePropsLength: tilePropsLength,
    );
  }
}

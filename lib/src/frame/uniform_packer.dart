// Packs one native DrawCommand's UBO bytes into the frame's uniform buffer.
//
// Each shader family has its own MapLibre UBO layout, and several of them
// carry renderer-only values in padding the native struct leaves unused. These
// values include the device pixel ratio, data-driven attribute masks, and
// pattern atlas dimensions.
// Layout offsets live in ubo_abi.dart. Packing is split by UBO range.
import 'dart:typed_data';

import '../native/command_payload.dart';
import '../native/draw_command.dart';
import 'draw_flags.dart';
import 'ubo_abi.dart';

part 'uniforms/drawable_uniforms.dart';
part 'uniforms/evaluated_uniforms.dart';
part 'uniforms/ubo_copy.dart';

/// Writes the drawable, evaluated-props, and tile-props ranges for one command.
///
/// [payload] must have selected a valid command. [destination] and
/// [destinationData] address the same renderer-owned uniform bytes. Native
/// bytes are copied before the frame or snapshot lease is released.
///
/// [textureWidth]/[textureHeight] are only read for `background-pattern`,
/// which carries its atlas size in drawable padding.
void packCommandUniforms({
  required CommandPayloadReader payload,
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
  _copyExportedUbo(
    payload: payload,
    sourceOffset: payload.drawableOffset,
    exportedSize: payload.drawableSize,
    destination: destination,
    destinationOffset: drawableOffset,
    destinationLength: RendererUboAbi.drawableMatrixBytes,
  );
  if (shader == ShaderType.clippingMask) return;

  _packDrawableUniforms(
    payload: payload,
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
    payload: payload,
    destination: destination,
    destinationData: destinationData,
    shader: shader,
    flags: flags,
    propsOffset: propsOffset,
    propsLength: propsLength,
  );
  if (tilePropsLength > 0) {
    _copyTileProps(
      payload: payload,
      destination: destination,
      tilePropsOffset: tilePropsOffset,
      tilePropsLength: tilePropsLength,
    );
  }
}

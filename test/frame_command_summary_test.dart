import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/frame_command_summary.dart';

import 'support/compact_command.dart';

/// Builds a command buffer with the real ABI stride and offsets, so the test
/// exercises the same byte arithmetic the renderer's decode loop performs.
({Uint8List commands, Uint8List payload}) _buffer(
  List<({int shader, int stencilMode, int layerIndex})> commands,
) => combineTestCommands([
  for (final command in commands)
    TestCommand(drawableSize: 0, propsSize: 0)
      ..data.setUint32(DrawCommandAbi.shaderType, command.shader, .little)
      ..data.setUint32(DrawCommandAbi.layerIndex, command.layerIndex, .little)
      ..payloadData.setUint32(
        CommandPayloadHeaderAbi.size +
            CommandTextureAbi.size +
            CommandStencilAbi.mode,
        command.stencilMode,
        .little,
      ),
]);

FrameCommandSummary _summarize(
  ({Uint8List commands, Uint8List payload}) buffer,
  int count, {
  int? stride,
}) => summarizeFrameCommands(
  commands: buffer.commands,
  payload: buffer.payload,
  commandCount: count,
  commandStride: stride ?? DrawCommandAbi.size,
  shaderTypeOffset: DrawCommandAbi.shaderType,
  expectedStride: DrawCommandAbi.size,
);

void main() {
  test('groups commands by shader type and stencil mode', () {
    final buffer = _buffer([
      (
        shader: ShaderType.fill,
        stencilMode: StencilModeType.clippingTest,
        layerIndex: 1,
      ),
      (
        shader: ShaderType.fill,
        stencilMode: StencilModeType.clippingTest,
        layerIndex: 1,
      ),
      (
        shader: ShaderType.clippingMask,
        stencilMode: StencilModeType.clippingMask,
        layerIndex: 2,
      ),
      (
        shader: ShaderType.clippingMask,
        stencilMode: StencilModeType.clear,
        layerIndex: 2,
      ),
      (
        shader: ShaderType.raster,
        stencilMode: StencilModeType.disabled,
        layerIndex: 3,
      ),
    ]);

    final summary = _summarize(buffer, 5);

    expect(summary.commandCount, 5);
    expect(summary.countByShader[ShaderType.fill], 2);
    expect(summary.countByShader[ShaderType.clippingMask], 2);
    expect(summary.countByShader[ShaderType.raster], 1);
    expect(summary.countByShader[ShaderType.line], isNull);
    expect(summary.countByStencilMode[StencilModeType.clippingTest], 2);
    expect(summary.countByStencilMode[StencilModeType.clippingMask], 1);
    expect(summary.countByStencilMode[StencilModeType.clear], 1);
    expect(summary.countByStencilMode[StencilModeType.disabled], 1);
  });

  test('reads each record at its own stride', () {
    // A wrong stride would still produce counts, just of the wrong bytes. Use
    // distinct shaders per record so a misread lands on a different value.
    final buffer = _buffer([
      (
        shader: ShaderType.line,
        stencilMode: StencilModeType.disabled,
        layerIndex: 1,
      ),
      (
        shader: ShaderType.circle,
        stencilMode: StencilModeType.disabled,
        layerIndex: 2,
      ),
      (
        shader: ShaderType.background,
        stencilMode: StencilModeType.disabled,
        layerIndex: 3,
      ),
    ]);

    final summary = _summarize(buffer, 3);

    expect(summary.countByShader, <int, int>{
      ShaderType.line: 1,
      ShaderType.circle: 1,
      ShaderType.background: 1,
    });
  });

  test('an ABI stride mismatch summarizes nothing', () {
    final buffer = _buffer([
      (
        shader: ShaderType.fill,
        stencilMode: StencilModeType.disabled,
        layerIndex: 1,
      ),
    ]);

    final summary = _summarize(buffer, 1, stride: DrawCommandAbi.size - 4);

    expect(summary.commandCount, 0);
    expect(summary.countByShader, isEmpty);
  });

  test('a buffer shorter than the record count summarizes nothing', () {
    // Guards against reading past the mapped native buffer.
    final buffer = _buffer([
      (
        shader: ShaderType.fill,
        stencilMode: StencilModeType.disabled,
        layerIndex: 1,
      ),
    ]);

    expect(_summarize(buffer, 2).commandCount, 0);
  });

  test('an empty frame summarizes nothing', () {
    expect(_summarize(_buffer([]), 0).commandCount, 0);
    expect(_summarize(_buffer([]), -1).commandCount, 0);
  });

  test('collects distinct style layer indices', () {
    final buffer = _buffer([
      (
        shader: ShaderType.fill,
        stencilMode: StencilModeType.disabled,
        layerIndex: 7,
      ),
      (
        shader: ShaderType.line,
        stencilMode: StencilModeType.clippingTest,
        layerIndex: 3,
      ),
      (
        shader: ShaderType.raster,
        stencilMode: StencilModeType.disabled,
        layerIndex: 7,
      ),
    ]);

    expect(
      frameCommandLayerIndices(
        commands: buffer.commands,
        commandCount: 3,
        commandStride: DrawCommandAbi.size,
        layerIndexOffset: DrawCommandAbi.layerIndex,
        expectedStride: DrawCommandAbi.size,
      ),
      {3, 7},
    );
  });

  test('rejects invalid layer index metadata', () {
    final buffer = _buffer([
      (
        shader: ShaderType.fill,
        stencilMode: StencilModeType.disabled,
        layerIndex: 4,
      ),
    ]);

    expect(
      frameCommandLayerIndices(
        commands: buffer.commands,
        commandCount: 1,
        commandStride: DrawCommandAbi.size - 4,
        layerIndexOffset: DrawCommandAbi.layerIndex,
        expectedStride: DrawCommandAbi.size,
      ),
      isEmpty,
    );
    expect(
      frameCommandLayerIndices(
        commands: buffer.commands,
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
        layerIndexOffset: DrawCommandAbi.size - 2,
        expectedStride: DrawCommandAbi.size,
      ),
      isEmpty,
    );
  });
}

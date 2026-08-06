import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/frame_command_summary.dart';

/// Builds a command buffer with the real ABI stride and offsets, so the test
/// exercises the same byte arithmetic the renderer's decode loop performs.
Uint8List _buffer(List<({int shader, int stencilMode})> commands) {
  final bytes = Uint8List(commands.length * DrawCommandAbi.size);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < commands.length; i++) {
    final offset = i * DrawCommandAbi.size;
    data.setUint32(
      offset + DrawCommandAbi.shaderType,
      commands[i].shader,
      Endian.little,
    );
    data.setUint32(
      offset + DrawCommandAbi.stencilMode,
      commands[i].stencilMode,
      Endian.little,
    );
  }
  return bytes;
}

FrameCommandSummary _summarize(Uint8List buffer, int count, {int? stride}) =>
    summarizeFrameCommands(
      commands: buffer,
      commandCount: count,
      commandStride: stride ?? DrawCommandAbi.size,
      shaderTypeOffset: DrawCommandAbi.shaderType,
      stencilModeOffset: DrawCommandAbi.stencilMode,
      expectedStride: DrawCommandAbi.size,
    );

void main() {
  test('groups commands by shader type and stencil mode', () {
    final buffer = _buffer(<({int shader, int stencilMode})>[
      (shader: ShaderType.fill, stencilMode: StencilModeType.clippingTest),
      (shader: ShaderType.fill, stencilMode: StencilModeType.clippingTest),
      (
        shader: ShaderType.clippingMask,
        stencilMode: StencilModeType.clippingMask,
      ),
      (shader: ShaderType.clippingMask, stencilMode: StencilModeType.clear),
      (shader: ShaderType.raster, stencilMode: StencilModeType.disabled),
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
    final buffer = _buffer(<({int shader, int stencilMode})>[
      (shader: ShaderType.line, stencilMode: StencilModeType.disabled),
      (shader: ShaderType.circle, stencilMode: StencilModeType.disabled),
      (shader: ShaderType.background, stencilMode: StencilModeType.disabled),
    ]);

    final summary = _summarize(buffer, 3);

    expect(summary.countByShader, <int, int>{
      ShaderType.line: 1,
      ShaderType.circle: 1,
      ShaderType.background: 1,
    });
  });

  test('an ABI stride mismatch summarizes nothing', () {
    final buffer = _buffer(<({int shader, int stencilMode})>[
      (shader: ShaderType.fill, stencilMode: StencilModeType.disabled),
    ]);

    final summary = _summarize(buffer, 1, stride: DrawCommandAbi.size - 4);

    expect(summary.commandCount, 0);
    expect(summary.countByShader, isEmpty);
  });

  test('a buffer shorter than the record count summarizes nothing', () {
    // Guards against reading past the mapped native buffer.
    final buffer = _buffer(<({int shader, int stencilMode})>[
      (shader: ShaderType.fill, stencilMode: StencilModeType.disabled),
    ]);

    expect(_summarize(buffer, 2).commandCount, 0);
  });

  test('an empty frame summarizes nothing', () {
    expect(_summarize(Uint8List(0), 0).commandCount, 0);
    expect(_summarize(Uint8List(0), -1).commandCount, 0);
  });
}

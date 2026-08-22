import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('constant line shaders consume packed LineLayoutVertex', () {
    for (final path in <String>[
      'shaders/line.vert',
      'shaders/line_sdf.vert',
      'shaders/line_gradient.vert',
      'shaders/line_pattern.vert',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('layout(location = 0) in uvec2 a_layout_packed;'));
      expect(source, contains('vec2 unpack_short2(uint packed)'));
      expect(source, contains('vec4 unpack_u8x4(uint packed)'));
      expect(source, contains('vec2 a_pos_normal = unpack_short2('));
      expect(source, contains('vec4 a_data = unpack_u8x4('));
    }
  });

  test('constant line GPU stride is packed while DD stays normalized', () {
    for (final shader in <int>[
      ShaderType.line,
      ShaderType.lineSDF,
      ShaderType.lineGradient,
      ShaderType.linePattern,
    ]) {
      expect(gpuVertexStride(shader, 0), 8);
      expect(gpuVertexStride(shader, DrawCommandFlags.lineGpuReady), 8);
      expect(
        gpuVertexStride(shader, DrawCommandFlags.lineColorDataDriven),
        120,
      );
    }
  });
}

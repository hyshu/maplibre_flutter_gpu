import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('constant line shaders consume expanded LineLayoutVertex', () {
    for (final path in [
      'shaders/line.vert',
      'shaders/line_sdf.vert',
      'shaders/line_gradient.vert',
      'shaders/line_pattern.vert',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('layout(location = 0) in vec2 a_pos_normal;'));
      expect(source, contains('layout(location = 1) in vec4 a_data;'));
      expect(source, isNot(contains('floatBitsToUint')));
    }
  });

  test('constant and DD line GPU strides use numeric floats', () {
    for (final shader in [
      ShaderType.line,
      ShaderType.lineSDF,
      ShaderType.lineGradient,
      ShaderType.linePattern,
    ]) {
      expect(gpuVertexStride(shader, 0), 24);
      expect(gpuVertexStride(shader, DrawCommandFlags.lineGpuReady), 24);
      expect(
        gpuVertexStride(shader, DrawCommandFlags.lineColorDataDriven),
        120,
      );
    }
  });
}

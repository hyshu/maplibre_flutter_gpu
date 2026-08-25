import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('packed fill layouts expand for GPU upload', () {
    for (final spec in <({int stride, int flags})>[
      (stride: 4, flags: 0),
      (stride: 28, flags: DrawCommandFlags.fillColorDataDriven),
    ]) {
      final source = Uint8List(spec.stride * 2);
      for (var index = 0; index < source.length; index += 1) {
        source[index] = (index * 37) & 0xff;
      }

      final result = repackVertexDataForGpu(
        source,
        vertexCount: 2,
        sourceStride: spec.stride,
        shader: ShaderType.fill,
        flags: spec.flags,
      );

      expect(identical(result, source), isFalse);
      expect(
        result.lengthInBytes,
        gpuVertexStride(ShaderType.fill, spec.flags) * 2,
      );
    }
  });

  test('packed triangulated outline layouts expand for GPU upload', () {
    for (final spec in <({int stride, int flags})>[
      (stride: 8, flags: 0),
      (stride: 32, flags: DrawCommandFlags.fillOutlineColorDataDriven),
    ]) {
      final source = Uint8List(spec.stride * 2);
      for (var index = 0; index < source.length; index += 1) {
        source[index] = (index * 53) & 0xff;
      }

      final result = repackVertexDataForGpu(
        source,
        vertexCount: 2,
        sourceStride: spec.stride,
        shader: ShaderType.fillOutlineTriangulated,
        flags: spec.flags,
      );

      expect(identical(result, source), isFalse);
      expect(
        result.lengthInBytes,
        gpuVertexStride(ShaderType.fillOutlineTriangulated, spec.flags) * 2,
      );
    }
  });
}

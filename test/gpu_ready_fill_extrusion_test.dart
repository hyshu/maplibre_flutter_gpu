import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/source_files.dart';

void main() {
  test('packed fill extrusion bypasses Dart repacking', () {
    final constant = Uint8List(12);
    final packedDd = Uint8List(44);

    final constantResult = repackVertexDataForGpu(
      constant,
      vertexCount: 1,
      sourceStride: 12,
      shader: ShaderType.fillExtrusion,
      flags: 0,
    );
    final ddResult = repackVertexDataForGpu(
      packedDd,
      vertexCount: 1,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      flags: DrawCommandFlags.fillExtrusionDataDriven,
    );

    expect(identical(constantResult, constant), isTrue);
    expect(identical(ddResult, packedDd), isTrue);
    expect(gpuVertexStride(ShaderType.fillExtrusion, 0), 12);
    expect(
      gpuVertexStride(
        ShaderType.fillExtrusion,
        DrawCommandFlags.fillExtrusionDataDriven,
      ),
      44,
    );
  });

  test('legacy GPU-ready data-driven extrusion remains compatible', () {
    final source = Uint8List(56);
    final data = ByteData.sublistView(source);
    for (var index = 0; index < 14; index += 1) {
      data.setFloat32(index * 4, index + 0.5, Endian.little);
    }

    const flags =
        DrawCommandFlags.fillExtrusionDataDriven |
        DrawCommandFlags.fillExtrusionGpuReady;
    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 56,
      shader: ShaderType.fillExtrusion,
      flags: flags,
    );

    expect(identical(result, source), isTrue);
    expect(gpuVertexStride(ShaderType.fillExtrusion, flags), 56);
  });

  test('native bridge leaves fill extrusion packed', () {
    final source = SourceFiles.bridgeMergeOnly;

    expect(
      source,
      isNot(contains('\n    prepareFillExtrusionGpuVertices(commands);')),
    );
    expect(source, contains('prepareLineGpuVertices(commands);'));
    expect(
      source,
      contains('Fill-extrusion stays in Command Export\'s packed 12/44-byte layout'),
    );
  });
}

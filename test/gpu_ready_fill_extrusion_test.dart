import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/source_files.dart';

void main() {
  test('GPU-ready data-driven extrusion bypasses Dart repacking', () {
    final source = Uint8List(56);
    final data = ByteData.sublistView(source);
    for (var index = 0; index < 14; index += 1) {
      data.setFloat32(index * 4, index + 0.5, Endian.little);
    }

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 56,
      shader: ShaderType.fillExtrusion,
      flags:
          DrawCommandFlags.fillExtrusionDataDriven |
          DrawCommandFlags.fillExtrusionGpuReady,
    );

    expect(identical(result, source), isTrue);
    expect(result, orderedEquals(source));
  });

  test('packed data-driven extrusion keeps the legacy Dart repack path', () {
    expect(
      fillExtrusionVertexStride(DrawCommandFlags.fillExtrusionDataDriven),
      44,
    );
    expect(
      gpuVertexStride(
        ShaderType.fillExtrusion,
        DrawCommandFlags.fillExtrusionDataDriven,
      ),
      56,
    );
  });

  test('native bridge publishes DD extrusion after GPU expansion', () {
    final source = SourceFiles.bridgeMergeOnly;
    final prepare = source.indexOf('prepareFillExtrusionGpuVertices(commands);');
    final earlyReturn = source.indexOf('if (commands.size() <= 1) return;');

    expect(source, contains('kFillExtrusionPackedStride = 44'));
    expect(source, contains('kFillExtrusionGpuStride = 56'));
    expect(source, contains('kFillExtrusionGpuReadyFlag = 1u << 24'));
    expect(
      source,
      contains('command.vertexStride = kFillExtrusionGpuStride;'),
    );
    expect(source, contains('command.flags |= kFillExtrusionGpuReadyFlag;'));
    expect(prepare, greaterThanOrEqualTo(0));
    expect(earlyReturn, greaterThan(prepare));
  });
}

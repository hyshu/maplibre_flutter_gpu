import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/command_layout.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/source_files.dart';

void main() {
  test('GPU-ready constant line bypasses Dart repacking', () {
    final source = Uint8List(24);
    final data = ByteData.sublistView(source);
    for (var index = 0; index < 6; index += 1) {
      data.setFloat32(index * 4, index + 0.25, Endian.little);
    }

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 24,
      shader: ShaderType.line,
      flags: DrawCommandFlags.lineGpuReady,
    );

    expect(identical(result, source), isTrue);
    expect(result, orderedEquals(source));
  });

  test('GPU-ready data-driven line bypasses Dart repacking', () {
    final source = Uint8List(120);
    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 120,
      shader: ShaderType.lineSDF,
      flags:
          DrawCommandFlags.lineColorDataDriven |
          DrawCommandFlags.lineGpuReady,
    );

    expect(identical(result, source), isTrue);
  });

  test('packed line layouts keep the legacy Dart repack path', () {
    expect(lineVertexStride(0), 8);
    expect(gpuVertexStride(ShaderType.line, 0), 24);
    expect(lineVertexStride(DrawCommandFlags.lineColorDataDriven), 88);
    expect(
      gpuVertexStride(ShaderType.line, DrawCommandFlags.lineColorDataDriven),
      120,
    );
  });

  test('GPU-ready line strides are accepted as native command layouts', () {
    expect(
      nativeVertexStride(
        shader: ShaderType.line,
        flags: DrawCommandFlags.lineGpuReady,
        merged: false,
      ),
      24,
    );
    const ddFlags =
        DrawCommandFlags.lineColorDataDriven | DrawCommandFlags.lineGpuReady;
    expect(
      nativeVertexStride(
        shader: ShaderType.linePattern,
        flags: ddFlags,
        merged: false,
      ),
      120,
    );
  });

  test('native bridge publishes line vertices after GPU expansion', () {
    final source = SourceFiles.bridgeMergeOnly;
    final prepare = source.indexOf('prepareLineGpuVertices(commands);');
    final earlyReturn = source.indexOf('if (commands.size() <= 1) return;');

    expect(source, contains('kLinePackedStride = 8'));
    expect(source, contains('kLineDataDrivenPackedStride = 88'));
    expect(source, contains('kLineGpuStride = 24'));
    expect(source, contains('kLineDataDrivenGpuStride = 120'));
    expect(source, contains('kLineGpuReadyFlag = 1u << 25'));
    expect(source, contains('std::memcpy(dst + 24, src + 8, 64);'));
    expect(source, contains('std::memcpy(dst + 88, pattern, sizeof(pattern));'));
    expect(source, contains('command.flags |= kLineGpuReadyFlag;'));
    expect(prepare, greaterThanOrEqualTo(0));
    expect(earlyReturn, greaterThan(prepare));
  });
}

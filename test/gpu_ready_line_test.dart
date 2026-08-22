import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/command_layout.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/source_files.dart';

void main() {
  test('packed constant line bypasses Dart repacking', () {
    final source = Uint8List(8);
    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 8,
      shader: ShaderType.line,
      flags: 0,
    );

    expect(identical(result, source), isTrue);
    expect(gpuVertexStride(ShaderType.line, 0), 8);
  });

  test('legacy GPU-ready constant line packs back to native 8-byte layout', () {
    final source = Uint8List(24);
    final data = ByteData.sublistView(source);
    data
      ..setFloat32(0, -17, Endian.little)
      ..setFloat32(4, 42, Endian.little)
      ..setFloat32(8, 1, Endian.little)
      ..setFloat32(12, 127, Endian.little)
      ..setFloat32(16, 200, Endian.little)
      ..setFloat32(20, 255, Endian.little);

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 24,
      shader: ShaderType.line,
      flags: DrawCommandFlags.lineGpuReady,
    );
    final packed = ByteData.sublistView(result);

    expect(result.lengthInBytes, 8);
    expect(packed.getInt16(0, Endian.little), -17);
    expect(packed.getInt16(2, Endian.little), 42);
    expect(result.sublist(4), [1, 127, 200, 255]);
  });

  test('GPU-ready data-driven line keeps the 120-byte path', () {
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
    expect(
      gpuVertexStride(
        ShaderType.lineSDF,
        DrawCommandFlags.lineColorDataDriven | DrawCommandFlags.lineGpuReady,
      ),
      120,
    );
  });

  test('packed DD line remains a valid 88-to-120 repack source', () {
    expect(lineVertexStride(DrawCommandFlags.lineColorDataDriven), 88);
    expect(
      gpuVertexStride(ShaderType.line, DrawCommandFlags.lineColorDataDriven),
      120,
    );
  });

  test('GPU-ready line strides remain accepted as native command layouts', () {
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

  test('native bridge still expands line vertices in this compatibility stage', () {
    final source = SourceFiles.bridgeMergeOnly;
    final prepare = source.indexOf('prepareLineGpuVertices(commands);');
    final earlyReturn = source.indexOf('if (commands.size() <= 1) return;');

    expect(source, contains('kLinePackedStride = 8'));
    expect(source, contains('kLineDataDrivenPackedStride = 88'));
    expect(source, contains('kLineGpuStride = 24'));
    expect(source, contains('kLineDataDrivenGpuStride = 120'));
    expect(source, contains('kLineGpuReadyFlag = 1u << 25'));
    expect(source, contains('command.flags |= kLineGpuReadyFlag;'));
    expect(prepare, greaterThanOrEqualTo(0));
    expect(earlyReturn, greaterThan(prepare));
  });
}

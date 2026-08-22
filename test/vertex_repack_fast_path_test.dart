import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('fill fast path expands short2 and preserves DD payload words', () {
    final source = Uint8List(56);
    final input = ByteData.sublistView(source);
    for (var vertex = 0; vertex < 2; vertex += 1) {
      final offset = vertex * 28;
      input
        ..setInt16(offset, -300 - vertex, Endian.little)
        ..setInt16(offset + 2, 700 + vertex, Endian.little);
      for (var payload = 4; payload < 28; payload += 4) {
        input.setUint32(
          offset + payload,
          0x10203040 + vertex * 0x100 + payload,
          Endian.little,
        );
      }
    }

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 2,
      sourceStride: 28,
      shader: ShaderType.fill,
      flags: DrawCommandFlags.fillColorDataDriven,
    );
    final output = ByteData.sublistView(result);

    expect(result.lengthInBytes, 64);
    expect(output.getFloat32(0, Endian.little), -300.0);
    expect(output.getFloat32(4, Endian.little), 700.0);
    expect(result.sublist(8, 32), orderedEquals(source.sublist(4, 28)));
    expect(output.getFloat32(32, Endian.little), -301.0);
    expect(output.getFloat32(36, Endian.little), 701.0);
    expect(result.sublist(40, 64), orderedEquals(source.sublist(32, 56)));
  });

  test('triangulated outline fast path preserves uchar4 and DD payload', () {
    final source = Uint8List(64);
    final input = ByteData.sublistView(source);
    for (var vertex = 0; vertex < 2; vertex += 1) {
      final offset = vertex * 32;
      input
        ..setInt16(offset, -40 - vertex, Endian.little)
        ..setInt16(offset + 2, 80 + vertex, Endian.little)
        ..setUint8(offset + 4, 1 + vertex)
        ..setUint8(offset + 5, 127 + vertex)
        ..setUint8(offset + 6, 200 + vertex)
        ..setUint8(offset + 7, 250 - vertex);
      for (var payload = 8; payload < 32; payload += 4) {
        input.setUint32(
          offset + payload,
          0x50607080 + vertex * 0x100 + payload,
          Endian.little,
        );
      }
    }

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 2,
      sourceStride: 32,
      shader: ShaderType.fillOutlineTriangulated,
      flags: DrawCommandFlags.fillOutlineColorDataDriven,
    );
    final output = ByteData.sublistView(result);

    expect(result.lengthInBytes, 96);
    expect(
      [for (var offset = 0; offset < 24; offset += 4)
        output.getFloat32(offset, Endian.little)],
      [-40.0, 80.0, 1.0, 127.0, 200.0, 250.0],
    );
    expect(result.sublist(24, 48), orderedEquals(source.sublist(8, 32)));
    expect(
      [for (var offset = 48; offset < 72; offset += 4)
        output.getFloat32(offset, Endian.little)],
      [-41.0, 81.0, 2.0, 128.0, 201.0, 249.0],
    );
    expect(result.sublist(72, 96), orderedEquals(source.sublist(40, 64)));
  });
}

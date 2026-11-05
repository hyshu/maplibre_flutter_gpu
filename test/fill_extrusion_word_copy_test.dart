import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

Uint8List _referenceExtrusions(Uint8List source, int count) {
  final input = ByteData.sublistView(source);
  final result = Uint8List(count * 56);
  final output = ByteData.sublistView(result);
  for (var vertex = 0; vertex < count; vertex++) {
    for (var field = 0; field < 6; field++) {
      final offset = vertex * 44 + field * 2;
      final value = field == 2 || field == 3
          ? input.getUint16(offset, Endian.little)
          : input.getInt16(offset, Endian.little);
      output.setFloat32(
        vertex * 56 + field * 4,
        value.toDouble(),
        Endian.little,
      );
    }
    for (var byte = 0; byte < 32; byte++) {
      output.setUint8(
        vertex * 56 + 24 + byte,
        input.getUint8(vertex * 44 + 12 + byte),
      );
    }
  }
  return result;
}

Uint8List _extrusionSource(int count, int offset) {
  final storage = Uint8List(offset + count * 44 + 5)
    ..fillRange(0, offset, 0xaa);
  final source = Uint8List.sublistView(storage, offset, offset + count * 44);
  final data = ByteData.sublistView(source);
  const signedValues = [-32768, -1, 0, 1, 32767];
  const unsignedValues = [0, 1, 32767, 32768, 65535];
  const paintWords = [
    0x7fc12345,
    0x80000000,
    0xff800000,
    0xffffffff,
    0x00000001,
    0x7f800000,
    0x3f800000,
    0x00000000,
  ];
  for (var vertex = 0; vertex < count; vertex++) {
    for (var field = 0; field < 6; field++) {
      final fieldOffset = vertex * 44 + field * 2;
      if (field == 2 || field == 3) {
        data.setUint16(
          fieldOffset,
          unsignedValues[(vertex + field) % unsignedValues.length],
          Endian.little,
        );
      } else {
        data.setInt16(
          fieldOffset,
          signedValues[(vertex + field) % signedValues.length],
          Endian.little,
        );
      }
    }
    for (var word = 0; word < 8; word++) {
      data.setUint32(
        vertex * 44 + 12 + word * 4,
        paintWords[(vertex + word) % paintWords.length],
        Endian.little,
      );
    }
  }
  return source;
}

void main() {
  test('staged extrusion preserves numeric fields and opaque paint bits', () {
    for (var offset = 0; offset <= 4; offset++) {
      for (final count in [0, 1, 7, 257]) {
        final source = _extrusionSource(count, offset);
        final sourceBefore = Uint8List.fromList(source);
        final expected = _referenceExtrusions(source, count);
        final scratch = VertexRepackScratch(maxRetainedBytes: count * 56 + 1);
        Uint8List convert({VertexRepackScratch? staging}) =>
            repackVertexDataForGpu(
              source,
              vertexCount: count,
              sourceStride: 44,
              shader: ShaderType.fillExtrusion,
              flags: DrawCommandFlags.fillExtrusionDataDriven,
              scratch: staging,
            );

        final owned = convert();
        final staged = convert(staging: scratch);
        expect(owned, orderedEquals(expected));
        expect(
          staged,
          orderedEquals(expected),
          reason: 'source offset $offset with $count vertices',
        );
        staged.fillRange(0, staged.length, 0xff);
        expect(convert(staging: scratch), orderedEquals(expected));
        expect(owned, orderedEquals(expected));
        expect(source, orderedEquals(sourceBefore));
      }
    }
  });

  test('oversize staged extrusion keeps independent output ownership', () {
    final scratch = VertexRepackScratch(maxRetainedBytes: 57);
    final source = _extrusionSource(7, 0);
    Uint8List convert() => repackVertexDataForGpu(
      source,
      vertexCount: 7,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      flags: DrawCommandFlags.fillExtrusionDataDriven,
      scratch: scratch,
    );
    final first = convert();
    final expected = _referenceExtrusions(source, 7);
    source.fillRange(0, source.length, 0);
    final second = convert();
    expect(first, orderedEquals(expected));
    expect(second, everyElement(0));
    expect(scratch.retainedBytes, 0);
  });
}

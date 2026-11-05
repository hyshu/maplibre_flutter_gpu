import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('explicit destinations preserve surrounding bytes for every layout', () {
    const layouts = [
      (ShaderType.fillExtrusion, 12, 0),
      (ShaderType.fillExtrusion, 44, DrawCommandFlags.fillExtrusionDataDriven),
      (ShaderType.line, 8, 0),
      (ShaderType.linePattern, 88, DrawCommandFlags.lineColorDataDriven),
      (ShaderType.fill, 28, DrawCommandFlags.fillColorDataDriven),
      (ShaderType.fillOutlineTriangulated, 8, 0),
      (
        ShaderType.fillOutlineTriangulated,
        32,
        DrawCommandFlags.fillOutlineColorDataDriven,
      ),
      (ShaderType.raster, 8, 0),
    ];
    for (final (shader, stride, flags) in layouts) {
      for (final sourceOffset in [0, 1]) {
        final sourceStorage = Uint8List(stride * 3 + sourceOffset);
        final source = Uint8List.sublistView(sourceStorage, sourceOffset);
        for (var index = 0; index < source.length; index++) {
          source[index] = (index * 53 + 17) & 255;
        }
        Uint8List convert({Uint8List? destination}) => repackVertexDataForGpu(
          source,
          vertexCount: 3,
          sourceStride: stride,
          shader: shader,
          flags: flags,
          destination: destination,
        );
        final expected = convert();
        final storage = Uint8List(expected.length + 9)
          ..fillRange(0, expected.length + 9, 0xa5);
        final destination = Uint8List.sublistView(
          storage,
          4,
          storage.length - 1,
        );
        final result = convert(destination: destination);
        expect(result, orderedEquals(expected));
        expect(result.buffer, storage.buffer);
        expect(result.offsetInBytes, 4);
        expect(storage.sublist(0, 4), everyElement(0xa5));
        expect(storage.sublist(expected.length + 4), everyElement(0xa5));
      }
    }
  });

  test(
    'explicit destination rejects overlap, misalignment and short spans',
    () {
      final storage = Uint8List(100)..fillRange(0, 100, 7);
      final source = Uint8List.sublistView(storage, 0, 44);
      Uint8List convert(
        Uint8List destination, {
        VertexRepackScratch? scratch,
      }) => repackVertexDataForGpu(
        source,
        vertexCount: 1,
        sourceStride: 44,
        shader: ShaderType.fillExtrusion,
        flags: DrawCommandFlags.fillExtrusionDataDriven,
        destination: destination,
        scratch: scratch,
      );
      final before = Uint8List.fromList(storage);
      expect(
        () => convert(Uint8List.sublistView(storage, 4, 60)),
        throwsArgumentError,
      );
      expect(
        () => convert(Uint8List.sublistView(Uint8List(57), 1)),
        throwsArgumentError,
      );
      expect(() => convert(Uint8List(55)), throwsArgumentError);
      expect(
        () => convert(Uint8List(56), scratch: VertexRepackScratch()),
        throwsArgumentError,
      );
      expect(storage, orderedEquals(before));
      final output = convert(Uint8List.sublistView(storage, 44));
      expect(output.length, 56);
      expect(source, orderedEquals(before.sublist(0, 44)));
    },
  );
}

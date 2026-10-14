import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/geo/clip_space.dart';
import 'package:vector_math/vector_math_64.dart';

double _depth(Float32List matrix, double distance) =>
    (matrix[14] - matrix[10] * distance) / (matrix[15] - matrix[11] * distance);

void main() {
  for (final (near, far) in [(20.6, 479.0), (1.0, 10000.0), (100.0, 101.0)]) {
    test('preserves perspective clipping planes at $near and $far', () {
      final matrix = Float32List.fromList(
        makePerspectiveMatrix(0.65, 1.8, near, far).storage,
      );
      final oldZeroDepth = 2 * near * far / (near + far);
      expect(_depth(matrix, near), closeTo(-1, 1e-5));
      expect(_depth(matrix, oldZeroDepth), closeTo(0, 1e-5));

      convertOpenGlToFlutterGpuDepth(ByteData.sublistView(matrix));

      expect(_depth(matrix, near), closeTo(0, 1e-5));
      expect(_depth(matrix, far), closeTo(1, 1e-5));
      expect(_depth(matrix, oldZeroDepth), closeTo(0.5, 1e-5));
      expect(_depth(matrix, near * 0.99), lessThan(0));
      expect(_depth(matrix, far * 1.01), greaterThan(1));
    });
  }

  test('maps orthographic depth without moving screen coordinates', () {
    final matrix = Float32List.fromList(
      makeOrthographicMatrix(-4, 4, -3, 3, 2, 20).storage,
    );
    final original = Float32List.fromList(matrix);

    convertOpenGlToFlutterGpuDepth(ByteData.sublistView(matrix));

    expect(_depth(matrix, 2), closeTo(0, 1e-7));
    expect(_depth(matrix, 11), closeTo(0.5, 1e-7));
    expect(_depth(matrix, 20), closeTo(1, 1e-7));
    for (var i = 0; i < 16; i++) {
      if (i % 4 == 2) continue;
      expect(matrix[i], original[i]);
    }
  });

  test('converts a rotated camera matrix inside a larger buffer', () {
    final projection = makePerspectiveMatrix(0.65, 1.8, 2, 200);
    final view = makeViewMatrix(
      Vector3(10, 20, 30),
      Vector3(2, 4, 1),
      Vector3(0, 0, 1),
    );
    final matrix = projection * view;
    const offset = 32;
    final bytes = Uint8List(offset + 64 + 16)..fillRange(0, offset + 80, 0xab);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < 16; i++) {
      data.setFloat32(offset + i * 4, matrix.storage[i], Endian.little);
    }
    final original = Uint8List.fromList(bytes);
    final point = Vector4(2, 4, 1, 1);
    final before = matrix.transformed(point);

    convertOpenGlToFlutterGpuDepth(data, offsetInBytes: offset);

    final corrected = Matrix4.fromList([
      for (var i = 0; i < 16; i++)
        data.getFloat32(offset + i * 4, Endian.little),
    ]).transformed(point);
    expect(
      corrected.z / corrected.w,
      closeTo((before.z / before.w + 1) / 2, 1e-6),
    );
    expect(corrected.x / corrected.w, closeTo(before.x / before.w, 1e-6));
    expect(corrected.y / corrected.w, closeTo(before.y / before.w, 1e-6));
    expect(corrected.w, closeTo(before.w, 1e-5));
    for (var i = 0; i < bytes.length; i++) {
      final relative = i - offset;
      if (relative >= 0 &&
          relative < 64 &&
          relative % 16 >= 8 &&
          relative % 16 < 12) {
        continue;
      }
      expect(bytes[i], original[i], reason: 'byte $i');
    }
  });
}

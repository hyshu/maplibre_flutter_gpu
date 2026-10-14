import 'dart:typed_data';

/// Converts a column-major OpenGL matrix to Flutter GPU clip depth in place.
///
/// [data] contains 16 little-endian float32 values at [offsetInBytes]. Apply
/// this once to an owned copy of the OpenGL matrix. The Z row becomes half
/// the sum of the Z and W rows, mapping clip depth from `[-w, w]` to `[0, w]`.
/// X, Y, and W remain unchanged.
void convertOpenGlToFlutterGpuDepth(ByteData data, {int offsetInBytes = 0}) {
  for (var column = 0; column < 4; column++) {
    final zOffset = offsetInBytes + column * 16 + 8;
    final z = data.getFloat32(zOffset, Endian.little);
    final w = data.getFloat32(zOffset + 4, Endian.little);
    data.setFloat32(zOffset, (z + w) * 0.5, Endian.little);
  }
}

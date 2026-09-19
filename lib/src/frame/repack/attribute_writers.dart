part of '../vertex_repack.dart';

void _writeShortsAsFloats(
  ByteData source,
  int sourceOffset,
  ByteData target,
  int targetOffset,
  int count,
) {
  for (var index = 0; index < count; index += 1) {
    target.setFloat32(
      targetOffset + index * 4,
      source.getInt16(sourceOffset + index * 2, Endian.little).toDouble(),
      Endian.little,
    );
  }
}

void _writeBytesAsFloats(
  ByteData source,
  int sourceOffset,
  ByteData target,
  int targetOffset,
  int count,
) {
  for (var index = 0; index < count; index += 1) {
    target.setFloat32(
      targetOffset + index * 4,
      source.getUint8(sourceOffset + index).toDouble(),
      Endian.little,
    );
  }
}

void _writeUnsignedShortsAsFloats(
  ByteData source,
  int sourceOffset,
  ByteData target,
  int targetOffset,
  int count,
) {
  for (var index = 0; index < count; index += 1) {
    target.setFloat32(
      targetOffset + index * 4,
      source.getUint16(sourceOffset + index * 2, Endian.little).toDouble(),
      Endian.little,
    );
  }
}

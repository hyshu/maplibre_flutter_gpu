part of '../vertex_repack.dart';

Uint8List _repackLineVertices(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int targetStride,
  required Uint8List target,
}) {
  final sourceData = ByteData.sublistView(
    source,
    0,
    vertexCount * sourceStride,
  );
  final targetData = ByteData.sublistView(target);
  if (sourceStride == 8 && targetStride == 12) {
    return _packLineBytesAsFloats(
      source,
      vertexCount: vertexCount,
      target: target,
    );
  }
  for (var vertex = 0; vertex < vertexCount; vertex += 1) {
    final sourceOffset = vertex * sourceStride;
    final targetOffset = vertex * targetStride;
    _writeShortsAsFloats(sourceData, sourceOffset, targetData, targetOffset, 2);
    _writeBytesAsFloats(
      sourceData,
      sourceOffset + 4,
      targetData,
      targetOffset + 8,
      4,
    );

    if (sourceStride > 8) {
      target.setRange(
        targetOffset + 24,
        targetOffset + 88,
        source,
        sourceOffset + 8,
      );
      _writeUnsignedShortsAsFloats(
        sourceData,
        sourceOffset + 72,
        targetData,
        targetOffset + 88,
        4,
      );
      _writeUnsignedShortsAsFloats(
        sourceData,
        sourceOffset + 80,
        targetData,
        targetOffset + 104,
        4,
      );
    }
  }
  return target;
}

Uint8List _packLineBytesAsFloats(
  Uint8List source, {
  required int vertexCount,
  required Uint8List target,
}) {
  final targetData = ByteData.sublistView(target);
  for (var vertex = 0; vertex < vertexCount; vertex += 1) {
    final offset = vertex * 8;
    final output = vertex * 12;
    targetData.setFloat32(
      output,
      (source[offset] | source[offset + 1] << 8 | source[offset + 2] << 16)
          .toDouble(),
      Endian.little,
    );
    targetData.setFloat32(
      output + 4,
      (source[offset + 3] | source[offset + 4] << 8 | source[offset + 5] << 16)
          .toDouble(),
      Endian.little,
    );
    targetData.setFloat32(
      output + 8,
      (source[offset + 6] | source[offset + 7] << 8).toDouble(),
      Endian.little,
    );
  }
  return target;
}

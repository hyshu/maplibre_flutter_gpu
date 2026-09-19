part of '../vertex_repack.dart';

Uint8List _repackLineVertices(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int targetStride,
}) {
  final target = Uint8List(vertexCount * targetStride);
  final sourceData = ByteData.sublistView(
    source,
    0,
    vertexCount * sourceStride,
  );
  final targetData = ByteData.sublistView(target);
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

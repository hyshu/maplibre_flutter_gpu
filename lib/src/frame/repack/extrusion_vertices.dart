part of '../vertex_repack.dart';

Uint8List _repackFillExtrusionVertices(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int targetStride,
}) {
  final target = Uint8List(vertexCount * targetStride);
  if (vertexCount == 0) return target;

  if (Endian.host == Endian.little && source.offsetInBytes.isEven) {
    final sourceLength = vertexCount * sourceStride;
    final signed = Int16List.view(
      source.buffer,
      source.offsetInBytes,
      sourceLength ~/ 2,
    );
    final unsigned = Uint16List.view(
      source.buffer,
      source.offsetInBytes,
      sourceLength ~/ 2,
    );
    final output = Float32List.view(target.buffer);
    final sourceWordsPerVertex = sourceStride ~/ 2;
    final targetFloatsPerVertex = targetStride ~/ 4;

    for (var vertex = 0; vertex < vertexCount; vertex += 1) {
      final sourceWord = vertex * sourceWordsPerVertex;
      final targetFloat = vertex * targetFloatsPerVertex;
      output[targetFloat] = signed[sourceWord].toDouble();
      output[targetFloat + 1] = signed[sourceWord + 1].toDouble();
      output[targetFloat + 2] = unsigned[sourceWord + 2].toDouble();
      output[targetFloat + 3] = unsigned[sourceWord + 3].toDouble();
      output[targetFloat + 4] = signed[sourceWord + 4].toDouble();
      output[targetFloat + 5] = signed[sourceWord + 5].toDouble();

      if (sourceStride > 12) {
        final sourceOffset = vertex * sourceStride;
        final targetOffset = vertex * targetStride;
        target.setRange(
          targetOffset + 24,
          targetOffset + targetStride,
          source,
          sourceOffset + 12,
        );
      }
    }
    return target;
  }

  final sourceData = ByteData.sublistView(source);
  final targetData = ByteData.sublistView(target);
  for (var vertex = 0; vertex < vertexCount; vertex += 1) {
    final sourceOffset = vertex * sourceStride;
    final targetOffset = vertex * targetStride;
    _writeShortsAsFloats(sourceData, sourceOffset, targetData, targetOffset, 2);
    _writeUnsignedShortsAsFloats(
      sourceData,
      sourceOffset + 4,
      targetData,
      targetOffset + 8,
      2,
    );
    _writeShortsAsFloats(
      sourceData,
      sourceOffset + 8,
      targetData,
      targetOffset + 16,
      2,
    );
    if (sourceStride > 12) {
      target.setRange(
        targetOffset + 24,
        targetOffset + targetStride,
        source,
        sourceOffset + 12,
      );
    }
  }
  return target;
}

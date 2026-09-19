part of '../vertex_repack.dart';

Uint8List _repackPositionPrefixVertices(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int targetStride,
}) {
  final target = Uint8List(vertexCount * targetStride);
  if (vertexCount == 0) return target;

  if (Endian.host == Endian.little && source.offsetInBytes % 4 == 0) {
    final sourceLength = vertexCount * sourceStride;
    final signed = Int16List.view(
      source.buffer,
      source.offsetInBytes,
      sourceLength ~/ 2,
    );
    final sourceWords = Uint32List.view(
      source.buffer,
      source.offsetInBytes,
      sourceLength ~/ 4,
    );
    final output = Float32List.view(target.buffer);
    final outputWords = Uint32List.view(target.buffer);
    final sourceHalvesPerVertex = sourceStride ~/ 2;
    final sourceWordsPerVertex = sourceStride ~/ 4;
    final targetFloatsPerVertex = targetStride ~/ 4;

    for (var vertex = 0; vertex < vertexCount; vertex += 1) {
      final sourceHalf = vertex * sourceHalvesPerVertex;
      final sourceWord = vertex * sourceWordsPerVertex;
      final targetFloat = vertex * targetFloatsPerVertex;
      output[targetFloat] = signed[sourceHalf].toDouble();
      output[targetFloat + 1] = signed[sourceHalf + 1].toDouble();
      for (var word = 1; word < sourceWordsPerVertex; word += 1) {
        outputWords[targetFloat + word + 1] = sourceWords[sourceWord + word];
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
    if (sourceStride > 4) {
      target.setRange(
        targetOffset + 8,
        targetOffset + targetStride,
        source,
        sourceOffset + 4,
      );
    }
  }
  return target;
}

Uint8List _repackRasterVertices(
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
    _writeUnsignedShortsAsFloats(
      sourceData,
      sourceOffset + 4,
      targetData,
      targetOffset + 8,
      2,
    );
  }
  return target;
}

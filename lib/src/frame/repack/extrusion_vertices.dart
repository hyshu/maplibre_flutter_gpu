part of '../vertex_repack.dart';

Uint8List _repackFillExtrusionVertices(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int targetStride,
  required Uint8List target,
  required bool copyPaintWords,
}) {
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
    final output = Float32List.view(
      target.buffer,
      target.offsetInBytes,
      target.lengthInBytes ~/ Float32List.bytesPerElement,
    );
    final sourceWordsPerVertex = sourceStride ~/ 2;
    final targetFloatsPerVertex = targetStride ~/ 4;

    if (copyPaintWords &&
        sourceStride == 44 &&
        targetStride == 56 &&
        source.offsetInBytes % 4 == 0) {
      final sourceWords = Uint32List.view(
        source.buffer,
        source.offsetInBytes,
        sourceLength ~/ Uint32List.bytesPerElement,
      );
      final outputWords = Uint32List.view(
        target.buffer,
        target.offsetInBytes,
        target.lengthInBytes ~/ Uint32List.bytesPerElement,
      );
      for (var vertex = 0; vertex < vertexCount; vertex += 1) {
        final sourceHalf = vertex * 22;
        final sourceWord = vertex * 11;
        final targetWord = vertex * 14;
        output[targetWord] = signed[sourceHalf].toDouble();
        output[targetWord + 1] = signed[sourceHalf + 1].toDouble();
        output[targetWord + 2] = unsigned[sourceHalf + 2].toDouble();
        output[targetWord + 3] = unsigned[sourceHalf + 3].toDouble();
        output[targetWord + 4] = signed[sourceHalf + 4].toDouble();
        output[targetWord + 5] = signed[sourceHalf + 5].toDouble();
        // Paint ranges retain their exact bits, including NaN payloads.
        outputWords[targetWord + 6] = sourceWords[sourceWord + 3];
        outputWords[targetWord + 7] = sourceWords[sourceWord + 4];
        outputWords[targetWord + 8] = sourceWords[sourceWord + 5];
        outputWords[targetWord + 9] = sourceWords[sourceWord + 6];
        outputWords[targetWord + 10] = sourceWords[sourceWord + 7];
        outputWords[targetWord + 11] = sourceWords[sourceWord + 8];
        outputWords[targetWord + 12] = sourceWords[sourceWord + 9];
        outputWords[targetWord + 13] = sourceWords[sourceWord + 10];
      }
      return target;
    }

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

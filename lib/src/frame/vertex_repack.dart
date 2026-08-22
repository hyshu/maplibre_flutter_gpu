// Converts the remaining MapLibre packed vertex layouts into the layouts their
// Flutter GPU pipelines consume. Fill, triangulated fill-outline, packed FE,
// and constant line vertices now bypass this file when source and GPU strides
// already match.
import 'dart:typed_data';

import '../native/draw_command.dart';
import 'draw_flags.dart';

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

/// Compatibility path for old bridge artifacts that expanded constant lines
/// to six float32 values. The values are exact integer conversions of the
/// original short2 + uchar4 layout, so packing them back is lossless.
Uint8List _packExpandedConstantLineVertices(
  Uint8List source, {
  required int vertexCount,
}) {
  final target = Uint8List(vertexCount * 8);
  final input = ByteData.sublistView(source);
  final output = ByteData.sublistView(target);
  for (var vertex = 0; vertex < vertexCount; vertex += 1) {
    final sourceOffset = vertex * 24;
    final targetOffset = vertex * 8;
    output
      ..setInt16(
        targetOffset,
        input.getFloat32(sourceOffset, Endian.little).toInt(),
        Endian.little,
      )
      ..setInt16(
        targetOffset + 2,
        input.getFloat32(sourceOffset + 4, Endian.little).toInt(),
        Endian.little,
      );
    for (var index = 0; index < 4; index += 1) {
      output.setUint8(
        targetOffset + 4 + index,
        input.getFloat32(sourceOffset + 8 + index * 4, Endian.little).toInt(),
      );
    }
  }
  return target;
}

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

Uint8List _repackFillOutlineTriangulatedVertices(
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
      final sourceOffset = vertex * sourceStride;
      final sourceHalf = vertex * sourceHalvesPerVertex;
      final sourceWord = vertex * sourceWordsPerVertex;
      final targetFloat = vertex * targetFloatsPerVertex;
      output[targetFloat] = signed[sourceHalf].toDouble();
      output[targetFloat + 1] = signed[sourceHalf + 1].toDouble();
      output[targetFloat + 2] = source[sourceOffset + 4].toDouble();
      output[targetFloat + 3] = source[sourceOffset + 5].toDouble();
      output[targetFloat + 4] = source[sourceOffset + 6].toDouble();
      output[targetFloat + 5] = source[sourceOffset + 7].toDouble();
      for (var word = 2; word < sourceWordsPerVertex; word += 1) {
        outputWords[targetFloat + word + 4] = sourceWords[sourceWord + word];
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
        targetOffset + targetStride,
        source,
        sourceOffset + 8,
      );
    }
  }
  return target;
}

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

Uint8List repackVertexDataForGpu(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int shader,
  required int flags,
}) {
  final sourceLength = vertexCount * sourceStride;
  if (vertexCount < 0 ||
      sourceStride <= 0 ||
      sourceLength > source.lengthInBytes) {
    throw RangeError('Invalid source vertex range');
  }

  final targetStride = gpuVertexStride(shader, flags);
  if (sourceStride == targetStride) return source;

  if (isLineShader(shader) &&
      !lineUsesDataDrivenPipeline(flags) &&
      sourceStride == 24 &&
      targetStride == 8) {
    return _packExpandedConstantLineVertices(
      source,
      vertexCount: vertexCount,
    );
  }

  if (shader == ShaderType.fillExtrusion) {
    return _repackFillExtrusionVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
    );
  }

  if (shader == ShaderType.fillOutlineTriangulated) {
    return _repackFillOutlineTriangulatedVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
    );
  }

  if (shader == ShaderType.fill ||
      shader == ShaderType.fillOutline ||
      shader == ShaderType.background ||
      shader == ShaderType.clippingMask ||
      shader == ShaderType.backgroundPattern ||
      shader == ShaderType.circle) {
    return _repackPositionPrefixVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
    );
  }

  final target = Uint8List(vertexCount * targetStride);
  final sourceData = ByteData.sublistView(source, 0, sourceLength);
  final targetData = ByteData.sublistView(target);

  for (var vertex = 0; vertex < vertexCount; vertex += 1) {
    final sourceOffset = vertex * sourceStride;
    final targetOffset = vertex * targetStride;

    if (isLineShader(shader)) {
      _writeShortsAsFloats(
        sourceData,
        sourceOffset,
        targetData,
        targetOffset,
        2,
      );
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
      continue;
    }

    if (shader == ShaderType.raster) {
      _writeShortsAsFloats(
        sourceData,
        sourceOffset,
        targetData,
        targetOffset,
        2,
      );
      _writeUnsignedShortsAsFloats(
        sourceData,
        sourceOffset + 4,
        targetData,
        targetOffset + 8,
        2,
      );
      continue;
    }

    throw ArgumentError.value(shader, 'shader', 'Unsupported shader type');
  }
  return target;
}

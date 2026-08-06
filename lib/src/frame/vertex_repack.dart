// Converts MapLibre's packed vertex layouts into the float-only layouts the
// Flutter GPU pipelines declare.
//
// Split out of the renderer because it is pure byte math over a source buffer:
// it needs no GPU context and is covered directly by unit tests.
//
// Not annotated @visibleForTesting: this is the render layer's own API, and
// lib/src is already outside the package's public surface.
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

Uint8List _repackFillExtrusionVertices(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int targetStride,
}) {
  final target = Uint8List(vertexCount * targetStride);
  if (vertexCount == 0) return target;

  // Native command buffers are naturally aligned and every supported Flutter
  // GPU target is little-endian. Typed views avoid six ByteData getter/setter
  // pairs per building vertex on the zoom-boundary cold path.
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

  // Defensive fallback for an unaligned view or a future big-endian target.
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

/// Converts MapLibre's compact short/byte vertex layouts to float-only stage
/// inputs. Impeller OpenGLES binds attributes with `glVertexAttribPointer` and
/// does not support 32-bit integer stage inputs, so passing packed words as
/// float bit patterns would be unsafe for NaN and subnormal encodings.
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
  if (shader == ShaderType.fillExtrusion) {
    return _repackFillExtrusionVertices(
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

    if (isLineShader(shader) || shader == ShaderType.fillOutlineTriangulated) {
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

      if (shader == ShaderType.fillOutlineTriangulated) {
        if (sourceStride > 8) {
          target.setRange(
            targetOffset + 24,
            targetOffset + targetStride,
            source,
            sourceOffset + 8,
          );
        }
        continue;
      }

      if (sourceStride > 8) {
        // Color plus six scalar ranges are already float data.
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

    // Fill, outline, background, circle, clipping mask, and background
    // pattern all begin with one packed signed-short pair.
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

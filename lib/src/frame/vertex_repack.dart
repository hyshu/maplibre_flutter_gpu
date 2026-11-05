// Converts native vertex encodings into each Flutter GPU pipeline's layout.
import 'dart:typed_data';

import '../native/draw_command.dart';
import 'draw_flags.dart';

part 'repack/attribute_writers.dart';
part 'repack/extrusion_vertices.dart';
part 'repack/line_vertices.dart';
part 'repack/outline_vertices.dart';
part 'repack/position_vertices.dart';

/// Bounded staging storage for vertices consumed by a synchronous upload.
///
/// Repacked views may be overwritten by the next repack using this scratch.
/// Upload or copy them before reusing it. Input bytes must not share its
/// storage. Outputs above [maxRetainedBytes] are allocated independently and
/// do not enlarge the retained storage.
final class VertexRepackScratch {
  /// Retains up to 4 MiB, enough for 65,535 vertices at 56 bytes each.
  VertexRepackScratch({this.maxRetainedBytes = 4 * 1024 * 1024}) {
    RangeError.checkNotNegative(maxRetainedBytes, 'maxRetainedBytes');
  }

  /// Maximum retained staging allocation in bytes.
  final int maxRetainedBytes;
  var _bytes = Uint8List(0);

  /// Current retained allocation in bytes, excluding one-shot outputs.
  int get retainedBytes => _bytes.lengthInBytes;

  Uint8List _allocate(int length) {
    if (length > maxRetainedBytes) return Uint8List(length);
    if (_bytes.lengthInBytes < length) {
      var capacity = _bytes.isEmpty ? 4096 : _bytes.lengthInBytes;
      while (capacity < length) {
        capacity *= 2;
      }
      _bytes = Uint8List(
        capacity > maxRetainedBytes ? maxRetainedBytes : capacity,
      );
    }
    return Uint8List.sublistView(_bytes, 0, length);
  }

  /// Drops retained storage without invalidating views held by a caller.
  void clear() => _bytes = Uint8List(0);
}

/// Returns vertices in the GPU layout selected by [shader] and [flags].
///
/// Returns [source] unchanged when its stride already matches the GPU layout.
/// Otherwise returns a new buffer containing [vertexCount] converted vertices.
/// When [scratch] is supplied, converted bytes are borrowed until its next
/// repack and must be consumed synchronously before that call.
/// An explicit [destination] must be disjoint from [source], aligned to four
/// bytes, and large enough for the converted vertices. It cannot accompany
/// [scratch]. Matching layouts still return [source] unchanged.
/// Throws [RangeError] for invalid counts, strides, or source ranges.
/// Throws [ArgumentError] when [shader] has no supported GPU layout.
Uint8List repackVertexDataForGpu(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int shader,
  required int flags,
  VertexRepackScratch? scratch,
  Uint8List? destination,
}) {
  final sourceLength = vertexCount * sourceStride;
  if (vertexCount < 0 ||
      sourceStride <= 0 ||
      sourceLength > source.lengthInBytes) {
    throw RangeError('Invalid source vertex range');
  }

  final targetStride = gpuVertexStride(shader, flags);
  if (destination != null && scratch != null) {
    throw ArgumentError('Destination and scratch cannot both be supplied');
  }
  if (sourceStride == targetStride) return source;
  final targetLength = vertexCount * targetStride;
  if (destination != null) {
    if (destination.lengthInBytes < targetLength ||
        destination.offsetInBytes % 4 != 0) {
      throw ArgumentError('Destination must be aligned and large enough');
    }
    if (source.buffer == destination.buffer &&
        source.offsetInBytes < destination.offsetInBytes + targetLength &&
        destination.offsetInBytes < source.offsetInBytes + sourceLength) {
      throw ArgumentError('Source and destination must not overlap');
    }
  }
  final target = destination != null
      ? Uint8List.sublistView(destination, 0, targetLength)
      : scratch?._allocate(targetLength) ?? Uint8List(targetLength);

  if (shader == ShaderType.fillExtrusion) {
    return _repackFillExtrusionVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
      target: target,
      copyPaintWords: scratch != null,
    );
  }

  if (shader == ShaderType.fillOutlineTriangulated) {
    return _repackFillOutlineTriangulatedVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
      target: target,
    );
  }

  if (shader == ShaderType.fill ||
      shader == ShaderType.fillOutline ||
      shader == ShaderType.background ||
      shader == ShaderType.clippingMask ||
      shader == ShaderType.backgroundPattern ||
      shader == ShaderType.heatmap ||
      shader == ShaderType.heatmapTexture ||
      shader == ShaderType.circle) {
    return _repackPositionPrefixVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
      target: target,
    );
  }

  if (isLineShader(shader)) {
    return _repackLineVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
      target: target,
    );
  }

  if (shader == ShaderType.raster ||
      shader == ShaderType.hillshadePrepare ||
      shader == ShaderType.hillshade) {
    return _repackRasterVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
      target: target,
    );
  }
  throw ArgumentError.value(shader, 'shader', 'Unsupported shader type');
}

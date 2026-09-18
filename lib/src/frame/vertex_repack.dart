// Converts native vertex encodings into each Flutter GPU pipeline's layout.
import 'dart:typed_data';

import '../native/draw_command.dart';
import 'draw_flags.dart';

part 'repack/attribute_writers.dart';
part 'repack/extrusion_vertices.dart';
part 'repack/line_vertices.dart';
part 'repack/outline_vertices.dart';
part 'repack/position_vertices.dart';

/// Returns vertices in the GPU layout selected by [shader] and [flags].
///
/// Returns [source] unchanged when its stride already matches the GPU layout.
/// Otherwise returns a new buffer containing [vertexCount] converted vertices.
/// Throws [RangeError] for invalid counts, strides, or source ranges.
/// Throws [ArgumentError] when [shader] has no supported GPU layout.
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

  if (isLineShader(shader)) {
    return _repackLineVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
    );
  }

  if (shader == ShaderType.raster) {
    return _repackRasterVertices(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      targetStride: targetStride,
    );
  }
  throw ArgumentError.value(shader, 'shader', 'Unsupported shader type');
}

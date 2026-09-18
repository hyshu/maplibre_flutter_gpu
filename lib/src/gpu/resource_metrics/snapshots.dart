part of '../resource_metrics.dart';

/// Repack cost attributed to one shader and source/GPU vertex layout pair.
final class const GpuRepackLayoutSnapshot({
  required final int shader,
  required final int sourceStride,
  required final int gpuStride,
  required final int count,
  required final int micros,
  required final int maxMicros,
  required final int inputBytes,
  required final int outputBytes,
}) {
  double get averageMicros => micros / count;
}

/// Aggregated GPU resource-cache and upload activity for one logging interval.
final class const GpuResourceTimingSnapshot({
  required final int vertexCacheHits,
  required final int vertexCacheMisses,
  required final int indexCacheHits,
  required final int indexCacheMisses,
  required final int textureCacheHits,
  required final int textureCacheMisses,
  required final int repackCount,
  required final int repackMicros,
  required final int repackMaxMicros,

  /// Cached-buffer repacks, ordered by total repack time descending.
  required final List<GpuRepackLayoutSnapshot> repackLayouts,
  required final int vertexUploadCount,
  required final int vertexUploadMicros,
  required final int vertexUploadBytes,
  required final int vertexUploadMaxMicros,
  required final int indexUploadCount,
  required final int indexUploadMicros,
  required final int indexUploadBytes,
  required final int indexUploadMaxMicros,
  required final int textureUploadCount,
  required final int textureUploadMicros,
  required final int textureUploadBytes,
  required final int textureUploadMaxMicros,
  required final int frameVertexUploadCount,
  required final int frameVertexUploadBytes,
  required final int frameIndexUploadCount,
  required final int frameIndexUploadBytes,
  required final int expiryEvictionCount,
  required final int expiryEvictionBytes,
  required final int budgetEvictionCount,
  required final int budgetEvictionBytes,
}) {
  int get vertexLookupCount => vertexCacheHits + vertexCacheMisses;
  int get indexLookupCount => indexCacheHits + indexCacheMisses;
  int get textureLookupCount => textureCacheHits + textureCacheMisses;

  double? get averageRepackMicros =>
      repackCount == 0 ? null : repackMicros / repackCount;
  double? get averageVertexUploadMicros =>
      vertexUploadCount == 0 ? null : vertexUploadMicros / vertexUploadCount;
  double? get averageIndexUploadMicros =>
      indexUploadCount == 0 ? null : indexUploadMicros / indexUploadCount;
  double? get averageTextureUploadMicros =>
      textureUploadCount == 0 ? null : textureUploadMicros / textureUploadCount;
}

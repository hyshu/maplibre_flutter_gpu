import 'package:flutter/foundation.dart';

import '../frame/draw_flags.dart';
import '../native/draw_command.dart';
import 'draw_entry.dart';
import 'prepared_graph_metrics.dart';
import 'resource_cache.dart';

/// Logs frame work and prepared graph reuse for one sampling interval.
void logGpuFrameSummary({
  required double zoom,
  required List<DrawEntry> entries,
  required int commandCount,
  required int drawCount,
  required int renderPassCount,
  required int uboMicros,
  required PreparedGraphDetailedTimingSnapshot graphTiming,
}) {
  int nFill = 0,
      nFE = 0,
      nBg = 0,
      nLine = 0,
      nSdf = 0,
      nGrad = 0,
      nPat = 0,
      nCircle = 0,
      nRaster = 0,
      nMerged = 0,
      totalVerts = 0;
  for (final entry in entries) {
    if (entry.shader == ShaderType.fill) {
      nFill++;
    } else if (entry.shader == ShaderType.fillExtrusion) {
      nFE++;
    } else if (entry.shader == ShaderType.background ||
        entry.shader == ShaderType.backgroundPattern) {
      nBg++;
    } else if (entry.shader == ShaderType.line) {
      nLine++;
    } else if (entry.shader == ShaderType.lineSDF) {
      nSdf++;
    } else if (entry.shader == ShaderType.lineGradient) {
      nGrad++;
    } else if (entry.shader == ShaderType.linePattern) {
      nPat++;
    } else if (entry.shader == ShaderType.circle) {
      nCircle++;
    } else if (entry.shader == ShaderType.raster) {
      nRaster++;
    }
    if (drawCommandIsCrossTileMerged(entry.flags)) nMerged++;
    totalVerts += entry.vertexCount;
  }
  String averageMicros(double? value) =>
      value == null ? '-' : '${value.toStringAsFixed(0)}us';
  String maxMicros(int count, int value) => count == 0 ? '-' : '${value}us';
  final totals = graphTiming.totals;
  final graphHitRate = (totals.hitRate * 100).toStringAsFixed(1);
  debugPrint(
    '[GpuRenderer] z=${zoom.toStringAsFixed(2)} n=$commandCount '
    'draws=$drawCount passes=$renderPassCount '
    'bg=$nBg fill=$nFill line=$nLine sdf=$nSdf grad=$nGrad pat=$nPat '
    'circle=$nCircle raster=$nRaster fe=$nFE merged=$nMerged '
    'verts=${totalVerts ~/ 1000}K '
    'graph=${totals.hitCount}/${totals.sampleCount}($graphHitRate%) '
    'graphHit=${averageMicros(totals.averageHitMicros)} '
    'graphRebuild=${averageMicros(totals.averageRebuildMicros)} '
    'ubo=${uboMicros}us',
  );
  debugPrint(
    '[GpuGraph] hitMax=${maxMicros(totals.hitCount, graphTiming.hitMaxMicros)} '
    'rebuildMax=${maxMicros(totals.rebuildCount, graphTiming.rebuildMaxMicros)} '
    'validate=${averageMicros(graphTiming.averageValidationMicros)} '
    'refresh=${averageMicros(graphTiming.averageRefreshMicros)} '
    'decode=${averageMicros(graphTiming.averageDecodeMicros)} '
    'capture=${averageMicros(graphTiming.averageCaptureMicros)} '
    'rebuildCause=noGraph:${graphTiming.noGraphRebuildCount} '
    'topology:${graphTiming.topologyMismatchRebuildCount} '
    'refresh:${graphTiming.refreshFailedRebuildCount}',
  );
}

/// Logs cache occupancy and resets interval upload and allocation metrics.
void logGpuResourceSummary(GpuResourceCache resourceCache) {
  final timing = resourceCache.timingMetrics.takeSnapshotAndReset();
  final cache = resourceCache.sizeSnapshot;
  final pool = resourceCache.takeBufferPoolSnapshotAndReset();
  String lookup(int hits, int misses) => '$hits/${hits + misses}(miss=$misses)';
  String average(double? micros) =>
      micros == null ? '-' : '${micros.toStringAsFixed(0)}us';
  String maximum(int count, int micros) => count == 0 ? '-' : '${micros}us';
  String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

  debugPrint(
    '[GpuResource] vertex=${lookup(timing.vertexCacheHits, timing.vertexCacheMisses)} '
    'index=${lookup(timing.indexCacheHits, timing.indexCacheMisses)} '
    'texture=${lookup(timing.textureCacheHits, timing.textureCacheMisses)} '
    'cache=v:${cache.vertexCount}/${megabytes(cache.vertexBytes)} '
    'i:${cache.indexCount}/${megabytes(cache.indexBytes)} '
    't:${cache.textureCount}/${megabytes(cache.textureBytes)} '
    'total=${megabytes(cache.totalBytes)} '
    'evict=expiry:${timing.expiryEvictionCount}/${megabytes(timing.expiryEvictionBytes)} '
    'budget:${timing.budgetEvictionCount}/${megabytes(timing.budgetEvictionBytes)}',
  );
  debugPrint(
    '[GpuUpload] repack=${timing.repackCount}/${average(timing.averageRepackMicros)} '
    'max=${maximum(timing.repackCount, timing.repackMaxMicros)} '
    'vertex=${timing.vertexUploadCount}/${megabytes(timing.vertexUploadBytes)}/'
    '${average(timing.averageVertexUploadMicros)}/'
    '${maximum(timing.vertexUploadCount, timing.vertexUploadMaxMicros)} '
    'index=${timing.indexUploadCount}/${megabytes(timing.indexUploadBytes)}/'
    '${average(timing.averageIndexUploadMicros)}/'
    '${maximum(timing.indexUploadCount, timing.indexUploadMaxMicros)} '
    'texture=${timing.textureUploadCount}/${megabytes(timing.textureUploadBytes)}/'
    '${average(timing.averageTextureUploadMicros)}/'
    '${maximum(timing.textureUploadCount, timing.textureUploadMaxMicros)} '
    'frameOwned=v:${timing.frameVertexUploadCount}/'
    '${megabytes(timing.frameVertexUploadBytes)} '
    'i:${timing.frameIndexUploadCount}/${megabytes(timing.frameIndexUploadBytes)}',
  );
  debugPrint(
    '[GpuBufferPool] pages=${pool.pageCount}/${megabytes(pool.pageBytes)} '
    'writes=${pool.writeCount}/${megabytes(pool.writeBytes)} '
    'newPages=${pool.pageAllocationCount} reuse=${pool.reusedRangeCount}',
  );
}

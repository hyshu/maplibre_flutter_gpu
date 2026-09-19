import 'package:flutter/foundation.dart';

import '../native/draw_command.dart';

part 'resource_metrics/diagnostics.dart';
part 'resource_metrics/snapshots.dart';

typedef GpuRepackLayoutKey = ({int shader, int sourceStride, int gpuStride});

final class _GpuRepackLayoutTotals {
  var count = 0;
  var micros = 0;
  var maxMicros = 0;
  var inputBytes = 0;
  var outputBytes = 0;
}

enum GpuUploadSizeClass { small, medium, large }

/// Classifies one upload by payload size for allocation-cost attribution.
@visibleForTesting
GpuUploadSizeClass gpuUploadSizeClassForBytes(int bytes) {
  if (bytes < 0) {
    throw RangeError.value(bytes, 'bytes', 'must not be negative');
  }
  if (bytes <= 16 * 1024) return .small;
  if (bytes <= 256 * 1024) return .medium;

  return .large;
}

final class _GpuUploadSizeTotals {
  var count = 0;
  var micros = 0;
  var maxMicros = 0;
  var bytes = 0;
}

/// Mutable interval counters for GPU resource preparation.
final class GpuResourceTimingMetrics {
  var _vertexCacheHits = 0;
  var _vertexCacheMisses = 0;
  var _indexCacheHits = 0;
  var _indexCacheMisses = 0;
  var _textureCacheHits = 0;
  var _textureCacheMisses = 0;
  var _repackCount = 0;
  var _repackMicros = 0;
  var _repackMaxMicros = 0;
  var _vertexUploadCount = 0;
  var _vertexUploadMicros = 0;
  var _vertexUploadBytes = 0;
  var _vertexUploadMaxMicros = 0;
  var _indexUploadCount = 0;
  var _indexUploadMicros = 0;
  var _indexUploadBytes = 0;
  var _indexUploadMaxMicros = 0;
  var _textureUploadCount = 0;
  var _textureUploadMicros = 0;
  var _textureUploadBytes = 0;
  var _textureUploadMaxMicros = 0;
  var _frameVertexUploadCount = 0;
  var _frameVertexUploadBytes = 0;
  var _frameIndexUploadCount = 0;
  var _frameIndexUploadBytes = 0;
  var _expiryEvictionCount = 0;
  var _expiryEvictionBytes = 0;
  var _budgetEvictionCount = 0;
  var _budgetEvictionBytes = 0;
  final Map<GpuRepackLayoutKey, _GpuRepackLayoutTotals> _repackLayouts = {};
  final Map<GpuUploadSizeClass, _GpuUploadSizeTotals> _vertexUploadSizes = {};
  final Map<GpuUploadSizeClass, _GpuUploadSizeTotals> _indexUploadSizes = {};
  ({int shader, int sourceStride, int gpuStride, int vertexCount})?
  _pendingCachedRepack;

  void recordVertexLookup({
    required bool hit,
    int? shader,
    int? sourceStride,
    int? gpuStride,
    int? vertexCount,
  }) {
    _pendingCachedRepack = null;
    if (hit) {
      _vertexCacheHits += 1;
    } else {
      _vertexCacheMisses += 1;
      if (shader != null &&
          sourceStride != null &&
          gpuStride != null &&
          vertexCount != null) {
        _checkNonNegative('sourceStride', sourceStride);
        _checkNonNegative('gpuStride', gpuStride);
        _checkNonNegative('vertexCount', vertexCount);
        _pendingCachedRepack = (
          shader: shader,
          sourceStride: sourceStride,
          gpuStride: gpuStride,
          vertexCount: vertexCount,
        );
      }
    }
  }

  void recordIndexLookup({required bool hit}) {
    if (hit) {
      _indexCacheHits += 1;
    } else {
      _indexCacheMisses += 1;
    }
  }

  void recordTextureLookup({required bool hit}) {
    if (hit) {
      _textureCacheHits += 1;
    } else {
      _textureCacheMisses += 1;
    }
  }

  void recordRepack({required int micros}) {
    _checkNonNegative('micros', micros);
    _repackCount += 1;
    _repackMicros += micros;
    if (micros > _repackMaxMicros) _repackMaxMicros = micros;

    final pending = _pendingCachedRepack;
    _pendingCachedRepack = null;
    if (pending == null) return;
    final key = (
      shader: pending.shader,
      sourceStride: pending.sourceStride,
      gpuStride: pending.gpuStride,
    );
    final totals = _repackLayouts.putIfAbsent(key, _GpuRepackLayoutTotals.new);
    totals
      ..count += 1
      ..micros += micros
      ..inputBytes += pending.vertexCount * pending.sourceStride
      ..outputBytes += pending.vertexCount * pending.gpuStride;
    if (micros > totals.maxMicros) totals.maxMicros = micros;
  }

  void recordVertexUpload({
    required int micros,
    required int bytes,
    bool frameOwned = false,
  }) {
    _checkNonNegative('micros', micros);
    _checkNonNegative('bytes', bytes);
    _vertexUploadCount += 1;
    _vertexUploadMicros += micros;
    _vertexUploadBytes += bytes;
    if (micros > _vertexUploadMaxMicros) _vertexUploadMaxMicros = micros;
    _recordUploadSize(_vertexUploadSizes, micros: micros, bytes: bytes);
    if (frameOwned) {
      _frameVertexUploadCount += 1;
      _frameVertexUploadBytes += bytes;
    }
  }

  void recordIndexUpload({
    required int micros,
    required int bytes,
    bool frameOwned = false,
  }) {
    _checkNonNegative('micros', micros);
    _checkNonNegative('bytes', bytes);
    _indexUploadCount += 1;
    _indexUploadMicros += micros;
    _indexUploadBytes += bytes;
    if (micros > _indexUploadMaxMicros) _indexUploadMaxMicros = micros;
    _recordUploadSize(_indexUploadSizes, micros: micros, bytes: bytes);
    if (frameOwned) {
      _frameIndexUploadCount += 1;
      _frameIndexUploadBytes += bytes;
    }
  }

  void recordTextureUpload({required int micros, required int bytes}) {
    _checkNonNegative('micros', micros);
    _checkNonNegative('bytes', bytes);
    _textureUploadCount += 1;
    _textureUploadMicros += micros;
    _textureUploadBytes += bytes;
    if (micros > _textureUploadMaxMicros) _textureUploadMaxMicros = micros;
  }

  void recordExpiryEvictions({required int count, required int bytes}) {
    _checkNonNegative('count', count);
    _checkNonNegative('bytes', bytes);
    _expiryEvictionCount += count;
    _expiryEvictionBytes += bytes;
  }

  void recordBudgetEviction({required int bytes}) {
    _checkNonNegative('bytes', bytes);
    _budgetEvictionCount += 1;
    _budgetEvictionBytes += bytes;
  }

  GpuResourceTimingSnapshot takeSnapshotAndReset() {
    final repackLayouts =
        _repackLayouts.entries
            .map(
              (entry) => GpuRepackLayoutSnapshot(
                shader: entry.key.shader,
                sourceStride: entry.key.sourceStride,
                gpuStride: entry.key.gpuStride,
                count: entry.value.count,
                micros: entry.value.micros,
                maxMicros: entry.value.maxMicros,
                inputBytes: entry.value.inputBytes,
                outputBytes: entry.value.outputBytes,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => right.micros.compareTo(left.micros));
    final snapshot = GpuResourceTimingSnapshot(
      vertexCacheHits: _vertexCacheHits,
      vertexCacheMisses: _vertexCacheMisses,
      indexCacheHits: _indexCacheHits,
      indexCacheMisses: _indexCacheMisses,
      textureCacheHits: _textureCacheHits,
      textureCacheMisses: _textureCacheMisses,
      repackCount: _repackCount,
      repackMicros: _repackMicros,
      repackMaxMicros: _repackMaxMicros,
      repackLayouts: .unmodifiable(repackLayouts),
      vertexUploadCount: _vertexUploadCount,
      vertexUploadMicros: _vertexUploadMicros,
      vertexUploadBytes: _vertexUploadBytes,
      vertexUploadMaxMicros: _vertexUploadMaxMicros,
      indexUploadCount: _indexUploadCount,
      indexUploadMicros: _indexUploadMicros,
      indexUploadBytes: _indexUploadBytes,
      indexUploadMaxMicros: _indexUploadMaxMicros,
      textureUploadCount: _textureUploadCount,
      textureUploadMicros: _textureUploadMicros,
      textureUploadBytes: _textureUploadBytes,
      textureUploadMaxMicros: _textureUploadMaxMicros,
      frameVertexUploadCount: _frameVertexUploadCount,
      frameVertexUploadBytes: _frameVertexUploadBytes,
      frameIndexUploadCount: _frameIndexUploadCount,
      frameIndexUploadBytes: _frameIndexUploadBytes,
      expiryEvictionCount: _expiryEvictionCount,
      expiryEvictionBytes: _expiryEvictionBytes,
      budgetEvictionCount: _budgetEvictionCount,
      budgetEvictionBytes: _budgetEvictionBytes,
    );
    _logRepackLayouts(snapshot.repackLayouts);
    _logUploadSizes(_vertexUploadSizes, _indexUploadSizes);
    _vertexCacheHits = 0;
    _vertexCacheMisses = 0;
    _indexCacheHits = 0;
    _indexCacheMisses = 0;
    _textureCacheHits = 0;
    _textureCacheMisses = 0;
    _repackCount = 0;
    _repackMicros = 0;
    _repackMaxMicros = 0;
    _vertexUploadCount = 0;
    _vertexUploadMicros = 0;
    _vertexUploadBytes = 0;
    _vertexUploadMaxMicros = 0;
    _indexUploadCount = 0;
    _indexUploadMicros = 0;
    _indexUploadBytes = 0;
    _indexUploadMaxMicros = 0;
    _textureUploadCount = 0;
    _textureUploadMicros = 0;
    _textureUploadBytes = 0;
    _textureUploadMaxMicros = 0;
    _frameVertexUploadCount = 0;
    _frameVertexUploadBytes = 0;
    _frameIndexUploadCount = 0;
    _frameIndexUploadBytes = 0;
    _expiryEvictionCount = 0;
    _expiryEvictionBytes = 0;
    _budgetEvictionCount = 0;
    _budgetEvictionBytes = 0;
    _repackLayouts.clear();
    _vertexUploadSizes.clear();
    _indexUploadSizes.clear();
    _pendingCachedRepack = null;

    return snapshot;
  }

  static void _recordUploadSize(
    Map<GpuUploadSizeClass, _GpuUploadSizeTotals> totals, {
    required int micros,
    required int bytes,
  }) {
    final value = totals.putIfAbsent(
      gpuUploadSizeClassForBytes(bytes),
      _GpuUploadSizeTotals.new,
    );
    value
      ..count += 1
      ..micros += micros
      ..bytes += bytes;
    if (micros > value.maxMicros) value.maxMicros = micros;
  }

  static void _checkNonNegative(String name, int value) {
    if (value < 0) {
      throw RangeError.value(value, name, 'must not be negative');
    }
  }
}

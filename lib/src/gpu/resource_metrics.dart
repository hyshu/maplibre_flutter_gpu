import 'package:flutter/foundation.dart';

import '../native/draw_command.dart';

typedef GpuRepackLayoutKey = ({int shader, int sourceStride, int gpuStride});

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

final class _GpuRepackLayoutTotals {
  int count = 0;
  int micros = 0;
  int maxMicros = 0;
  int inputBytes = 0;
  int outputBytes = 0;
}

enum GpuUploadSizeClass { small, medium, large }

/// Classifies one upload by payload size for allocation-cost attribution.
@visibleForTesting
GpuUploadSizeClass gpuUploadSizeClassForBytes(int bytes) {
  if (bytes < 0) {
    throw RangeError.value(bytes, 'bytes', 'must not be negative');
  }
  if (bytes <= 16 * 1024) return GpuUploadSizeClass.small;
  if (bytes <= 256 * 1024) return GpuUploadSizeClass.medium;
  return GpuUploadSizeClass.large;
}

final class _GpuUploadSizeTotals {
  int count = 0;
  int micros = 0;
  int maxMicros = 0;
  int bytes = 0;
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

/// Mutable interval counters for GPU resource preparation.
final class GpuResourceTimingMetrics {
  int _vertexCacheHits = 0;
  int _vertexCacheMisses = 0;
  int _indexCacheHits = 0;
  int _indexCacheMisses = 0;
  int _textureCacheHits = 0;
  int _textureCacheMisses = 0;
  int _repackCount = 0;
  int _repackMicros = 0;
  int _repackMaxMicros = 0;
  int _vertexUploadCount = 0;
  int _vertexUploadMicros = 0;
  int _vertexUploadBytes = 0;
  int _vertexUploadMaxMicros = 0;
  int _indexUploadCount = 0;
  int _indexUploadMicros = 0;
  int _indexUploadBytes = 0;
  int _indexUploadMaxMicros = 0;
  int _textureUploadCount = 0;
  int _textureUploadMicros = 0;
  int _textureUploadBytes = 0;
  int _textureUploadMaxMicros = 0;
  int _frameVertexUploadCount = 0;
  int _frameVertexUploadBytes = 0;
  int _frameIndexUploadCount = 0;
  int _frameIndexUploadBytes = 0;
  int _expiryEvictionCount = 0;
  int _expiryEvictionBytes = 0;
  int _budgetEvictionCount = 0;
  int _budgetEvictionBytes = 0;
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
      repackLayouts: List<GpuRepackLayoutSnapshot>.unmodifiable(repackLayouts),
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

void _logRepackLayouts(List<GpuRepackLayoutSnapshot> layouts) {
  if (layouts.isEmpty) {
    debugPrint('[GpuRepack] none');
    return;
  }

  String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  final values = layouts
      .take(6)
      .map((layout) {
        final name = _shaderName(layout.shader);
        final average = layout.averageMicros.toStringAsFixed(0);
        return '$name[${layout.sourceStride}>${layout.gpuStride}]='
            '${layout.count}/${megabytes(layout.inputBytes)}>'
            '${megabytes(layout.outputBytes)}/${average}us/${layout.maxMicros}us';
      })
      .join(' ');
  final omitted = layouts.length > 6 ? ' +${layouts.length - 6}more' : '';
  debugPrint('[GpuRepack] $values$omitted');
}

void _logUploadSizes(
  Map<GpuUploadSizeClass, _GpuUploadSizeTotals> vertex,
  Map<GpuUploadSizeClass, _GpuUploadSizeTotals> index,
) {
  if (vertex.isEmpty && index.isEmpty) {
    debugPrint('[GpuUploadSize] none');
    return;
  }

  String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  String className(GpuUploadSizeClass sizeClass) => switch (sizeClass) {
    GpuUploadSizeClass.small => '<=16K',
    GpuUploadSizeClass.medium => '<=256K',
    GpuUploadSizeClass.large => '>256K',
  };
  String describe(
    String prefix,
    Map<GpuUploadSizeClass, _GpuUploadSizeTotals> totals,
  ) {
    final values = <String>[];
    for (final sizeClass in GpuUploadSizeClass.values) {
      final value = totals[sizeClass];
      if (value == null || value.count == 0) continue;
      final average = (value.micros / value.count).toStringAsFixed(0);
      values.add(
        '$prefix${className(sizeClass)}=${value.count}/'
        '${megabytes(value.bytes)}/${value.micros}us/${average}us/'
        '${value.maxMicros}us',
      );
    }
    return values.join(' ');
  }

  final vertexText = describe('v', vertex);
  final indexText = describe('i', index);
  final values = [
    vertexText,
    indexText,
  ].where((value) => value.isNotEmpty).join(' ');
  debugPrint('[GpuUploadSize] $values');
}

String _shaderName(int shader) => switch (shader) {
  ShaderType.fill => 'fill',
  ShaderType.fillOutline => 'fillOutline',
  ShaderType.line => 'line',
  ShaderType.background => 'background',
  ShaderType.fillExtrusion => 'fillExtrusion',
  ShaderType.lineSDF => 'lineSDF',
  ShaderType.lineGradient => 'lineGradient',
  ShaderType.linePattern => 'linePattern',
  ShaderType.circle => 'circle',
  ShaderType.raster => 'raster',
  ShaderType.fillOutlineTriangulated => 'fillOutlineTri',
  ShaderType.clippingMask => 'clippingMask',
  ShaderType.backgroundPattern => 'backgroundPattern',
  _ => 'shader$shader',
};

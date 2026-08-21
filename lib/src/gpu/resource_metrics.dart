/// Aggregated GPU resource-cache and upload activity for one logging interval.
final class GpuResourceTimingSnapshot {
  const GpuResourceTimingSnapshot({
    required this.vertexCacheHits,
    required this.vertexCacheMisses,
    required this.indexCacheHits,
    required this.indexCacheMisses,
    required this.textureCacheHits,
    required this.textureCacheMisses,
    required this.repackCount,
    required this.repackMicros,
    required this.repackMaxMicros,
    required this.vertexUploadCount,
    required this.vertexUploadMicros,
    required this.vertexUploadBytes,
    required this.vertexUploadMaxMicros,
    required this.indexUploadCount,
    required this.indexUploadMicros,
    required this.indexUploadBytes,
    required this.indexUploadMaxMicros,
    required this.textureUploadCount,
    required this.textureUploadMicros,
    required this.textureUploadBytes,
    required this.textureUploadMaxMicros,
    required this.frameVertexUploadCount,
    required this.frameVertexUploadBytes,
    required this.frameIndexUploadCount,
    required this.frameIndexUploadBytes,
    required this.expiryEvictionCount,
    required this.expiryEvictionBytes,
    required this.budgetEvictionCount,
    required this.budgetEvictionBytes,
  });

  final int vertexCacheHits;
  final int vertexCacheMisses;
  final int indexCacheHits;
  final int indexCacheMisses;
  final int textureCacheHits;
  final int textureCacheMisses;
  final int repackCount;
  final int repackMicros;
  final int repackMaxMicros;
  final int vertexUploadCount;
  final int vertexUploadMicros;
  final int vertexUploadBytes;
  final int vertexUploadMaxMicros;
  final int indexUploadCount;
  final int indexUploadMicros;
  final int indexUploadBytes;
  final int indexUploadMaxMicros;
  final int textureUploadCount;
  final int textureUploadMicros;
  final int textureUploadBytes;
  final int textureUploadMaxMicros;
  final int frameVertexUploadCount;
  final int frameVertexUploadBytes;
  final int frameIndexUploadCount;
  final int frameIndexUploadBytes;
  final int expiryEvictionCount;
  final int expiryEvictionBytes;
  final int budgetEvictionCount;
  final int budgetEvictionBytes;

  int get vertexLookupCount => vertexCacheHits + vertexCacheMisses;
  int get indexLookupCount => indexCacheHits + indexCacheMisses;
  int get textureLookupCount => textureCacheHits + textureCacheMisses;

  double? get averageRepackMicros =>
      repackCount == 0 ? null : repackMicros / repackCount;
  double? get averageVertexUploadMicros => vertexUploadCount == 0
      ? null
      : vertexUploadMicros / vertexUploadCount;
  double? get averageIndexUploadMicros =>
      indexUploadCount == 0 ? null : indexUploadMicros / indexUploadCount;
  double? get averageTextureUploadMicros => textureUploadCount == 0
      ? null
      : textureUploadMicros / textureUploadCount;
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

  void recordVertexLookup({required bool hit}) {
    if (hit) {
      _vertexCacheHits += 1;
    } else {
      _vertexCacheMisses += 1;
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

    return snapshot;
  }

  static void _checkNonNegative(String name, int value) {
    if (value < 0) {
      throw RangeError.value(value, name, 'must not be negative');
    }
  }
}

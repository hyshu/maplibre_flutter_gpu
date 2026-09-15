part of '../resource_cache.dart';

sealed class const _BufferBudgetKey();

final class const _VertexBufferBudgetKey(final GpuVertexBufferCacheKey cacheKey)
    extends _BufferBudgetKey;

final class const _IndexBufferBudgetKey(final GpuIndexBufferCacheKey cacheKey)
    extends _BufferBudgetKey;

typedef _BudgetEntry = ({int lastUsed, int bytes});

/// Applies expiry and adaptive byte budgets to resources shared with the cache.
final class _GpuCacheMaintenance {
  _GpuCacheMaintenance({
    required this._vertexCache,
    required this._indexCache,
    required this._textureCache,
    required this.timingMetrics,
    required GpuCacheMissTracker<GpuVertexBufferCacheKey> vertexMissTracker,
    required GpuCacheMissTracker<GpuIndexBufferCacheKey> indexMissTracker,
  }) : _fillExtrusionVertexMissTracker = vertexMissTracker,
       _fillExtrusionIndexMissTracker = indexMissTracker;

  final Map<GpuVertexBufferCacheKey, GpuBufferEntry> _vertexCache;
  final Map<GpuIndexBufferCacheKey, GpuBufferEntry> _indexCache;
  final Map<GpuTextureCacheKey, GpuTextureEntry> _textureCache;
  final GpuResourceTimingMetrics timingMetrics;
  final GpuCacheMissTracker<GpuVertexBufferCacheKey>
  _fillExtrusionVertexMissTracker;
  final GpuCacheMissTracker<GpuIndexBufferCacheKey>
  _fillExtrusionIndexMissTracker;
  final _evictionMetrics = _GpuCacheEvictionMetrics();
  var _frame = 0;
  var _regularBufferBudgetBytes =
      GpuCachePolicy.regularMinBufferCacheBudgetBytes;
  var _lastRegularBufferBudgetGrowthFrame = 0;
  var _fillExtrusionBudgetBytes =
      GpuCachePolicy.fillExtrusionMinBufferCacheBudgetBytes;
  var _lastFillExtrusionRecentUseFrame = 0;
  var _budgetDirty = false;

  void markDirty() {
    _budgetDirty = true;
  }

  void recordFillExtrusionUse() {
    _lastFillExtrusionRecentUseFrame = _frame;
  }

  void beginFrame(int frame) {
    _frame = frame;
    if (_regularBufferBudgetBytes >
            GpuCachePolicy.regularMinBufferCacheBudgetBytes &&
        _frame - _lastRegularBufferBudgetGrowthFrame ==
            GpuCachePolicy.regularBudgetIdleShrinkFrames) {
      _budgetDirty = true;
    }
    if (_fillExtrusionBudgetBytes >
            GpuCachePolicy.fillExtrusionMinBufferCacheBudgetBytes &&
        _frame - _lastFillExtrusionRecentUseFrame ==
            GpuCachePolicy.fillExtrusionBudgetIdleShrinkFrames) {
      _budgetDirty = true;
    }
  }

  /// Removes expired entries and enforces cache byte budgets.
  void evictCaches() {
    // Superseded resources must survive the frames already in flight, so
    // expiry maintenance runs at the same cadence.
    if (gpuCacheExpiryMaintenanceDue(_frame)) {
      var expiredCount = 0;
      var expiredBytes = 0;
      void recordVertexExpiry(
        GpuVertexBufferCacheKey key,
        GpuBufferEntry value,
      ) {
        value._releasePooledAllocation(_frame);
        if (value.isFillExtrusion) {
          _fillExtrusionVertexMissTracker.recordEviction(
            key: key,
            kind: .expiry,
          );
        }
        expiredCount += 1;
        expiredBytes += value.lengthInBytes;
        _evictionMetrics.recordExpiry(
          gpuCacheClassForShader(key.shader),
          value.lengthInBytes,
        );
      }

      void recordIndexExpiry(GpuIndexBufferCacheKey key, GpuBufferEntry value) {
        value._releasePooledAllocation(_frame);
        if (value.isFillExtrusion) {
          _fillExtrusionIndexMissTracker.recordEviction(
            key: key,
            kind: .expiry,
          );
        }
        expiredCount += 1;
        expiredBytes += value.lengthInBytes;
        _evictionMetrics.recordExpiry(
          value.isFillExtrusion ? .fillExtrusion : .indexBuffer,
          value.lengthInBytes,
        );
      }

      void recordTextureExpiry(GpuTextureCacheKey key, GpuTextureEntry value) {
        expiredCount += 1;
        expiredBytes += value.lengthInBytes;
        _evictionMetrics.recordExpiry(.texture, value.lengthInBytes);
      }

      evictExpiredCacheVersions(
        _vertexCache,
        frame: _frame,
        idOf: (key) => key.bufferId,
        versionOf: (key) => key.bufferVersion,
        lastUsedOf: (value) => value.lastUsed,
        unusedRetentionFramesForEntry: (key, value) =>
            gpuVertexUnusedRetentionFrames(
              key.shader,
              isFillExtrusion: value.isFillExtrusion,
            ),
        onEvict: recordVertexExpiry,
        onEvictReason: (_, value, reason) =>
            _evictionMetrics.recordExpiryReason(reason, value.lengthInBytes),
      );
      evictExpiredCacheVersions(
        _indexCache,
        frame: _frame,
        idOf: (key) => key.bufferId,
        versionOf: (key) => key.bufferVersion,
        lastUsedOf: (value) => value.lastUsed,
        unusedRetentionFramesOf: (value) => gpuIndexUnusedRetentionFrames(
          isFillExtrusion: value.isFillExtrusion,
        ),
        onEvict: recordIndexExpiry,
        onEvictReason: (_, value, reason) =>
            _evictionMetrics.recordExpiryReason(reason, value.lengthInBytes),
      );
      evictExpiredCacheVersions(
        _textureCache,
        frame: _frame,
        idOf: (key) => key.textureId,
        versionOf: (key) => key.textureVersion,
        lastUsedOf: (value) => value.lastUsed,
        onEvict: recordTextureExpiry,
        onEvictReason: (_, value, reason) =>
            _evictionMetrics.recordExpiryReason(reason, value.lengthInBytes),
      );
      if (expiredCount > 0) {
        timingMetrics.recordExpiryEvictions(
          count: expiredCount,
          bytes: expiredBytes,
        );
      }
    }

    // Cached bytes can increase only when a resource is stored. Count without
    // allocating, then build sortable victim maps only when a limit is
    // actually exceeded.
    if (!_budgetDirty) {
      _evictionMetrics.logIfDue(_frame);

      return;
    }
    _budgetDirty = false;
    var regularBufferBytes = 0;
    var recentRegularBufferBytes = 0;
    var fillExtrusionBufferBytes = 0;
    var recentFillExtrusionBufferBytes = 0;
    for (final entry in _vertexCache.values) {
      if (entry.isFillExtrusion) {
        fillExtrusionBufferBytes += entry.lengthInBytes;
        if (_frame - entry.lastUsed <
            GpuCachePolicy.fillExtrusionBudgetWorkingSetFrames) {
          recentFillExtrusionBufferBytes += entry.lengthInBytes;
        }
      } else {
        regularBufferBytes += entry.lengthInBytes;
        if (_frame - entry.lastUsed <
            GpuCachePolicy.regularBudgetWorkingSetFrames) {
          recentRegularBufferBytes += entry.lengthInBytes;
        }
      }
    }
    for (final entry in _indexCache.values) {
      if (entry.isFillExtrusion) {
        fillExtrusionBufferBytes += entry.lengthInBytes;
        if (_frame - entry.lastUsed <
            GpuCachePolicy.fillExtrusionBudgetWorkingSetFrames) {
          recentFillExtrusionBufferBytes += entry.lengthInBytes;
        }
      } else {
        regularBufferBytes += entry.lengthInBytes;
        if (_frame - entry.lastUsed <
            GpuCachePolicy.regularBudgetWorkingSetFrames) {
          recentRegularBufferBytes += entry.lengthInBytes;
        }
      }
    }

    final regularTargetBudgetBytes = gpuRegularBufferBudgetForResidentBytes(
      regularBufferBytes,
    );
    if (regularTargetBudgetBytes > _regularBufferBudgetBytes) {
      _regularBufferBudgetBytes = regularTargetBudgetBytes;
      _lastRegularBufferBudgetGrowthFrame = _frame;
    } else if (_regularBufferBudgetBytes >
            GpuCachePolicy.regularMinBufferCacheBudgetBytes &&
        _frame - _lastRegularBufferBudgetGrowthFrame >=
            GpuCachePolicy.regularBudgetIdleShrinkFrames &&
        recentRegularBufferBytes <=
            GpuCachePolicy.regularMinBufferCacheBudgetBytes) {
      _regularBufferBudgetBytes =
          GpuCachePolicy.regularMinBufferCacheBudgetBytes;
    }
    if (regularBufferBytes > _regularBufferBudgetBytes) {
      regularBufferBytes -= _evictBufferBudget(
        _bufferBudgetEntries(isFillExtrusion: false),
        maxBytes: _regularBufferBudgetBytes,
      );
    }

    final hasRecentFillExtrusionWorkingSet = recentFillExtrusionBufferBytes > 0;
    if (hasRecentFillExtrusionWorkingSet) {
      _lastFillExtrusionRecentUseFrame = _frame;
    }
    final fillExtrusionTargetBudgetBytes =
        gpuFillExtrusionBudgetForWorkingSetBytes(
          recentFillExtrusionBufferBytes,
        );
    _fillExtrusionBudgetBytes = gpuFillExtrusionBudgetWithHysteresis(
      currentBudgetBytes: _fillExtrusionBudgetBytes,
      targetBudgetBytes: fillExtrusionTargetBudgetBytes,
      hasRecentWorkingSet: hasRecentFillExtrusionWorkingSet,
      framesSinceRecentUse: _frame - _lastFillExtrusionRecentUseFrame,
    );
    if (fillExtrusionBufferBytes > _fillExtrusionBudgetBytes) {
      fillExtrusionBufferBytes -= _evictBufferBudget(
        _bufferBudgetEntries(isFillExtrusion: true),
        maxBytes: _fillExtrusionBudgetBytes,
      );
    }

    var textureBytes = 0;
    for (final entry in _textureCache.values) {
      textureBytes += entry.lengthInBytes;
    }
    if (textureBytes > GpuCachePolicy.textureCacheBudgetBytes) {
      final textureEntries = <GpuTextureCacheKey, _BudgetEntry>{
        for (final entry in _textureCache.entries)
          entry.key: (
            lastUsed: entry.value.lastUsed,
            bytes: entry.value.lengthInBytes,
          ),
      };
      for (final key in gpuCacheBudgetVictims(
        textureEntries,
        currentFrame: _frame,
        maxBytes: GpuCachePolicy.textureCacheBudgetBytes,
      )) {
        final removed = _textureCache.remove(key);
        if (removed != null) {
          textureBytes -= removed.lengthInBytes;
          timingMetrics.recordBudgetEviction(bytes: removed.lengthInBytes);
          _evictionMetrics.recordBudget(.texture, removed.lengthInBytes);
        }
      }
    }
    _budgetDirty =
        gpuCacheBudgetNeedsRetry(
          residentBytes: regularBufferBytes,
          maxBytes: _regularBufferBudgetBytes,
        ) ||
        gpuCacheBudgetNeedsRetry(
          residentBytes: fillExtrusionBufferBytes,
          maxBytes: _fillExtrusionBudgetBytes,
        ) ||
        gpuCacheBudgetNeedsRetry(
          residentBytes: textureBytes,
          maxBytes: GpuCachePolicy.textureCacheBudgetBytes,
        );
    _evictionMetrics.logIfDue(_frame);
  }

  Map<_BufferBudgetKey, _BudgetEntry> _bufferBudgetEntries({
    required bool isFillExtrusion,
  }) => {
    for (final entry in _vertexCache.entries)
      if (entry.value.isFillExtrusion == isFillExtrusion)
        _VertexBufferBudgetKey(entry.key): (
          lastUsed: entry.value.lastUsed,
          bytes: entry.value.lengthInBytes,
        ),
    for (final entry in _indexCache.entries)
      if (entry.value.isFillExtrusion == isFillExtrusion)
        _IndexBufferBudgetKey(entry.key): (
          lastUsed: entry.value.lastUsed,
          bytes: entry.value.lengthInBytes,
        ),
  };

  int _evictBufferBudget(
    Map<_BufferBudgetKey, _BudgetEntry> entries, {
    required int maxBytes,
  }) {
    var removedBytes = 0;
    for (final key in gpuCacheBudgetVictims(
      entries,
      currentFrame: _frame,
      maxBytes: maxBytes,
    )) {
      GpuBufferEntry? removed;
      GpuCacheClass resourceClass;
      switch (key) {
        case _VertexBufferBudgetKey(:final cacheKey):
          resourceClass = gpuCacheClassForShader(cacheKey.shader);
          removed = _vertexCache.remove(cacheKey);
        case _IndexBufferBudgetKey(:final cacheKey):
          final existing = _indexCache[cacheKey];
          resourceClass = existing?.isFillExtrusion == true
              ? .fillExtrusion
              : .indexBuffer;
          removed = _indexCache.remove(cacheKey);
      }
      if (removed != null) {
        removedBytes += removed.lengthInBytes;
        switch (key) {
          case _VertexBufferBudgetKey(:final cacheKey):
            if (removed.isFillExtrusion) {
              _fillExtrusionVertexMissTracker.recordEviction(
                key: cacheKey,
                kind: .budget,
              );
            }
          case _IndexBufferBudgetKey(:final cacheKey):
            if (removed.isFillExtrusion) {
              _fillExtrusionIndexMissTracker.recordEviction(
                key: cacheKey,
                kind: .budget,
              );
            }
        }
        removed._releasePooledAllocation(_frame);
        timingMetrics.recordBudgetEviction(bytes: removed.lengthInBytes);
        _evictionMetrics.recordBudget(resourceClass, removed.lengthInBytes);
      }
    }
    return removedBytes;
  }

  void dispose() {
    _evictionMetrics.clear();
    _regularBufferBudgetBytes = GpuCachePolicy.regularMinBufferCacheBudgetBytes;
    _lastRegularBufferBudgetGrowthFrame = 0;
    _fillExtrusionBudgetBytes =
        GpuCachePolicy.fillExtrusionMinBufferCacheBudgetBytes;
    _lastFillExtrusionRecentUseFrame = 0;
    _budgetDirty = false;
  }
}

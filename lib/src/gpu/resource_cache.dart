import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../native/draw_command.dart';
import 'persistent_buffer_pool.dart';
import 'resource_cache_keys.dart';
import 'resource_cache_policy.dart';
import 'resource_metrics.dart';
import 'resource_miss_tracker.dart';

export 'resource_cache_keys.dart';
export 'resource_cache_policy.dart'
    hide GpuCacheClass, GpuCachePolicy, gpuCacheClassForShader;

sealed class const _BufferBudgetKey();

final class const _VertexBufferBudgetKey(final GpuVertexBufferCacheKey cacheKey)
    extends _BufferBudgetKey;

final class const _IndexBufferBudgetKey(final GpuIndexBufferCacheKey cacheKey)
    extends _BufferBudgetKey;

typedef _BudgetEntry = ({int lastUsed, int bytes});

final class _EvictionClassTotals {
  int count = 0;
  int bytes = 0;
}

/// A cached device buffer and the metadata used to manage its lifetime.
class GpuBufferEntry(
  /// The cached GPU buffer.
  final gpu.DeviceBuffer buffer,

  /// Number of bytes available through [view].
  final int lengthInBytes, {

  /// Whether this buffer uses the fill extrusion retention policy.
  final bool isFillExtrusion = false,

  /// Byte offset of this entry inside [buffer].
  final int offsetInBytes = 0,
  GpuPersistentBufferAllocation? pooledAllocation,
}) {
  GpuPersistentBufferAllocation? _pooledAllocation = pooledAllocation;

  /// Frame in which this entry was most recently requested.
  int lastUsed = 0;

  /// A view covering this entry's range inside [buffer].
  late final view = gpu.BufferView(
    buffer,
    offsetInBytes: offsetInBytes,
    lengthInBytes: lengthInBytes,
  );

  void _releasePooledAllocation(int frame) {
    final allocation = _pooledAllocation;
    if (allocation == null) return;
    _pooledAllocation = null;
    allocation.release(frame);
  }
}

/// A cached texture and the metadata used to manage its lifetime.
class GpuTextureEntry(
  /// The cached GPU texture.
  final gpu.Texture texture,

  /// Number of source bytes represented by [texture].
  final int lengthInBytes,
) {
  /// Frame in which this entry was most recently requested.
  int lastUsed = 0;
}

/// Current cache occupancy sampled when the renderer emits its periodic log.
final class const GpuResourceCacheSizeSnapshot({
  required final int vertexCount,
  required final int vertexBytes,
  required final int indexCount,
  required final int indexBytes,
  required final int textureCount,
  required final int textureBytes,
}) {
  int get totalBytes => vertexBytes + indexBytes + textureBytes;
}

/// Caches GPU buffers and textures across rendered frames.
///
/// Entries remain alive while submitted frames may reference them. Unused
/// entries are removed by age or when a cache exceeds its byte budget.
class GpuResourceCache {
  // Vertex cache includes every value that can alter the repacked bytes.
  // A raw pointer alone is unsafe because freed tile memory can be reallocated
  // at the same address. The same address and generation can also be presented
  // through different GPU layouts.
  final Map<GpuVertexBufferCacheKey, GpuBufferEntry> _vertexCache = {};
  final Map<GpuIndexBufferCacheKey, GpuBufferEntry> _indexCache = {};

  // Texture IDs and versions form the GPU texture cache key. The native side
  // changes the version when pixel contents change so stale data is not reused.
  final Map<GpuTextureCacheKey, GpuTextureEntry> _textureCache = {};

  /// Interval metrics shared with the renderer's repack/upload instrumentation.
  final GpuResourceTimingMetrics timingMetrics = GpuResourceTimingMetrics();
  final _bufferPool = GpuPersistentBufferPool();
  final _fillExtrusionVertexMissTracker =
      GpuCacheMissTracker<GpuVertexBufferCacheKey>(
        idOf: (key) => key.bufferId,
        versionOf: (key) => key.bufferVersion,
      );
  final _fillExtrusionIndexMissTracker =
      GpuCacheMissTracker<GpuIndexBufferCacheKey>(
        idOf: (key) => key.bufferId,
        versionOf: (key) => key.bufferVersion,
      );

  final Map<GpuCacheClass, _EvictionClassTotals> _expiryEvictionsByClass = {};
  final Map<GpuCacheClass, _EvictionClassTotals> _budgetEvictionsByClass = {};
  final Map<GpuCacheExpiryReason, _EvictionClassTotals>
  _expiryEvictionsByReason = {};
  var _frame = 0;
  var _evictionClassLogFrame = 0;
  var _regularBufferBudgetBytes =
      GpuCachePolicy.regularMinBufferCacheBudgetBytes;
  var _lastRegularBufferBudgetGrowthFrame = 0;
  var _fillExtrusionBudgetBytes =
      GpuCachePolicy.fillExtrusionMinBufferCacheBudgetBytes;
  var _lastFillExtrusionRecentUseFrame = 0;
  var _budgetDirty = false;

  /// Current cache sizes. This walks the maps only when the periodic log asks.
  GpuResourceCacheSizeSnapshot get sizeSnapshot => .new(
    vertexCount: _vertexCache.length,
    vertexBytes: _vertexCache.values.fold<int>(
      0,
      (total, entry) => total + entry.lengthInBytes,
    ),
    indexCount: _indexCache.length,
    indexBytes: _indexCache.values.fold<int>(
      0,
      (total, entry) => total + entry.lengthInBytes,
    ),
    textureCount: _textureCache.length,
    textureBytes: _textureCache.values.fold<int>(
      0,
      (total, entry) => total + entry.lengthInBytes,
    ),
  );

  /// Uploads a cache-owned buffer, pooling payloads up to 256 KiB.
  GpuBufferEntry uploadCachedBuffer(
    Uint8List bytes, {
    bool isFillExtrusion = false,
  }) {
    final allocation = _bufferPool.allocate(bytes, frame: _frame);
    if (allocation != null) {
      return .new(
        allocation.buffer,
        bytes.lengthInBytes,
        isFillExtrusion: isFillExtrusion,
        offsetInBytes: allocation.offsetInBytes,
        pooledAllocation: allocation,
      );
    }
    return .new(
      gpu.gpuContext.createDeviceBufferWithCopy(ByteData.sublistView(bytes)),
      bytes.lengthInBytes,
      isFillExtrusion: isFillExtrusion,
    );
  }

  /// Returns interval allocation activity for the persistent small-buffer pool.
  GpuPersistentBufferPoolSnapshot takeBufferPoolSnapshotAndReset() {
    final snapshot = _bufferPool.takeSnapshotAndReset();
    logGpuFillExtrusionMissClasses(
      vertex: _fillExtrusionVertexMissTracker.takeSnapshotAndReset(),
      index: _fillExtrusionIndexMissTracker.takeSnapshotAndReset(),
    );

    return snapshot;
  }

  /// Advances the frame used for cache lifetime tracking.
  void beginFrame() {
    _frame += 1;
    _bufferPool.beginFrame(_frame);
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

  /// Returns the vertex buffer for [key] and marks it as used this frame.
  GpuBufferEntry? vertexBuffer(GpuVertexBufferCacheKey key) {
    final cacheKey = gpuCanonicalVertexBufferCacheKey(key);
    final entry = _vertexCache[cacheKey];
    timingMetrics.recordVertexLookup(
      hit: entry != null,
      shader: key.shader,
      sourceStride: key.sourceStride,
      gpuStride: key.gpuStride,
      vertexCount: key.vertexCount,
    );
    if (key.shader == ShaderType.fillExtrusion) {
      _fillExtrusionVertexMissTracker.recordLookup(
        key: cacheKey,
        hit: entry != null,
      );
    }
    if (entry != null) {
      entry.lastUsed = _frame;
      if (key.shader == ShaderType.fillExtrusion) {
        _lastFillExtrusionRecentUseFrame = _frame;
      }
    }
    return entry;
  }

  /// Stores a vertex buffer under [key].
  void storeVertexBuffer(GpuVertexBufferCacheKey key, GpuBufferEntry entry) {
    final cacheKey = gpuCanonicalVertexBufferCacheKey(key);
    entry.lastUsed = _frame;
    if (key.shader == ShaderType.fillExtrusion) {
      _lastFillExtrusionRecentUseFrame = _frame;
      _fillExtrusionVertexMissTracker.recordStore(
        key: cacheKey,
        bytes: entry.lengthInBytes,
        classify: true,
      );
    }
    final previous = _vertexCache[cacheKey];
    if (previous != null && !identical(previous, entry)) {
      previous._releasePooledAllocation(_frame);
    }
    _vertexCache[cacheKey] = entry;
    _budgetDirty = true;
  }

  /// Returns the index buffer for [key] and marks it as used this frame.
  GpuBufferEntry? indexBuffer(GpuIndexBufferCacheKey key) {
    final cacheKey = gpuCanonicalIndexBufferCacheKey(key);
    final entry = _indexCache[cacheKey];
    timingMetrics.recordIndexLookup(hit: entry != null);
    if (entry == null || entry.isFillExtrusion) {
      _fillExtrusionIndexMissTracker.recordLookup(
        key: cacheKey,
        hit: entry != null,
      );
    }
    if (entry != null) {
      entry.lastUsed = _frame;
      if (entry.isFillExtrusion) {
        _lastFillExtrusionRecentUseFrame = _frame;
      }
    }
    return entry;
  }

  /// Stores an index buffer under [key].
  void storeIndexBuffer(GpuIndexBufferCacheKey key, GpuBufferEntry entry) {
    final cacheKey = gpuCanonicalIndexBufferCacheKey(key);
    entry.lastUsed = _frame;
    _fillExtrusionIndexMissTracker.recordStore(
      key: cacheKey,
      bytes: entry.lengthInBytes,
      classify: entry.isFillExtrusion,
    );
    if (entry.isFillExtrusion) {
      _lastFillExtrusionRecentUseFrame = _frame;
    }
    final previous = _indexCache[cacheKey];
    if (previous != null && !identical(previous, entry)) {
      previous._releasePooledAllocation(_frame);
    }
    _indexCache[cacheKey] = entry;
    _budgetDirty = true;
  }

  /// Returns the texture for [key] and marks it as used this frame.
  GpuTextureEntry? texture(GpuTextureCacheKey key) {
    final entry = _textureCache[key];
    timingMetrics.recordTextureLookup(hit: entry != null);
    if (entry != null) entry.lastUsed = _frame;

    return entry;
  }

  /// Stores a texture under [key] and marks it as used this frame.
  void storeTexture(GpuTextureCacheKey key, GpuTextureEntry entry) {
    entry.lastUsed = _frame;
    _textureCache[key] = entry;
    _budgetDirty = true;
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
        _recordEvictionClass(
          _expiryEvictionsByClass,
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
        _recordEvictionClass(
          _expiryEvictionsByClass,
          value.isFillExtrusion ? .fillExtrusion : .indexBuffer,
          value.lengthInBytes,
        );
      }

      void recordTextureExpiry(GpuTextureCacheKey key, GpuTextureEntry value) {
        expiredCount += 1;
        expiredBytes += value.lengthInBytes;
        _recordEvictionClass(
          _expiryEvictionsByClass,
          .texture,
          value.lengthInBytes,
        );
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
            _recordExpiryReason(reason, value.lengthInBytes),
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
            _recordExpiryReason(reason, value.lengthInBytes),
      );
      evictExpiredCacheVersions(
        _textureCache,
        frame: _frame,
        idOf: (key) => key.textureId,
        versionOf: (key) => key.textureVersion,
        lastUsedOf: (value) => value.lastUsed,
        onEvict: recordTextureExpiry,
        onEvictReason: (_, value, reason) =>
            _recordExpiryReason(reason, value.lengthInBytes),
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
      _logEvictionClassesIfDue();
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
          _recordEvictionClass(
            _budgetEvictionsByClass,
            .texture,
            removed.lengthInBytes,
          );
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
    _logEvictionClassesIfDue();
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
        _recordEvictionClass(
          _budgetEvictionsByClass,
          resourceClass,
          removed.lengthInBytes,
        );
      }
    }
    return removedBytes;
  }

  void _recordEvictionClass(
    Map<GpuCacheClass, _EvictionClassTotals> totals,
    GpuCacheClass resourceClass,
    int bytes,
  ) {
    final value = totals.putIfAbsent(resourceClass, _EvictionClassTotals.new);
    value
      ..count += 1
      ..bytes += bytes;
  }

  void _recordExpiryReason(GpuCacheExpiryReason reason, int bytes) {
    final value = _expiryEvictionsByReason.putIfAbsent(
      reason,
      _EvictionClassTotals.new,
    );
    value
      ..count += 1
      ..bytes += bytes;
  }

  void _logEvictionClassesIfDue() {
    if (_frame - _evictionClassLogFrame <
        GpuCachePolicy.evictionClassLogFrames) {
      return;
    }
    _evictionClassLogFrame = _frame;
    if (_expiryEvictionsByClass.isEmpty && _budgetEvictionsByClass.isEmpty) {
      return;
    }

    String megabytes(int bytes) =>
        '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    String className(GpuCacheClass resourceClass) => switch (resourceClass) {
      .line => 'line',
      .fillExtrusion => 'fe',
      .other => 'other',
      .indexBuffer => 'idx',
      .texture => 'tex',
    };
    String describe(Map<GpuCacheClass, _EvictionClassTotals> totals) {
      final values = <String>[];
      for (final resourceClass in GpuCacheClass.values) {
        final value = totals[resourceClass];
        if (value == null || value.count == 0) continue;
        values.add(
          '${className(resourceClass)}:${value.count}/${megabytes(value.bytes)}',
        );
      }
      return values.isEmpty ? 'none' : values.join(' ');
    }

    String describeReasons() {
      final values = <String>[];
      for (final reason in GpuCacheExpiryReason.values) {
        final value = _expiryEvictionsByReason[reason];
        if (value == null || value.count == 0) continue;
        final name = switch (reason) {
          .superseded => 'superseded',
          .unused => 'age',
        };
        values.add('$name:${value.count}/${megabytes(value.bytes)}');
      }
      return values.isEmpty ? 'none' : values.join(' ');
    }

    debugPrint(
      '[GpuEvictClass] expiry=${describe(_expiryEvictionsByClass)} '
      'budget=${describe(_budgetEvictionsByClass)} '
      'reason=${describeReasons()}',
    );
    _expiryEvictionsByClass.clear();
    _budgetEvictionsByClass.clear();
    _expiryEvictionsByReason.clear();
  }

  /// Removes every cached resource reference.
  void dispose() {
    for (final entry in _vertexCache.values) {
      entry._releasePooledAllocation(_frame);
    }
    for (final entry in _indexCache.values) {
      entry._releasePooledAllocation(_frame);
    }
    _vertexCache.clear();
    _indexCache.clear();
    _textureCache.clear();
    _bufferPool.dispose();
    _fillExtrusionVertexMissTracker.clear();
    _fillExtrusionIndexMissTracker.clear();
    _expiryEvictionsByClass.clear();
    _budgetEvictionsByClass.clear();
    _expiryEvictionsByReason.clear();
    _regularBufferBudgetBytes = GpuCachePolicy.regularMinBufferCacheBudgetBytes;
    _lastRegularBufferBudgetGrowthFrame = 0;
    _fillExtrusionBudgetBytes =
        GpuCachePolicy.fillExtrusionMinBufferCacheBudgetBytes;
    _lastFillExtrusionRecentUseFrame = 0;
    _budgetDirty = false;
  }
}

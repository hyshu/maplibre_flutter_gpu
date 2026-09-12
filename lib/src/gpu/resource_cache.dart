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

part 'cache/resource_entries.dart';
part 'cache/maintenance.dart';
part 'cache/eviction_metrics.dart';

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

  var _frame = 0;
  late final _maintenance = _GpuCacheMaintenance(
    vertexCache: _vertexCache,
    indexCache: _indexCache,
    textureCache: _textureCache,
    timingMetrics: timingMetrics,
    vertexMissTracker: _fillExtrusionVertexMissTracker,
    indexMissTracker: _fillExtrusionIndexMissTracker,
  );

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
    _maintenance.beginFrame(_frame);
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
        _maintenance.recordFillExtrusionUse();
      }
    }
    return entry;
  }

  /// Stores a vertex buffer under [key].
  void storeVertexBuffer(GpuVertexBufferCacheKey key, GpuBufferEntry entry) {
    final cacheKey = gpuCanonicalVertexBufferCacheKey(key);
    entry.lastUsed = _frame;
    if (key.shader == ShaderType.fillExtrusion) {
      _maintenance.recordFillExtrusionUse();
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
    _maintenance.markDirty();
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
        _maintenance.recordFillExtrusionUse();
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
      _maintenance.recordFillExtrusionUse();
    }
    final previous = _indexCache[cacheKey];
    if (previous != null && !identical(previous, entry)) {
      previous._releasePooledAllocation(_frame);
    }
    _indexCache[cacheKey] = entry;
    _maintenance.markDirty();
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
    _maintenance.markDirty();
  }

  /// Removes expired entries and enforces cache byte budgets.
  void evictCaches() => _maintenance.evictCaches();

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
    _maintenance.dispose();
  }
}

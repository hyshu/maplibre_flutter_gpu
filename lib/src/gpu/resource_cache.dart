import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../native/draw_command.dart';
import 'resource_metrics.dart';

/// Values that uniquely identify repacked vertex data in the GPU cache.
typedef GpuVertexBufferCacheKey = ({
  int bufferId,
  int bufferVersion,
  int dataAddress,
  int vertexCount,
  int sourceStride,
  int shader,
  int gpuStride,
});

/// Values that uniquely identify index data in the GPU cache.
typedef GpuIndexBufferCacheKey = ({
  int bufferId,
  int bufferVersion,
  int dataAddress,
});

/// Values that uniquely identify pixel data in the GPU texture cache.
typedef GpuTextureCacheKey = ({int textureId, int textureVersion});

sealed class _BufferBudgetKey {
  const _BufferBudgetKey();
}

final class _VertexBufferBudgetKey extends _BufferBudgetKey {
  const _VertexBufferBudgetKey(this.cacheKey);

  final GpuVertexBufferCacheKey cacheKey;
}

final class _IndexBufferBudgetKey extends _BufferBudgetKey {
  const _IndexBufferBudgetKey(this.cacheKey);

  final GpuIndexBufferCacheKey cacheKey;
}

typedef _BudgetEntry = ({int lastUsed, int bytes});

enum _GpuCacheClass { line, fillExtrusion, other, indexBuffer, texture }

final class _EvictionClassTotals {
  int count = 0;
  int bytes = 0;
}

_GpuCacheClass _gpuCacheClassForShader(int shader) => switch (shader) {
  ShaderType.line ||
  ShaderType.lineSDF ||
  ShaderType.lineGradient ||
  ShaderType.linePattern => _GpuCacheClass.line,
  ShaderType.fillExtrusion => _GpuCacheClass.fillExtrusion,
  _ => _GpuCacheClass.other,
};

/// A cached device buffer and the metadata used to manage its lifetime.
class GpuBufferEntry {
  /// The cached GPU buffer.
  final gpu.DeviceBuffer buffer;

  /// Number of bytes available through [view].
  final int lengthInBytes;

  /// Whether this buffer uses the fill extrusion retention policy.
  final bool isFillExtrusion;

  /// Frame in which this entry was most recently requested.
  int lastUsed = 0;

  /// A view covering the complete [buffer].
  late final gpu.BufferView view = gpu.BufferView(
    buffer,
    offsetInBytes: 0,
    lengthInBytes: lengthInBytes,
  );

  /// Creates an entry for [buffer].
  GpuBufferEntry(
    this.buffer,
    this.lengthInBytes, {
    this.isFillExtrusion = false,
  });
}

/// A cached texture and the metadata used to manage its lifetime.
class GpuTextureEntry {
  /// The cached GPU texture.
  final gpu.Texture texture;

  /// Number of source bytes represented by [texture].
  final int lengthInBytes;

  /// Frame in which this entry was most recently requested.
  int lastUsed = 0;

  /// Creates an entry for [texture].
  GpuTextureEntry(this.texture, this.lengthInBytes);
}

/// Current cache occupancy sampled when the renderer emits its periodic log.
final class GpuResourceCacheSizeSnapshot {
  const GpuResourceCacheSizeSnapshot({
    required this.vertexCount,
    required this.vertexBytes,
    required this.indexCount,
    required this.indexBytes,
    required this.textureCount,
    required this.textureBytes,
  });

  final int vertexCount;
  final int vertexBytes;
  final int indexCount;
  final int indexBytes;
  final int textureCount;
  final int textureBytes;

  int get totalBytes => vertexBytes + indexBytes + textureBytes;
}

const _gpuFramesInFlight = 4;
const _gpuUnusedRetentionFrames = 60;
const _gpuFillExtrusionUnusedRetentionFrames = 600;
const _gpuBufferCacheBudgetBytes = 64 * 1024 * 1024;
const _gpuFillExtrusionBufferCacheBudgetBytes = 64 * 1024 * 1024;
const _gpuTextureCacheBudgetBytes = 64 * 1024 * 1024;
const _gpuEvictionClassLogFrames = 60;

/// Whether expiry maintenance is due on [frame].
@visibleForTesting
bool gpuCacheExpiryMaintenanceDue(
  int frame, {
  int interval = _gpuFramesInFlight,
}) => frame % interval == 0;

/// Whether a cache entry can be removed on [frame].
///
/// Superseded entries expire after in-flight frames have finished. Other
/// entries expire after [unusedRetentionFrames] without use.
@visibleForTesting
bool gpuCacheEntryExpired({
  required int frame,
  required int lastUsed,
  required bool superseded,
  int unusedRetentionFrames = _gpuUnusedRetentionFrames,
}) {
  final age = frame - lastUsed;

  return age >= unusedRetentionFrames ||
      (superseded && age >= _gpuFramesInFlight);
}

/// Selects entries to remove until the remaining size does not exceed
/// [maxBytes].
///
/// Entries used in [currentFrame] are never selected. Older entries take
/// priority, followed by larger entries when their last-use frames match.
@visibleForTesting
List<K> gpuCacheBudgetVictims<K>(
  Map<K, ({int lastUsed, int bytes})> entries, {
  required int currentFrame,
  required int maxBytes,
}) {
  var totalBytes = entries.values.fold<int>(
    0,
    (total, entry) => total + entry.bytes,
  );
  if (totalBytes <= maxBytes) return <K>[];

  final candidates =
      entries.entries
          .where((entry) => entry.value.lastUsed < currentFrame)
          .toList(growable: false)
        ..sort((a, b) {
          final ageOrder = a.value.lastUsed.compareTo(b.value.lastUsed);
          if (ageOrder != 0) return ageOrder;

          return b.value.bytes.compareTo(a.value.bytes);
        });
  final victims = <K>[];
  for (final candidate in candidates) {
    if (totalBytes <= maxBytes) break;
    victims.add(candidate.key);
    totalBytes -= candidate.value.bytes;
  }
  return victims;
}

/// Removes expired versions from [cache].
///
/// For each resource ID, the most recently used version is treated as current.
@visibleForTesting
void evictExpiredCacheVersions<K, V>(
  Map<K, V> cache, {
  required int frame,
  required int Function(K key) idOf,
  required int Function(K key) versionOf,
  required int Function(V value) lastUsedOf,
  int Function(V value)? unusedRetentionFramesOf,
  void Function(K key, V value)? onEvict,
}) {
  final latestVersion = <int, int>{};
  final latestUse = <int, int>{};
  for (final entry in cache.entries) {
    final id = idOf(entry.key);
    final used = lastUsedOf(entry.value);
    if (used >= (latestUse[id] ?? -1)) {
      latestUse[id] = used;
      latestVersion[id] = versionOf(entry.key);
    }
  }
  cache.removeWhere((key, value) {
    final expired = gpuCacheEntryExpired(
      frame: frame,
      lastUsed: lastUsedOf(value),
      superseded: versionOf(key) != latestVersion[idOf(key)],
      unusedRetentionFrames:
          unusedRetentionFramesOf?.call(value) ?? _gpuUnusedRetentionFrames,
    );
    if (expired) onEvict?.call(key, value);

    return expired;
  });
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

  final Map<_GpuCacheClass, _EvictionClassTotals> _expiryEvictionsByClass = {};
  final Map<_GpuCacheClass, _EvictionClassTotals> _budgetEvictionsByClass = {};
  var _frame = 0;
  var _evictionClassLogFrame = 0;
  var _budgetDirty = false;

  /// Current cache sizes. This walks the maps only when the periodic log asks.
  GpuResourceCacheSizeSnapshot get sizeSnapshot => GpuResourceCacheSizeSnapshot(
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

  /// Advances the frame used for cache lifetime tracking.
  void beginFrame() {
    _frame += 1;
  }

  /// Returns the vertex buffer for [key] and marks it as used this frame.
  GpuBufferEntry? vertexBuffer(GpuVertexBufferCacheKey key) {
    final entry = _vertexCache[key];
    timingMetrics.recordVertexLookup(
      hit: entry != null,
      shader: key.shader,
      sourceStride: key.sourceStride,
      gpuStride: key.gpuStride,
      vertexCount: key.vertexCount,
    );
    if (entry != null) entry.lastUsed = _frame;

    return entry;
  }

  /// Stores a vertex buffer under [key].
  void storeVertexBuffer(GpuVertexBufferCacheKey key, GpuBufferEntry entry) {
    entry.lastUsed = _frame;
    _vertexCache[key] = entry;
    _budgetDirty = true;
  }

  /// Returns the index buffer for [key] and marks it as used this frame.
  GpuBufferEntry? indexBuffer(GpuIndexBufferCacheKey key) {
    final entry = _indexCache[key];
    timingMetrics.recordIndexLookup(hit: entry != null);
    if (entry != null) entry.lastUsed = _frame;

    return entry;
  }

  /// Stores an index buffer under [key].
  void storeIndexBuffer(GpuIndexBufferCacheKey key, GpuBufferEntry entry) {
    entry.lastUsed = _frame;
    _indexCache[key] = entry;
    _budgetDirty = true;
  }

  /// Returns the texture for [key] and marks it as used this frame.
  GpuTextureEntry? texture(GpuTextureCacheKey key) {
    final entry = _textureCache[key];
    timingMetrics.recordTextureLookup(hit: entry != null);
    if (entry != null) entry.lastUsed = _frame;

    return entry;
  }

  /// Stores a texture under [key].
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
        expiredCount += 1;
        expiredBytes += value.lengthInBytes;
        _recordEvictionClass(
          _expiryEvictionsByClass,
          _gpuCacheClassForShader(key.shader),
          value.lengthInBytes,
        );
      }
      void recordIndexExpiry(
        GpuIndexBufferCacheKey key,
        GpuBufferEntry value,
      ) {
        expiredCount += 1;
        expiredBytes += value.lengthInBytes;
        _recordEvictionClass(
          _expiryEvictionsByClass,
          value.isFillExtrusion
              ? _GpuCacheClass.fillExtrusion
              : _GpuCacheClass.indexBuffer,
          value.lengthInBytes,
        );
      }
      void recordTextureExpiry(GpuTextureCacheKey key, GpuTextureEntry value) {
        expiredCount += 1;
        expiredBytes += value.lengthInBytes;
        _recordEvictionClass(
          _expiryEvictionsByClass,
          _GpuCacheClass.texture,
          value.lengthInBytes,
        );
      }

      evictExpiredCacheVersions(
        _vertexCache,
        frame: _frame,
        idOf: (key) => key.bufferId,
        versionOf: (key) => key.bufferVersion,
        lastUsedOf: (value) => value.lastUsed,
        unusedRetentionFramesOf: (value) => value.isFillExtrusion
            ? _gpuFillExtrusionUnusedRetentionFrames
            : _gpuUnusedRetentionFrames,
        onEvict: recordVertexExpiry,
      );
      evictExpiredCacheVersions(
        _indexCache,
        frame: _frame,
        idOf: (key) => key.bufferId,
        versionOf: (key) => key.bufferVersion,
        lastUsedOf: (value) => value.lastUsed,
        unusedRetentionFramesOf: (value) => value.isFillExtrusion
            ? _gpuFillExtrusionUnusedRetentionFrames
            : _gpuUnusedRetentionFrames,
        onEvict: recordIndexExpiry,
      );
      evictExpiredCacheVersions(
        _textureCache,
        frame: _frame,
        idOf: (key) => key.textureId,
        versionOf: (key) => key.textureVersion,
        lastUsedOf: (value) => value.lastUsed,
        onEvict: recordTextureExpiry,
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
    var fillExtrusionBufferBytes = 0;
    for (final entry in _vertexCache.values) {
      if (entry.isFillExtrusion) {
        fillExtrusionBufferBytes += entry.lengthInBytes;
      } else {
        regularBufferBytes += entry.lengthInBytes;
      }
    }
    for (final entry in _indexCache.values) {
      if (entry.isFillExtrusion) {
        fillExtrusionBufferBytes += entry.lengthInBytes;
      } else {
        regularBufferBytes += entry.lengthInBytes;
      }
    }
    if (regularBufferBytes > _gpuBufferCacheBudgetBytes) {
      _evictBufferBudget(
        _bufferBudgetEntries(isFillExtrusion: false),
        maxBytes: _gpuBufferCacheBudgetBytes,
      );
    }
    if (fillExtrusionBufferBytes > _gpuFillExtrusionBufferCacheBudgetBytes) {
      _evictBufferBudget(
        _bufferBudgetEntries(isFillExtrusion: true),
        maxBytes: _gpuFillExtrusionBufferCacheBudgetBytes,
      );
    }

    var textureBytes = 0;
    for (final entry in _textureCache.values) {
      textureBytes += entry.lengthInBytes;
    }
    if (textureBytes > _gpuTextureCacheBudgetBytes) {
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
        maxBytes: _gpuTextureCacheBudgetBytes,
      )) {
        final removed = _textureCache.remove(key);
        if (removed != null) {
          timingMetrics.recordBudgetEviction(bytes: removed.lengthInBytes);
          _recordEvictionClass(
            _budgetEvictionsByClass,
            _GpuCacheClass.texture,
            removed.lengthInBytes,
          );
        }
      }
    }
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

  void _evictBufferBudget(
    Map<_BufferBudgetKey, _BudgetEntry> entries, {
    required int maxBytes,
  }) {
    for (final key in gpuCacheBudgetVictims(
      entries,
      currentFrame: _frame,
      maxBytes: maxBytes,
    )) {
      GpuBufferEntry? removed;
      _GpuCacheClass resourceClass;
      switch (key) {
        case _VertexBufferBudgetKey(:final cacheKey):
          resourceClass = _gpuCacheClassForShader(cacheKey.shader);
          removed = _vertexCache.remove(cacheKey);
        case _IndexBufferBudgetKey(:final cacheKey):
          final existing = _indexCache[cacheKey];
          resourceClass = existing?.isFillExtrusion == true
              ? _GpuCacheClass.fillExtrusion
              : _GpuCacheClass.indexBuffer;
          removed = _indexCache.remove(cacheKey);
      }
      if (removed != null) {
        timingMetrics.recordBudgetEviction(bytes: removed.lengthInBytes);
        _recordEvictionClass(
          _budgetEvictionsByClass,
          resourceClass,
          removed.lengthInBytes,
        );
      }
    }
  }

  void _recordEvictionClass(
    Map<_GpuCacheClass, _EvictionClassTotals> totals,
    _GpuCacheClass resourceClass,
    int bytes,
  ) {
    final value = totals.putIfAbsent(resourceClass, _EvictionClassTotals.new);
    value
      ..count += 1
      ..bytes += bytes;
  }

  void _logEvictionClassesIfDue() {
    if (_frame - _evictionClassLogFrame < _gpuEvictionClassLogFrames) return;
    _evictionClassLogFrame = _frame;
    if (_expiryEvictionsByClass.isEmpty && _budgetEvictionsByClass.isEmpty) {
      return;
    }

    String megabytes(int bytes) =>
        '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    String className(_GpuCacheClass resourceClass) => switch (resourceClass) {
      _GpuCacheClass.line => 'line',
      _GpuCacheClass.fillExtrusion => 'fe',
      _GpuCacheClass.other => 'other',
      _GpuCacheClass.indexBuffer => 'idx',
      _GpuCacheClass.texture => 'tex',
    };
    String describe(Map<_GpuCacheClass, _EvictionClassTotals> totals) {
      final values = <String>[];
      for (final resourceClass in _GpuCacheClass.values) {
        final value = totals[resourceClass];
        if (value == null || value.count == 0) continue;
        values.add(
          '${className(resourceClass)}:${value.count}/${megabytes(value.bytes)}',
        );
      }
      return values.isEmpty ? 'none' : values.join(' ');
    }

    debugPrint(
      '[GpuEvictClass] expiry=${describe(_expiryEvictionsByClass)} '
      'budget=${describe(_budgetEvictionsByClass)}',
    );
    _expiryEvictionsByClass.clear();
    _budgetEvictionsByClass.clear();
  }

  /// Removes every cached resource reference.
  void dispose() {
    _vertexCache.clear();
    _indexCache.clear();
    _textureCache.clear();
    _expiryEvictionsByClass.clear();
    _budgetEvictionsByClass.clear();
    _budgetDirty = false;
  }
}

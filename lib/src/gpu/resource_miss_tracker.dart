import 'package:flutter/foundation.dart';

/// Why a cache-owned GPU buffer had to be uploaded again.
enum GpuCacheMissReason {
  /// This resource ID has never been observed before.
  newBuffer,

  /// The same resource ID was observed with a different content version.
  versionChange,

  /// The resource ID/version pair is unchanged, but another key field changed.
  ///
  /// For vertices this includes native address, vertex count, or layout fields.
  /// For indices this normally means the native address changed. Tracking this
  /// separately exposes geometry-identity churn that a larger cache cannot fix.
  identityChange,

  /// The exact cache key was evicted by expiry and later requested again.
  expiryRevisit,

  /// The exact cache key was evicted by the byte budget and later requested again.
  budgetRevisit,
}

enum GpuCacheEvictionKind { expiry, budget }

/// One interval total for a cache-miss cause.
final class GpuCacheMissSnapshot {
  const GpuCacheMissSnapshot({
    required this.reason,
    required this.count,
    required this.bytes,
  });

  final GpuCacheMissReason reason;
  final int count;
  final int bytes;
}

final class _GpuCacheMissTotals {
  int count = 0;
  int bytes = 0;
}

const _gpuIdentityChangeSampleLimit = 4;

/// Bounded identity history used to classify cache misses without retaining GPU
/// resources or native memory.
final class GpuCacheMissTracker<K> {
  GpuCacheMissTracker({
    required this.idOf,
    required this.versionOf,
    this.historyLimit = 8192,
  }) {
    if (historyLimit <= 0) {
      throw RangeError.value(historyLimit, 'historyLimit', 'must be positive');
    }
  }

  final int Function(K key) idOf;
  final int Function(K key) versionOf;
  final int historyLimit;

  final Map<int, K> _lastSeenKeys = <int, K>{};
  final Map<K, GpuCacheEvictionKind> _evictedKeys = <K, GpuCacheEvictionKind>{};
  final Set<K> _pendingMisses = <K>{};
  final Map<GpuCacheMissReason, _GpuCacheMissTotals> _totals =
      <GpuCacheMissReason, _GpuCacheMissTotals>{};
  int _identityChangeSamplesLogged = 0;

  /// Records one lookup. A miss is classified later, when its uploaded byte
  /// size is known at [recordStore].
  void recordLookup({required K key, required bool hit}) {
    if (hit) {
      _rememberKey(idOf(key), key);
      return;
    }
    _pendingMisses.remove(key);
    _pendingMisses.add(key);
    while (_pendingMisses.length > historyLimit) {
      _pendingMisses.remove(_pendingMisses.first);
    }
  }

  /// Completes a pending miss after upload/store.
  ///
  /// [classify] is false for lookups that share this tracker temporarily but do
  /// not belong to the resource class being diagnosed.
  void recordStore({
    required K key,
    required int bytes,
    required bool classify,
  }) {
    if (bytes < 0) {
      throw RangeError.value(bytes, 'bytes', 'must not be negative');
    }
    if (!_pendingMisses.remove(key)) return;
    if (!classify) return;

    final id = idOf(key);
    final version = versionOf(key);
    final eviction = _evictedKeys.remove(key);
    final previousKey = _lastSeenKeys[id];
    final previousVersion = previousKey == null ? null : versionOf(previousKey);
    final reason = switch (eviction) {
      GpuCacheEvictionKind.expiry => GpuCacheMissReason.expiryRevisit,
      GpuCacheEvictionKind.budget => GpuCacheMissReason.budgetRevisit,
      null when previousVersion == null => GpuCacheMissReason.newBuffer,
      null when previousVersion != version => GpuCacheMissReason.versionChange,
      null => GpuCacheMissReason.identityChange,
    };

    if (reason == GpuCacheMissReason.identityChange &&
        previousKey != null &&
        _identityChangeSamplesLogged < _gpuIdentityChangeSampleLimit) {
      _identityChangeSamplesLogged += 1;
      debugPrint(
        '[GpuIdentityChange] id=$id version=$version '
        'previous=$previousKey current=$key',
      );
    }

    final totals = _totals.putIfAbsent(reason, _GpuCacheMissTotals.new);
    totals
      ..count += 1
      ..bytes += bytes;
    _rememberKey(id, key);
  }

  /// Remembers that [key] left the cache so an exact later reappearance can be
  /// distinguished from native identity/version churn.
  void recordEviction({required K key, required GpuCacheEvictionKind kind}) {
    _evictedKeys.remove(key);
    _evictedKeys[key] = kind;
    _trimMap(_evictedKeys);
  }

  /// Returns interval totals while retaining bounded identity history.
  List<GpuCacheMissSnapshot> takeSnapshotAndReset() {
    final snapshots = <GpuCacheMissSnapshot>[
      for (final reason in GpuCacheMissReason.values)
        if ((_totals[reason]?.count ?? 0) > 0)
          GpuCacheMissSnapshot(
            reason: reason,
            count: _totals[reason]!.count,
            bytes: _totals[reason]!.bytes,
          ),
    ];
    _totals.clear();
    _identityChangeSamplesLogged = 0;
    return List<GpuCacheMissSnapshot>.unmodifiable(snapshots);
  }

  void clear() {
    _lastSeenKeys.clear();
    _evictedKeys.clear();
    _pendingMisses.clear();
    _totals.clear();
    _identityChangeSamplesLogged = 0;
  }

  void _rememberKey(int id, K key) {
    _lastSeenKeys.remove(id);
    _lastSeenKeys[id] = key;
    _trimMap(_lastSeenKeys);
  }

  void _trimMap<K2, V2>(Map<K2, V2> values) {
    while (values.length > historyLimit) {
      values.remove(values.keys.first);
    }
  }
}

/// Emits one compact breakdown of fill-extrusion cache misses.
void logGpuFillExtrusionMissClasses({
  required List<GpuCacheMissSnapshot> vertex,
  required List<GpuCacheMissSnapshot> index,
}) {
  if (vertex.isEmpty && index.isEmpty) {
    debugPrint('[GpuMissClass] none');
    return;
  }

  String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  String name(GpuCacheMissReason reason) => switch (reason) {
    GpuCacheMissReason.newBuffer => 'new',
    GpuCacheMissReason.versionChange => 'version',
    GpuCacheMissReason.identityChange => 'identity',
    GpuCacheMissReason.expiryRevisit => 'expiry',
    GpuCacheMissReason.budgetRevisit => 'budget',
  };
  String describe(List<GpuCacheMissSnapshot> values) => values.isEmpty
      ? 'none'
      : values
            .map(
              (value) =>
                  '${name(value.reason)}:${value.count}/${megabytes(value.bytes)}',
            )
            .join(' ');

  debugPrint('[GpuMissClass] feV=${describe(vertex)} feI=${describe(index)}');
}

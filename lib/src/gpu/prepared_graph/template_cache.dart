part of '../prepared_graph.dart';

/// One cached graph topology and its renderer-owned structural payload.
typedef PreparedGraphTemplateCacheEntry<T> = ({PreparedGraphKey key, T value});

typedef _PreparedGraphTemplateBucketKey = ({
  int commandCount,
  int commandStride,
  int familyFingerprint,
});

final class const _PreparedGraphTemplateCacheValue<T>({
  required final _PreparedGraphTemplateBucketKey bucketKey,
  required final PreparedGraphKey key,
  required final T value,
});

/// Small LRU of previously decoded graph topologies.
final class PreparedGraphTemplateCache<T>({final int capacity = 4}) {
  this {
    if (capacity <= 0) {
      throw RangeError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final Map<
    _PreparedGraphTemplateBucketKey,
    List<_PreparedGraphTemplateCacheValue<T>>
  >
  _buckets = {};
  final List<_PreparedGraphTemplateCacheValue<T>> _recency = [];

  int get length => _recency.length;

  /// Remembers one reusable graph as the most recently displaced topology.
  void remember({required PreparedGraphKey key, required T value}) {
    if (!key.reusable) return;
    final bucketKey = (
      commandCount: key.commandCount,
      commandStride: key.commandStride,
      familyFingerprint: key.familyFingerprint,
    );
    final entries = _buckets.putIfAbsent(
      bucketKey,
      () => <_PreparedGraphTemplateCacheValue<T>>[],
    );
    for (var index = entries.length - 1; index >= 0; index -= 1) {
      final entry = entries[index];
      if (!entry.key.sameTopologyAs(key)) continue;
      entries.removeAt(index);
      _recency.remove(entry);
    }
    final entry = _PreparedGraphTemplateCacheValue(
      bucketKey: bucketKey,
      key: key,
      value: value,
    );
    entries.insert(0, entry);
    _recency.insert(0, entry);
    if (_recency.length > capacity) {
      final oldest = _recency.removeLast();
      final oldestBucket = _buckets[oldest.bucketKey]!;
      oldestBucket.remove(oldest);
      if (oldestBucket.isEmpty) _buckets.remove(oldest.bucketKey);
    }
  }

  /// Removes and returns the first cached topology matching this command block.
  PreparedGraphTemplateCacheEntry<T>? takeMatching({
    required Uint8List commandBytes,
    required int commandCount,
    required int commandStride,
  }) {
    final preservedMismatch = PreparedGraphTopologyDiagnostics._pendingMismatch;
    try {
      if (commandCount < 0 ||
          commandStride != DrawCommandAbi.size ||
          commandBytes.lengthInBytes < commandCount * commandStride) {
        return null;
      }
      final data = ByteData.sublistView(commandBytes);
      final bucketKey = (
        commandCount: commandCount,
        commandStride: commandStride,
        familyFingerprint: _topologyFamilyFingerprintFromBytes(
          data,
          commandCount,
          commandStride,
        ),
      );
      final entries = _buckets[bucketKey];
      if (entries == null) return null;
      for (var index = 0; index < entries.length; index += 1) {
        final entry = entries[index];
        if (entry.key.matches(
          commandBytes: commandBytes,
          commandCount: commandCount,
          commandStride: commandStride,
        )) {
          entries.removeAt(index);
          _recency.remove(entry);
          if (entries.isEmpty) _buckets.remove(bucketKey);

          return (key: entry.key, value: entry.value);
        }
      }
      return null;
    } finally {
      PreparedGraphTopologyDiagnostics._pendingMismatch = preservedMismatch;
    }
  }

  void clear() {
    _buckets.clear();
    _recency.clear();
  }
}

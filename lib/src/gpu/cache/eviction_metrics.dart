part of '../resource_cache.dart';

final class _EvictionClassTotals {
  int count = 0;
  int bytes = 0;
}

/// Accumulates eviction counts until the cache's diagnostic interval elapses.
final class _GpuCacheEvictionMetrics {
  final Map<GpuCacheClass, _EvictionClassTotals> _expiryEvictionsByClass = {};
  final Map<GpuCacheClass, _EvictionClassTotals> _budgetEvictionsByClass = {};
  final Map<GpuCacheExpiryReason, _EvictionClassTotals>
  _expiryEvictionsByReason = {};
  var _evictionClassLogFrame = 0;

  void recordExpiry(GpuCacheClass resourceClass, int bytes) =>
      _recordEvictionClass(_expiryEvictionsByClass, resourceClass, bytes);

  void recordBudget(GpuCacheClass resourceClass, int bytes) =>
      _recordEvictionClass(_budgetEvictionsByClass, resourceClass, bytes);

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

  void recordExpiryReason(GpuCacheExpiryReason reason, int bytes) {
    final value = _expiryEvictionsByReason.putIfAbsent(
      reason,
      _EvictionClassTotals.new,
    );
    value
      ..count += 1
      ..bytes += bytes;
  }

  void logIfDue(int frame) {
    if (frame - _evictionClassLogFrame <
        GpuCachePolicy.evictionClassLogFrames) {
      return;
    }
    _evictionClassLogFrame = frame;
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

  void clear() {
    _expiryEvictionsByClass.clear();
    _budgetEvictionsByClass.clear();
    _expiryEvictionsByReason.clear();
  }
}

part of '../prepared_graph.dart';

/// Timing totals for persistent graph reuse over one logging interval.
final class const PreparedGraphTimingSnapshot({
  required final int hitCount,
  required final int rebuildCount,
  required final int hitMicros,
  required final int rebuildMicros,
}) {
  int get sampleCount => hitCount + rebuildCount;

  double get hitRate => sampleCount == 0 ? 0 : hitCount / sampleCount;

  double? get averageHitMicros => hitCount == 0 ? null : hitMicros / hitCount;

  double? get averageRebuildMicros =>
      rebuildCount == 0 ? null : rebuildMicros / rebuildCount;
}

/// Accumulates graph reuse and rebuild timing until the next renderer log.
final class PreparedGraphTimingMetrics {
  int _hitCount = 0;
  int _rebuildCount = 0;
  int _hitMicros = 0;
  int _rebuildMicros = 0;

  void record({required bool reused, required int micros}) {
    if (micros < 0) {
      throw RangeError.value(micros, 'micros', 'must not be negative');
    }
    if (reused) {
      _hitCount += 1;
      _hitMicros += micros;
    } else {
      _rebuildCount += 1;
      _rebuildMicros += micros;
    }
  }

  PreparedGraphTimingSnapshot takeSnapshotAndReset() {
    final snapshot = PreparedGraphTimingSnapshot(
      hitCount: _hitCount,
      rebuildCount: _rebuildCount,
      hitMicros: _hitMicros,
      rebuildMicros: _rebuildMicros,
    );
    _hitCount = 0;
    _rebuildCount = 0;
    _hitMicros = 0;
    _rebuildMicros = 0;

    return snapshot;
  }
}

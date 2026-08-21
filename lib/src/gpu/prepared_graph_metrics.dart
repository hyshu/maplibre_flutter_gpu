import 'prepared_graph.dart';

/// Why a persistent prepared graph could not be reused for one native frame.
enum PreparedGraphRebuildReason {
  /// No previous graph existed yet.
  noGraph,

  /// The stable command topology no longer matched the retained graph.
  topologyMismatch,

  /// Topology matched, but refreshing dynamic resources failed.
  refreshFailed,
}

/// Detailed persistent-graph timing totals over one renderer logging interval.
final class PreparedGraphDetailedTimingSnapshot {
  const PreparedGraphDetailedTimingSnapshot({
    required this.totals,
    required this.hitMaxMicros,
    required this.rebuildMaxMicros,
    required this.validationCount,
    required this.validationMicros,
    required this.refreshCount,
    required this.refreshMicros,
    required this.decodeCount,
    required this.decodeMicros,
    required this.captureCount,
    required this.captureMicros,
    required this.noGraphRebuildCount,
    required this.topologyMismatchRebuildCount,
    required this.refreshFailedRebuildCount,
  });

  final PreparedGraphTimingSnapshot totals;
  final int hitMaxMicros;
  final int rebuildMaxMicros;
  final int validationCount;
  final int validationMicros;
  final int refreshCount;
  final int refreshMicros;
  final int decodeCount;
  final int decodeMicros;
  final int captureCount;
  final int captureMicros;
  final int noGraphRebuildCount;
  final int topologyMismatchRebuildCount;
  final int refreshFailedRebuildCount;

  double? get averageValidationMicros => validationCount == 0
      ? null
      : validationMicros / validationCount;

  double? get averageRefreshMicros =>
      refreshCount == 0 ? null : refreshMicros / refreshCount;

  double? get averageDecodeMicros =>
      decodeCount == 0 ? null : decodeMicros / decodeCount;

  double? get averageCaptureMicros =>
      captureCount == 0 ? null : captureMicros / captureCount;
}

/// Accumulates total and per-phase timing for persistent graph preparation.
final class PreparedGraphDetailedTimingMetrics {
  final PreparedGraphTimingMetrics _totals = PreparedGraphTimingMetrics();
  int _hitMaxMicros = 0;
  int _rebuildMaxMicros = 0;
  int _validationCount = 0;
  int _validationMicros = 0;
  int _refreshCount = 0;
  int _refreshMicros = 0;
  int _decodeCount = 0;
  int _decodeMicros = 0;
  int _captureCount = 0;
  int _captureMicros = 0;
  int _noGraphRebuildCount = 0;
  int _topologyMismatchRebuildCount = 0;
  int _refreshFailedRebuildCount = 0;

  void recordHit({
    required int totalMicros,
    required int validationMicros,
    required int refreshMicros,
  }) {
    _checkMicros('totalMicros', totalMicros);
    _checkMicros('validationMicros', validationMicros);
    _checkMicros('refreshMicros', refreshMicros);
    _totals.record(reused: true, micros: totalMicros);
    if (totalMicros > _hitMaxMicros) _hitMaxMicros = totalMicros;
    _recordValidation(validationMicros);
    _recordRefresh(refreshMicros);
  }

  void recordRebuild({
    required int totalMicros,
    required PreparedGraphRebuildReason reason,
    int? validationMicros,
    int? refreshMicros,
    required int decodeMicros,
    required int captureMicros,
  }) {
    _checkMicros('totalMicros', totalMicros);
    if (validationMicros != null) {
      _checkMicros('validationMicros', validationMicros);
    }
    if (refreshMicros != null) {
      _checkMicros('refreshMicros', refreshMicros);
    }
    _checkMicros('decodeMicros', decodeMicros);
    _checkMicros('captureMicros', captureMicros);
    _totals.record(reused: false, micros: totalMicros);
    if (totalMicros > _rebuildMaxMicros) _rebuildMaxMicros = totalMicros;
    if (validationMicros != null) _recordValidation(validationMicros);
    if (refreshMicros != null) _recordRefresh(refreshMicros);
    _decodeCount += 1;
    _decodeMicros += decodeMicros;
    _captureCount += 1;
    _captureMicros += captureMicros;
    switch (reason) {
      case PreparedGraphRebuildReason.noGraph:
        _noGraphRebuildCount += 1;
        break;
      case PreparedGraphRebuildReason.topologyMismatch:
        _topologyMismatchRebuildCount += 1;
        break;
      case PreparedGraphRebuildReason.refreshFailed:
        _refreshFailedRebuildCount += 1;
        break;
    }
  }

  PreparedGraphDetailedTimingSnapshot takeSnapshotAndReset() {
    final snapshot = PreparedGraphDetailedTimingSnapshot(
      totals: _totals.takeSnapshotAndReset(),
      hitMaxMicros: _hitMaxMicros,
      rebuildMaxMicros: _rebuildMaxMicros,
      validationCount: _validationCount,
      validationMicros: _validationMicros,
      refreshCount: _refreshCount,
      refreshMicros: _refreshMicros,
      decodeCount: _decodeCount,
      decodeMicros: _decodeMicros,
      captureCount: _captureCount,
      captureMicros: _captureMicros,
      noGraphRebuildCount: _noGraphRebuildCount,
      topologyMismatchRebuildCount: _topologyMismatchRebuildCount,
      refreshFailedRebuildCount: _refreshFailedRebuildCount,
    );
    _hitMaxMicros = 0;
    _rebuildMaxMicros = 0;
    _validationCount = 0;
    _validationMicros = 0;
    _refreshCount = 0;
    _refreshMicros = 0;
    _decodeCount = 0;
    _decodeMicros = 0;
    _captureCount = 0;
    _captureMicros = 0;
    _noGraphRebuildCount = 0;
    _topologyMismatchRebuildCount = 0;
    _refreshFailedRebuildCount = 0;

    return snapshot;
  }

  void _recordValidation(int micros) {
    _validationCount += 1;
    _validationMicros += micros;
  }

  void _recordRefresh(int micros) {
    _refreshCount += 1;
    _refreshMicros += micros;
  }

  static void _checkMicros(String name, int micros) {
    if (micros < 0) {
      throw RangeError.value(micros, name, 'must not be negative');
    }
  }
}

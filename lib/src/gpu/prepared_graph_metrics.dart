import 'package:flutter/foundation.dart';

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

String _topologyMismatchLabel(PreparedGraphTopologyMismatchReason reason) =>
    switch (reason) {
      .nonReusable => 'nonReusable',
      .commandCount => 'commandCount',
      .commandStride => 'commandStride',
      .commandBytes => 'commandBytes',
      .shader => 'shader',
      .drawMode => 'drawMode',
      .flags => 'flags',
      .layer => 'layer',
      .subLayer => 'subLayer',
      .stencil => 'stencil',
      .admission => 'admission',
      .unknown => 'unknown',
    };

/// Detailed persistent-graph timing totals over one renderer logging interval.
final class const PreparedGraphDetailedTimingSnapshot({
  required final PreparedGraphTimingSnapshot totals,
  required final int hitMaxMicros,
  required final int rebuildMaxMicros,
  required final int validationCount,
  required final int validationMicros,
  required final int refreshCount,
  required final int refreshMicros,
  required final int decodeCount,
  required final int decodeMicros,
  required final int captureCount,
  required final int captureMicros,
  required final int noGraphRebuildCount,
  required final int topologyMismatchRebuildCount,
  required final int refreshFailedRebuildCount,
  required final List<int> topologyMismatchReasonCounts,
}) {
  int topologyMismatchCount(PreparedGraphTopologyMismatchReason reason) =>
      topologyMismatchReasonCounts[reason.index];

  double? get averageValidationMicros =>
      validationCount == 0 ? null : validationMicros / validationCount;

  double? get averageRefreshMicros =>
      refreshCount == 0 ? null : refreshMicros / refreshCount;

  double? get averageDecodeMicros =>
      decodeCount == 0 ? null : decodeMicros / decodeCount;

  double? get averageCaptureMicros =>
      captureCount == 0 ? null : captureMicros / captureCount;
}

/// Accumulates total and per-phase timing for persistent graph preparation.
final class PreparedGraphDetailedTimingMetrics {
  final _totals = PreparedGraphTimingMetrics();
  final _topologyMismatchReasonCounts = List.filled(
    PreparedGraphTopologyMismatchReason.values.length,
    0,
  );
  var _hitMaxMicros = 0;
  var _rebuildMaxMicros = 0;
  var _validationCount = 0;
  var _validationMicros = 0;
  var _refreshCount = 0;
  var _refreshMicros = 0;
  var _decodeCount = 0;
  var _decodeMicros = 0;
  var _captureCount = 0;
  var _captureMicros = 0;
  var _noGraphRebuildCount = 0;
  var _topologyMismatchRebuildCount = 0;
  var _refreshFailedRebuildCount = 0;

  void recordHit({
    required int totalMicros,
    required int validationMicros,
    required int refreshMicros,
  }) {
    _checkMicros('totalMicros', totalMicros);
    _checkMicros('validationMicros', validationMicros);
    _checkMicros('refreshMicros', refreshMicros);
    PreparedGraphTopologyDiagnostics.clearPendingMismatch();
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
    if (validationMicros != null)
      _checkMicros('validationMicros', validationMicros);
    if (refreshMicros != null) _checkMicros('refreshMicros', refreshMicros);
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
      case .noGraph:
        PreparedGraphTopologyDiagnostics.clearPendingMismatch();
        _noGraphRebuildCount += 1;
        break;
      case .topologyMismatch:
        _topologyMismatchRebuildCount += 1;
        final mismatch =
            PreparedGraphTopologyDiagnostics.consumePendingMismatch() ?? .unknown;
        _topologyMismatchReasonCounts[mismatch.index] += 1;
        break;
      case .refreshFailed:
        PreparedGraphTopologyDiagnostics.clearPendingMismatch();
        _refreshFailedRebuildCount += 1;
        break;
    }
  }

  PreparedGraphDetailedTimingSnapshot takeSnapshotAndReset() {
    final mismatchCounts = List.unmodifiable(_topologyMismatchReasonCounts);
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
      topologyMismatchReasonCounts: mismatchCounts,
    );
    _logTopologyMismatchCounts(mismatchCounts);
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
    for (
      var index = 0;
      index < _topologyMismatchReasonCounts.length;
      index += 1
    ) {
      _topologyMismatchReasonCounts[index] = 0;
    }

    return snapshot;
  }

  void _logTopologyMismatchCounts(List<int> counts) {
    var total = 0;
    final parts = <String>[];
    for (final reason in PreparedGraphTopologyMismatchReason.values) {
      final count = counts[reason.index];
      if (count == 0) continue;
      total += count;
      parts.add('${_topologyMismatchLabel(reason)}:$count');
    }
    if (total == 0) return;
    debugPrint('[GpuGraphMismatch] total=$total ${parts.join(' ')}');
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

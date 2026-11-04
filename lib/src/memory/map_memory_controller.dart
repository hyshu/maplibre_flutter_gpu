import 'dart:async';

import 'map_memory_policy.dart';

/// Serializes reclamation with native frame leases and cancels work on disposal.
final class MapMemoryController {
  /// Connects pressure decisions to the owner's frame and cache lifecycle.
  MapMemoryController({
    required this.policy,
    required this.readSnapshot,
    required this.beforeMutation,
    required this.applyBudget,
    required this.trimCaches,
    required this.isActive,
    required this.onError,
    this.onDiagnostics,
  });

  /// Retention policy shared by sampling and platform warnings.
  final MapMemoryPolicy policy;

  /// Reads process measurements without requiring an active map frame.
  final MapMemorySnapshot Function() readSnapshot;

  /// Releases native frame leases before cache mutation.
  final Future<void> Function() beforeMutation;

  /// Applies retention limits and schedules any required replacement frame.
  final void Function(MapMemoryBudget) applyBudget;

  /// Drops rebuildable resources and schedules their next visible frame.
  final void Function() trimCaches;

  /// Whether periodic sampling should run while the map is visible.
  final bool Function() isActive;

  /// Reports failures while keeping reclamation eligible for retry.
  final void Function(Object, StackTrace) onError;

  /// Receives completed samples and applied limits, with memory values in bytes.
  ///
  /// No diagnostic strings are built when this callback is absent.
  final void Function(String)? onDiagnostics;
  final _clock = Stopwatch();
  Timer? _timer;
  var _disposed = false;
  var _checking = false;
  var _warningPending = false;
  var _initialBudgetPending = true;
  var _trimPending = false;

  /// Applies the initial budget and starts periodic sampling once.
  void start() {
    if (_disposed || _timer != null) return;
    _clock.start();
    unawaited(check());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isActive()) unawaited(check());
    });
  }

  /// Warnings are handled even while the map is hidden.
  Future<void> check({bool warning = false}) async {
    if (_disposed) return;
    _warningPending |= warning;
    if (_checking) return;
    _checking = true;
    try {
      do {
        final warned = _warningPending;
        _warningPending = false;
        MapMemorySnapshot snapshot;
        try {
          snapshot = readSnapshot();
        } catch (error, stackTrace) {
          onError(error, stackTrace);
          snapshot = const MapMemorySnapshot();
        }
        final previousLevel = policy.pressureLevel;
        final decision = policy.evaluate(
          snapshot,
          elapsed: _clock.elapsed,
          warning: warned,
        );
        _trimPending |= decision.trim;
        var trimmed = false;
        if (decision.changed || _trimPending || _initialBudgetPending) {
          await beforeMutation();
          if (_disposed) return;
          applyBudget(decision.budget);
          _initialBudgetPending = false;
          if (_trimPending) {
            trimCaches();
            _trimPending = false;
            trimmed = true;
          }
        }
        final diagnostics = onDiagnostics;
        if (diagnostics != null) {
          final budget = decision.budget;
          final gpu = budget.gpu;
          diagnostics(
            '[MapMemory] elapsedMs=${_clock.elapsedMilliseconds} '
            'physicalBytes=${snapshot.physicalBytes} '
            'availableBytes=${snapshot.availableBytes} '
            'usageBytes=${snapshot.usageBytes} '
            'previousLevel=$previousLevel level=${policy.pressureLevel} '
            'changed=${decision.changed} warning=$warned trimmed=$trimmed '
            'regularMinBytes=${gpu.regularMinBytes} '
            'regularMaxBytes=${gpu.regularMaxBytes} '
            'fillExtrusionMinBytes=${gpu.fillExtrusionMinBytes} '
            'fillExtrusionMaxBytes=${gpu.fillExtrusionMaxBytes} '
            'textureBytes=${gpu.textureBytes} poolBytes=${gpu.poolBytes} '
            'nativeTiles=${budget.nativeTileCount} '
            'customizerBytes=${budget.customizerBytes} '
            'processLimitBytes=${budget.processLimitBytes} '
            'reserveBytes=${budget.reserveBytes}',
          );
        }
      } while (_warningPending && !_disposed);
    } catch (error, stackTrace) {
      _initialBudgetPending = true;
      if (!_disposed) onError(error, stackTrace);
    } finally {
      _checking = false;
    }
  }

  /// Stops sampling and prevents suspended checks from mutating resources.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }
}

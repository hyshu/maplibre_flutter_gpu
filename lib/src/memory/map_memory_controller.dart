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
        final decision = policy.evaluate(
          snapshot,
          elapsed: _clock.elapsed,
          warning: warned,
        );
        _trimPending |= decision.trim;
        if (decision.changed || _trimPending || _initialBudgetPending) {
          await beforeMutation();
          if (_disposed) return;
          applyBudget(decision.budget);
          _initialBudgetPending = false;
          if (_trimPending) {
            trimCaches();
            _trimPending = false;
          }
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

import 'dart:async';

/// Coordinates native rendering barriers without blocking the Flutter isolate.
class MapRenderPauseTransition {
  MapRenderPauseTransition({
    required this.isAlive,
    required this.pauseDisplay,
    required this.prepareResume,
    required this.resumeDisplay,
    required this.releaseFrame,
    required this.setNativePaused,
  });

  final bool Function() isAlive;
  final void Function() pauseDisplay;
  final void Function() prepareResume;
  final void Function() resumeDisplay;
  final Future<void> Function() releaseFrame;
  final Future<bool> Function(bool paused) setNativePaused;
  final _disposed = Completer<void>();
  final _nativeBarriers = <Future<void>>{};
  var _generation = 0;

  bool _isCurrent(int generation) =>
      !_disposed.isCompleted && isAlive() && generation == _generation;

  /// Applies the latest request and leaves newer requests in control.
  Future<void> setPaused(bool paused) {
    if (_disposed.isCompleted) return Future<void>.value();
    final generation = ++_generation;

    return Future.any([_apply(paused, generation), _disposed.future]);
  }

  Future<void> _apply(bool paused, int generation) async {
    var nativeChangeAccepted = false;
    try {
      if (paused) {
        pauseDisplay();
        // Native closes admission before returning this future. Releasing a
        // lease cannot start another render while the owner barrier is pending.
        final native = _setNativePaused(true).then((accepted) {
          nativeChangeAccepted = accepted;

          return accepted;
        });
        final results = await Future.wait([
          native,
          Future<void>.sync(releaseFrame).then((_) => true),
        ]);
        if (!_isCurrent(generation)) return;
        if (!results.first) {
          throw StateError('Native map rejected the rendering pause change');
        }
      } else {
        await releaseFrame();
        if (!_isCurrent(generation)) return;
        final accepted = await _setNativePaused(false);
        nativeChangeAccepted = accepted;
        if (!_isCurrent(generation)) return;
        if (!accepted) {
          throw StateError('Native map rejected the rendering pause change');
        }
        prepareResume();
        resumeDisplay();
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        if (!paused && nativeChangeAccepted) pauseDisplay();
        if (nativeChangeAccepted) {
          final restored = await _setNativePaused(!paused);
          if (!_isCurrent(generation)) return;
          if (!restored) {
            throw StateError('Native map rejected rendering pause recovery');
          }
        }
        if (paused && _isCurrent(generation)) resumeDisplay();
      }
      rethrow;
    }
  }

  Future<bool> _setNativePaused(bool paused) {
    final result = setNativePaused(paused);
    final barrier = result.then<void>((_) {}, onError: (Object _) {});
    _nativeBarriers.add(barrier);
    unawaited(barrier.then((_) => _nativeBarriers.remove(barrier)));

    return result;
  }

  /// Completes callers immediately and returns pending native cleanup barriers.
  ///
  /// Native resources must outlive accepted requests even after the Flutter
  /// widget is gone. The returned future ignores request failures.
  Future<void>? dispose() {
    if (_disposed.isCompleted) return null;
    _generation++;
    _disposed.complete();

    return _nativeBarriers.isEmpty
        ? null
        : Future.wait(_nativeBarriers).then((_) {});
  }
}

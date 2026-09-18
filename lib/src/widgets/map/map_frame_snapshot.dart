part of '../maplibre_map.dart';

extension _MapFrameSnapshot on _MapLibreMapState {
  Future<void> _releaseFrameSnapshotBeforeMutation() {
    if (_applyingFrameSnapshot) {
      _releaseSnapshotAfterApply = true;

      return (_mutationBarrier ??= .new()).future;
    }
    _releasePendingFrameSnapshot();

    return Future<void>.value();
  }

  void _releasePendingFrameSnapshot() {
    final snapshot = _pendingFrameSnapshot;
    _pendingFrameSnapshot = null;
    snapshot?.release();
  }

  void _finishApplyingFrameSnapshot() {
    _applyingFrameSnapshot = false;
    if (!_releaseSnapshotAfterApply) return;
    _releaseSnapshotAfterApply = false;
    final barrier = _mutationBarrier;
    _mutationBarrier = null;
    try {
      _releasePendingFrameSnapshot();
      barrier?.complete();
    } catch (error, stackTrace) {
      barrier?.completeError(error, stackTrace);
    }
  }

  void _onFrameSnapshotReleased(NativeFrameSnapshotLease snapshot) {
    if (identical(_pendingFrameSnapshot, snapshot)) {
      _pendingFrameSnapshot = null;
    }
  }

  NativeFrameSnapshotLease? _frameSnapshotForPaint() => _pendingFrameSnapshot;
}

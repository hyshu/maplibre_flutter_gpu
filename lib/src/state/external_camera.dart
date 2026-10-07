import 'dart:async' show unawaited;

import '../geo/camera.dart';

/// Coalesces external absolute camera inputs while native frames are in use.
class ExternalCamera({
  required final bool Function() canApply,
  required final Future<void> Function() beforeApply,
  required final void Function(CameraPosition position) apply,
  required final void Function(void Function() callback) schedule,
  required final void Function(Object error, StackTrace stackTrace) onError,
}) {
  CameraPosition? _position;
  var _revision = 0;
  var _dirty = false;
  var _scheduled = false;
  var _applying = false;
  var _disposed = false;

  /// Retains the latest input, or releases external ownership when null.
  void update(CameraPosition? position) {
    if (_disposed || _position == position) return;
    _position = position;
    _revision++;
    _dirty = position != null;
    _schedule();
  }

  /// Requests the current input again after initialization or viewport changes.
  void reapply() {
    if (_disposed || _position == null) return;
    _revision++;
    _dirty = true;
    _schedule();
  }

  /// Records an input applied directly during native initialization.
  void markApplied(CameraPosition position) {
    if (_position == position) _dirty = false;
  }

  void _schedule() {
    if (_disposed || !_dirty || _scheduled || _applying) return;
    _scheduled = true;
    schedule(() => unawaited(_flush()));
  }

  Future<void> _flush() async {
    _scheduled = false;
    if (_disposed || !_dirty || _applying || !canApply()) return;
    _applying = true;
    var revision = _revision;
    try {
      await beforeApply();
      if (_disposed || !canApply()) return;
      final position = _position;
      if (position == null || !_dirty) return;
      revision = _revision;
      apply(position);
      if (revision == _revision) _dirty = false;
    } catch (error, stackTrace) {
      if (revision == _revision) _dirty = false;
      if (!_disposed) onError(error, stackTrace);
    } finally {
      _applying = false;
      if (!_disposed && canApply()) _schedule();
    }
  }

  /// Drops retained input and prevents queued callbacks from touching native.
  void dispose() {
    _disposed = true;
    _position = null;
    _dirty = false;
  }
}

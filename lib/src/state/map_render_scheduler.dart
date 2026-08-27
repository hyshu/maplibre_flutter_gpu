// Coalesces timer, native, and lifecycle render requests while preventing
// rendering in the background.
import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Schedules map rendering from repaint, native, and lifecycle requests.
class MapRenderScheduler({
  /// Whether the map is still mounted and initialized.
  required final bool Function() _isAlive,

  /// Whether native has work that justifies a frame, checked at frame time.
  required final bool Function() _hasPendingNativeWork,

  /// Renders one map frame.
  required final void Function() _render,
  Timer Function(Duration duration, void Function() callback)? createTimer,
  void Function(void Function() callback)? scheduleFrameCallback,
}) {
  this
    : _createTimer = createTimer ?? Timer.new,
      _scheduleFrameCallback =
          scheduleFrameCallback ??
          ((callback) => SchedulerBinding.instance.scheduleFrameCallback(
            (_) => callback(),
          ));

  final Timer Function(Duration, void Function()) _createTimer;
  final void Function(void Function()) _scheduleFrameCallback;

  Timer? _repaintTimer;
  bool _appActive = true;
  bool _renderOnResume = false;
  bool _frameScheduled = false;
  bool _forceNextFrame = false;
  bool _disposed = false;

  /// Whether the app is in the foreground and may touch the GPU surface.
  bool get isAppActive => _appActive;

  /// Whether a timer-based repaint is pending.
  bool get isRepaintPending => _repaintTimer != null;

  /// Queues one timer-based repaint after [interval].
  ///
  /// Does nothing when the app is inactive, the scheduler is disposed, or a
  /// timer is already pending.
  void scheduleRepaint(Duration interval) {
    if (_disposed || _repaintTimer != null || !_appActive) return;
    _repaintTimer = _createTimer(interval, () {
      _repaintTimer = null;
      if (_disposed || !_isAlive() || !_appActive) return;
      _render();
    });
  }

  /// Cancels the pending timer-based repaint.
  void cancelRepaint() {
    _repaintTimer?.cancel();
    _repaintTimer = null;
  }

  /// Asks for a render on the next frame.
  ///
  /// Requests within one frame are coalesced. If any request is forced, the
  /// frame renders without requiring pending native work.
  void scheduleNativeRender({bool force = false}) {
    if (_disposed) return;
    if (!_appActive) {
      // Defer rendering until the GPU surface is available again.
      _renderOnResume = true;

      return;
    }
    _forceNextFrame |= force;
    if (_frameScheduled) return;
    _frameScheduled = true;
    _scheduleFrameCallback(() {
      _frameScheduled = false;
      if (_disposed || !_isAlive() || !_appActive) return;
      final forced = _forceNextFrame;
      _forceNextFrame = false;
      if (!forced && !_hasPendingNativeWork()) return;
      // This frame supersedes the timer and prevents a duplicate render.
      cancelRepaint();
      _render();
    });
  }

  /// Defers a render that could not run while the app was inactive.
  void deferToResume() {
    if (_disposed) return;
    _renderOnResume = true;
  }

  /// Updates whether the app may render.
  ///
  /// Returns whether the state changed. Resuming forces any deferred render.
  bool setAppActive(bool active) {
    if (_disposed || _appActive == active) return false;
    _appActive = active;
    if (!active) {
      cancelRepaint();
      _renderOnResume = true;

      return true;
    }
    if (_renderOnResume && _isAlive()) {
      _renderOnResume = false;
      scheduleNativeRender(force: true);
    }
    return true;
  }

  /// Cancels owned work and prevents future render requests.
  ///
  /// Repeated calls do nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelRepaint();
    _frameScheduled = false;
    _forceNextFrame = false;
    _renderOnResume = false;
  }
}

/// Whether the map still owes a frame once the current one has been drawn.
///
/// Polling continues until the style is loaded and the map is idle when native
/// render notifications are unavailable.
bool shouldScheduleFrame({
  required bool needsRepaint,
  required bool cameraMoving,
  required bool flingAnimating,
  required bool supportsEventDrivenRendering,
  required bool styleLoaded,
  required bool mapIdle,
}) =>
    needsRepaint ||
    cameraMoving ||
    flingAnimating ||
    (!supportsEventDrivenRendering && (!styleLoaded || !mapIdle));

/// Whether the style and camera have reached a fully settled state.
///
/// Camera transitions and Flutter flings prevent settlement even when native
/// reports the current frame as idle.
bool isMapRenderSettled({
  required bool styleLoaded,
  required bool mapIdle,
  required bool cameraMoving,
  required bool flingAnimating,
}) => styleLoaded && mapIdle && !cameraMoving && !flingAnimating;

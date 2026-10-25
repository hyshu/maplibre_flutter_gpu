// Coalesces timer, native, and lifecycle render requests while preventing
// rendering while the app or this map is suspended.
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
  var _appActive = true;
  var _renderingPaused = false;
  var _renderOnResume = false;
  var _frameScheduled = false;
  var _forceNextFrame = false;
  var _repaintDue = false;
  var _disposed = false;
  var _frameGeneration = 0;

  /// Whether the app is in the foreground and may touch the GPU surface.
  bool get isAppActive => _appActive;

  /// Whether this map has been explicitly paused.
  bool get isRenderingPaused => _renderingPaused;

  /// Whether lifecycle and explicit rendering controls both allow a frame.
  bool get isRenderingAllowed => !_disposed && _appActive && !_renderingPaused;

  /// Whether a timer-based repaint is pending.
  bool get isRepaintPending => _repaintTimer != null;

  /// Queues one timer-based repaint after [interval].
  ///
  /// The repaint renders on the first frame after the timer fires, so it
  /// shares that frame's render with any native or camera request instead of
  /// rendering a second time between frames. Does nothing when the app is
  /// inactive, rendering is paused, or a timer is already pending.
  void scheduleRepaint(Duration interval) {
    if (!isRenderingAllowed || _repaintTimer != null) return;
    _repaintTimer = _createTimer(interval, () {
      _repaintTimer = null;
      if (!_isAlive() || !isRenderingAllowed) return;
      _repaintDue = true;
      _scheduleFrame();
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
    if (!isRenderingAllowed) {
      // Keep only the need to refresh when rendering becomes available.
      _renderOnResume = true;

      return;
    }
    _forceNextFrame |= force;
    _scheduleFrame();
  }

  void _scheduleFrame() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    final generation = _frameGeneration;
    _scheduleFrameCallback(() {
      if (generation != _frameGeneration) return;
      _frameScheduled = false;
      if (!_isAlive() || !isRenderingAllowed) return;
      final forced = _forceNextFrame;
      final due = _repaintDue;
      _forceNextFrame = false;
      _repaintDue = false;
      if (!forced && !due && !_hasPendingNativeWork()) return;
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

  /// Updates whether the app lifecycle allows rendering.
  ///
  /// Returns whether the state changed. Resuming forces any deferred render.
  bool setAppActive(bool active) {
    if (_disposed || _appActive == active) return false;
    _appActive = active;
    _updateRenderingPermission();

    return true;
  }

  /// Pauses this map without changing its app lifecycle state.
  ///
  /// Resuming requests one fresh frame when the app is active. Requests made
  /// while either gate is closed are coalesced into that same frame.
  bool setRenderingPaused(bool paused) {
    if (_disposed || _renderingPaused == paused) return false;
    _renderingPaused = paused;
    _updateRenderingPermission();

    return true;
  }

  void _updateRenderingPermission() {
    if (!isRenderingAllowed) {
      cancelRepaint();
      _frameGeneration++;
      _frameScheduled = false;
      _forceNextFrame = false;
      _repaintDue = false;
      _renderOnResume = true;

      return;
    }
    if (_renderOnResume && _isAlive()) {
      _renderOnResume = false;
      scheduleNativeRender(force: true);
    }
  }

  /// Cancels owned work and prevents future render requests.
  ///
  /// Repeated calls do nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _frameGeneration++;
    cancelRepaint();
    _frameScheduled = false;
    _forceNextFrame = false;
    _repaintDue = false;
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

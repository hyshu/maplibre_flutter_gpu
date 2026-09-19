part of 'gesture_coordinator.dart';

enum _DesktopMouseDragMode { tilt, rotate }

class _DesktopGestureState {
  var trackpadGestureActive = false;
  var macosTrackpadTiltActive = false;
  _DesktopMouseDragMode? mouseDragMode;
  int? mouseDragPointer;
  var previousTrackpadScale = 1.0;
  var previousTrackpadRotation = 0.0;
}

extension _DesktopGestures on MapGestureCoordinator {
  _DesktopMouseDragMode? _desktopMouseDragModeFor(PointerDownEvent event) {
    final platform = defaultTargetPlatform;
    if (platform != .windows && platform != .linux) return null;
    if (event.kind != .mouse || event.buttons != kPrimaryMouseButton) {
      return null;
    }
    if (HardwareKeyboard.instance.isControlPressed) return .rotate;
    if (HardwareKeyboard.instance.isShiftPressed) return .tilt;

    return null;
  }

  bool _applyDesktopMouseDragMove(PointerMoveEvent event) {
    final mode = _desktop.mouseDragMode;
    if (mode == null || event.pointer != _desktop.mouseDragPointer) {
      return false;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      _finishDesktopMouseDrag();

      return true;
    }
    final bridge = host.gestureBridge;
    if (bridge == null) return true;
    final settings = host.gestureSettings;
    switch (mode) {
      case .tilt:
        if (!settings.tiltEnabled) return true;
        _beginScaleGesture();
        bridge.pitchBy(mouseTiltDelta(event.delta.dy));
      case .rotate:
        if (!settings.rotateEnabled) return true;
        _beginScaleGesture();
        bridge.rotateBy(mouseRotateDelta(event.delta.dx));
    }
    _scheduleGestureRender();

    return true;
  }

  void _finishDesktopMouseDrag() {
    _desktop.mouseDragMode = null;
    _desktop.mouseDragPointer = null;
    if (!_scaleGestureActive) return;
    _scaleGestureActive = false;
    _clearScaleTracking();
    if (host.gestureBridge == null) return;
    _renderGestureNow();
    host.endCameraGesture();
  }

  void _applyTrackpadUpdate(
    MaplibreBridge bridge,
    MapGestureSettings settings,
    ScaleUpdateDetails details,
  ) {
    var cameraChanged = false;
    if (settings.scrollEnabled && details.focalPointDelta != Offset.zero) {
      bridge.moveBy(details.focalPointDelta.dx, details.focalPointDelta.dy);
      cameraChanged = true;
    }
    if (settings.zoomEnabled) {
      final scale = trackpadScaleDelta(
        details.scale,
        _desktop.previousTrackpadScale,
      );
      if ((scale - 1).abs() > 0.0001) {
        bridge.scaleBy(
          scale,
          details.localFocalPoint.dx,
          details.localFocalPoint.dy,
        );
        cameraChanged = true;
      }
    }
    if (settings.rotateEnabled) {
      final rotation = normalizedAngleDelta(
        details.rotation,
        _desktop.previousTrackpadRotation,
      );
      if (rotation.abs() > 0.0001) {
        bridge.rotateBy(bearingGestureDelta(rotation));
        cameraChanged = true;
      }
    }
    _desktop.previousTrackpadScale = details.scale;
    _desktop.previousTrackpadRotation = details.rotation;
    if (cameraChanged) _scheduleGestureRender();
  }

  void _startMacosTrackpadTilt() {
    if (host.gestureBridge == null || !host.gestureSettings.tiltEnabled) return;
    _desktop.macosTrackpadTiltActive = true;
    _beginScaleGesture();
  }

  void _updateMacosTrackpadTilt(double scrollingDelta) {
    if (!_desktop.macosTrackpadTiltActive ||
        !host.gestureSettings.tiltEnabled) {
      return;
    }
    final bridge = host.gestureBridge;
    if (bridge == null) return;
    bridge.pitchBy(trackpadTiltDelta(scrollingDelta));
    _scheduleGestureRender();
  }

  void _endMacosTrackpadTilt() {
    if (!_desktop.macosTrackpadTiltActive) return;
    _desktop.macosTrackpadTiltActive = false;
    _scaleGestureActive = false;
    _clearScaleTracking();
    if (host.gestureBridge == null) return;
    _renderGestureNow();
    host.endCameraGesture();
  }
}

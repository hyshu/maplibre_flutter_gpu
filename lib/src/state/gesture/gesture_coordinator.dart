import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../native/maplibre_ffi.dart';
import 'gesture_math.dart';
import 'gesture_options.dart';
import 'multi_pointer_tracker.dart';
import 'pan_fling_tracker.dart';

part 'gesture_desktop.dart';
part 'gesture_taps.dart';

/// Which gestures the map currently accepts.
typedef MapGestureSettings = ({
  bool scrollEnabled,
  bool zoomEnabled,
  bool rotateEnabled,
  bool tiltEnabled,

  /// A null value follows the zoom setting.
  bool? doubleClickZoomEnabled,
});

/// Provides the map operations required by [MapGestureCoordinator].
abstract interface class MapGestureHost {
  /// The native bridge, or null when the map cannot accept gestures.
  MaplibreBridge? get gestureBridge;

  /// Gestures currently accepted by the map.
  MapGestureSettings get gestureSettings;

  /// Behavior and thresholds used to interpret gestures.
  MapGestureOptions get gestureOptions;

  /// Logical size of the map, for gestures that need a default focal point.
  Size get logicalMapSize;

  /// Redraws at the new camera without re-extracting labels.
  void renderGesture();

  /// Keeps the repaint loop running while the camera is still moving.
  void scheduleRepaint();

  /// Begins a user camera gesture and cancels pending programmatic completion.
  void beginCameraGesture();

  /// Ends a user camera gesture and resumes settled-camera processing.
  void endCameraGesture();
}

/// Turns pointer, trackpad, and fling input into native camera moves.
///
/// Owns gesture tracking and fling animation state. Map operations are
/// performed through [MapGestureHost].
class MapGestureCoordinator({
  required TickerProvider vsync,
  required final MapGestureHost host,
}) {
  this {
    _flingController =
        .new(vsync: vsync, duration: host.gestureOptions.flingDuration)
          ..addListener(_onFlingTick)
          ..addStatusListener(_onFlingStatus);
  }

  late final AnimationController _flingController;
  final _pan = PanFlingTracker();
  final _pointers = MultiPointerTracker();
  var _twoFingerUpdateScheduled = false;
  var _gestureRenderScheduled = false;
  var _scaleGestureActive = false;
  var _singlePointerPanActive = false;
  var _suppressScaleUntilPointersReleased = false;
  final _pointerPositions = <int, Offset>{};
  final _tap = _TapGestureState();
  final _desktop = _DesktopGestureState();

  Timer? _wheelEndTimer;

  /// Whether a fling animation is active.
  bool get isFlinging => _flingController.isAnimating;

  /// Whether a pointer or trackpad scale gesture has started.
  bool get isScaleGestureActive => _scaleGestureActive;

  /// Stops gesture motion when a programmatic update takes over the camera.
  ///
  /// The new update owns rendering and idle completion.
  void stopFling() {
    _cancelWheelGesture();
    _gestureRenderScheduled = false;
    _flingController.stop();
    _pan.clearPanSamples();
    _tap.tapZoomTimer?.cancel();
  }

  /// Stops an active fling and completes its camera gesture.
  void cancelFlingAndEndGesture() {
    if (!_flingController.isAnimating) return;
    _flingController.stop();
    _pan.clearPanSamples();
    if (host.gestureBridge == null) return;
    host.renderGesture();
    host.endCameraGesture();
  }

  /// Stops an active scale gesture and rejects its remaining pointer input.
  void cancelScaleGestureAndEndGesture() {
    if (_pointerPositions.isNotEmpty) {
      _suppressScaleUntilPointersReleased = true;
    }
    if (!_scaleGestureActive) return;
    _scaleGestureActive = false;
    _clearScaleTracking();
    if (host.gestureBridge == null) return;
    _renderGestureNow();
    host.endCameraGesture();
  }

  /// Releases timers and animation resources owned by this coordinator.
  void dispose() {
    _cancelWheelGesture();
    _gestureRenderScheduled = false;
    _tap.dispose();
    _flingController.dispose();
  }

  /// Handles scroll wheel and pointer signal input.
  void onPointerSignal(PointerSignalEvent event) {
    final bridge = host.gestureBridge;
    if (bridge == null || !host.gestureSettings.zoomEnabled) return;
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        _scaleGestureActive) {
      return;
    }
    if (_wheelEndTimer == null) host.beginCameraGesture();
    _wheelEndTimer?.cancel();
    _wheelEndTimer = Timer(
      const Duration(milliseconds: 150),
      _finishWheelGesture,
    );
    _flingController.stop();
    final rate = host.gestureOptions.scrollWheelZoomRate;
    final factor = event.scrollDelta.dy < 0 ? 1 + rate : 1 - rate;
    final local = event.localPosition;
    bridge.scaleBy(factor, local.dx, local.dy);
    _scheduleGestureRender();
    host.scheduleRepaint();
  }

  void _finishWheelGesture() {
    if (_wheelEndTimer == null) return;
    _cancelWheelGesture();
    if (host.gestureBridge == null) return;
    _renderGestureNow();
    host.endCameraGesture();
  }

  void _cancelWheelGesture() {
    _wheelEndTimer?.cancel();
    _wheelEndTimer = null;
  }

  void _scheduleGestureRender() {
    if (_gestureRenderScheduled) return;
    _gestureRenderScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      if (!_gestureRenderScheduled) return;
      _gestureRenderScheduled = false;
      if (host.gestureBridge != null) host.renderGesture();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _renderGestureNow() {
    _gestureRenderScheduled = false;
    host.renderGesture();
  }

  /// Starts tracking a pointer and any tap gesture it may form.
  ///
  /// Tracking starts before map initialization completes. Updates check map
  /// availability before changing the camera.
  void onPointerDown(PointerDownEvent event) {
    _finishWheelGesture();
    if (_flingController.isAnimating) {
      _flingController.stop();
      _pan.clearPanSamples();
      host.endCameraGesture();
    }
    final desktopMouseDragMode = _desktopMouseDragModeFor(event);
    if (_pointerPositions.isEmpty) {
      final settings = host.gestureSettings;
      _suppressScaleUntilPointersReleased =
          !settings.scrollEnabled &&
          !settings.zoomEnabled &&
          !settings.rotateEnabled &&
          !settings.tiltEnabled;
    }
    _trackTapPointerDown(event, desktopMouseDragMode == null);
    _pointerPositions[event.pointer] = event.localPosition;
    _pointers.down(event.pointer, event.localPosition);
    if (desktopMouseDragMode != null) {
      _desktop.mouseDragMode = desktopMouseDragMode;
      _desktop.mouseDragPointer = event.pointer;
    }
    _trackTwoFingerTapDown();
  }

  /// Stops tracking a pointer and completes any recognized tap gesture.
  void onPointerEnd(PointerEvent event) {
    final wasDesktopMouseDrag = event.pointer == _desktop.mouseDragPointer;
    final wasQuickZoomPointer = event.pointer == _tap.quickZoomPointer;
    _rememberCompletedSingleTap(event, wasQuickZoomPointer);
    final twoFingerTap = _finishTwoFingerTapIfRecognized(event);
    _pointerPositions.remove(event.pointer);
    _forgetTapPointer(event.pointer);
    _pointers.up(event.pointer);
    if (wasDesktopMouseDrag) _finishDesktopMouseDrag();
    if (_pointerPositions.isEmpty) {
      _suppressScaleUntilPointersReleased = false;
    }
    if (wasQuickZoomPointer) _finishQuickZoom();
    if (twoFingerTap != null) _zoomByTap(-1, twoFingerTap);
  }

  /// Updates pointer tracking and applies recognized gesture movement.
  void onPointerMove(PointerMoveEvent event) {
    _pointerPositions[event.pointer] = event.localPosition;
    _trackTapPointerMove(event);
    if (_applyDesktopMouseDragMove(event)) return;
    if (_applyQuickZoomMove(event)) return;
    _pointers.move(event.pointer, event.localPosition);
    if (!_pointers.isMultiPointer || _twoFingerUpdateScheduled) return;
    _twoFingerUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _twoFingerUpdateScheduled = false;
      _processMultiPointerGesture();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _processMultiPointerGesture() {
    if (_suppressScaleUntilPointersReleased) return;
    final bridge = host.gestureBridge;
    if (bridge == null) return;
    final settings = host.gestureSettings;
    final update = _pointers.evaluate(
      zoomEnabled: settings.zoomEnabled,
      rotateEnabled: settings.rotateEnabled,
      tiltEnabled: settings.tiltEnabled,
    );
    if (update == null) return;
    _beginScaleGesture();
    final tiltDelta = update.tiltDelta;
    if (tiltDelta != null) bridge.pitchBy(tiltDelta);
    final scale = update.scale;
    if (scale != null) {
      bridge.scaleBy(scale, update.scaleFocus!.dx, update.scaleFocus!.dy);
    }
    final rotation = update.rotationDelta;
    if (rotation != null) bridge.rotateBy(bearingGestureDelta(rotation));
    host.renderGesture();
  }

  /// Begins a scale gesture and clears motion inherited from an earlier input.
  void onScaleStart(ScaleStartDetails details) {
    if (_desktop.mouseDragMode != null ||
        _tap.quickZoomPointer != null ||
        (_suppressScaleUntilPointersReleased && details.kind != .trackpad)) {
      return;
    }
    _beginScaleGesture();
    _desktop.trackpadGestureActive = details.kind == .trackpad;
    _desktop.previousTrackpadScale = 1;
    _desktop.previousTrackpadRotation = 0;
  }

  void _beginScaleGesture() {
    _finishWheelGesture();
    if (_scaleGestureActive) return;
    _scaleGestureActive = true;
    _singlePointerPanActive = false;
    host.beginCameraGesture();
    _flingController.stop();
    _pan.clearPanSamples();
  }

  /// Applies pan, zoom, and rotation updates from a scale recognizer.
  void onScaleUpdate(ScaleUpdateDetails details) {
    if (_tap.quickZoomPointer != null || !_scaleGestureActive) return;
    final bridge = host.gestureBridge;
    if (bridge == null) return;
    final settings = host.gestureSettings;
    if (_desktop.trackpadGestureActive) {
      _applyTrackpadUpdate(bridge, settings, details);

      return;
    }
    // Two or more pointers are handled by the multi-pointer tracker, which
    // reads raw positions rather than this recognizer's aggregate.
    if (details.pointerCount >= 2) {
      _singlePointerPanActive = false;

      return;
    }
    if (!settings.scrollEnabled) return;
    final delta = details.focalPointDelta;
    if (details.pointerCount == 1 && delta != Offset.zero) {
      _singlePointerPanActive = true;
    }
    bridge.moveBy(delta.dx, delta.dy);
    _scheduleGestureRender();
  }

  /// Begins a native macOS three-finger trackpad tilt.
  void onMacosTrackpadTiltStart() => _startMacosTrackpadTilt();

  /// Applies one native macOS three-finger trackpad scrolling delta.
  void onMacosTrackpadTiltUpdate(double scrollingDelta) =>
      _updateMacosTrackpadTilt(scrollingDelta);

  /// Completes a native macOS three-finger trackpad tilt.
  void onMacosTrackpadTiltEnd() => _endMacosTrackpadTilt();

  /// Completes a scale gesture and starts a fling when appropriate.
  void onScaleEnd(ScaleEndDetails details) {
    if (_tap.quickZoomPointer != null) return;
    if (!_scaleGestureActive) {
      _clearScaleTracking();

      return;
    }
    _scaleGestureActive = false;
    if (host.gestureBridge == null) {
      _clearScaleTracking();

      return;
    }
    _renderGestureNow();

    var startedFling = false;
    final options = host.gestureOptions;
    // The recognizer reports remaining pointers, so lifting one finger from
    // a pinch must not turn that finger's velocity into a pan fling.
    if (options.flingEnabled &&
        _singlePointerPanActive &&
        details.pointerCount == 0 &&
        host.gestureSettings.scrollEnabled) {
      final velocity = details.velocity.pixelsPerSecond;
      if (_pan.isFling(velocity, threshold: options.flingVelocityThreshold)) {
        _startFling(velocity);
        startedFling = true;
      }
    }
    _clearScaleTracking();
    if (!startedFling) host.endCameraGesture();
  }

  void _clearScaleTracking() {
    _singlePointerPanActive = false;
    _pan.clearPanSamples();
    _desktop.trackpadGestureActive = false;
    _desktop.macosTrackpadTiltActive = false;
    _desktop.previousTrackpadScale = 1;
    _desktop.previousTrackpadRotation = 0;
  }

  /// Records the focal point of a possible double tap.
  void onDoubleTapDown(TapDownDetails details) =>
      _tap.doubleTapPosition = details.localPosition;

  /// Applies zoom for a recognized double tap when enabled.
  void onDoubleTap() => _handleDoubleTap();

  void _startFling(Offset velocity) {
    if (host.gestureBridge == null) return;
    _flingController.duration = host.gestureOptions.flingDuration;
    _pan.beginFling(velocity);
    _flingController.forward(from: 0.0);
  }

  void _onFlingTick() {
    final bridge = host.gestureBridge;
    if (bridge == null) return;
    final move = _pan.advance(_flingController.value);
    if (move == null) return;
    bridge.moveBy(move.dx, move.dy);
    host.renderGesture();
  }

  void _onFlingStatus(AnimationStatus status) {
    if (status != .completed) return;
    if (host.gestureBridge == null) return;
    host.renderGesture();
    host.endCameraGesture();
  }
}

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../native/maplibre_ffi.dart';
import 'gesture_math.dart';
import 'gesture_options.dart';
import 'multi_pointer_tracker.dart';
import 'pan_fling_tracker.dart';

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
class MapGestureCoordinator {
  MapGestureCoordinator({required TickerProvider vsync, required this.host}) {
    _flingController =
        AnimationController(
            vsync: vsync,
            duration: host.gestureOptions.flingDuration,
          )
          ..addListener(_onFlingTick)
          ..addStatusListener(_onFlingStatus);
  }

  final MapGestureHost host;

  static const _twoFingerTapTime = Duration(milliseconds: 300);
  static const _twoFingerTapSlop = 12.0;
  static const _quickZoomSlop = 4.0;

  late final AnimationController _flingController;
  final PanFlingTracker _pan = PanFlingTracker();
  final MultiPointerTracker _pointers = MultiPointerTracker();
  var _twoFingerUpdateScheduled = false;
  var _gestureRenderScheduled = false;
  var _scaleGestureActive = false;
  var _suppressScaleUntilPointersReleased = false;
  var _trackpadGestureActive = false;
  var _previousTrackpadScale = 1.0;
  var _previousTrackpadRotation = 0.0;
  Offset? _doubleTapPosition;
  Timer? _tapZoomTimer;
  Timer? _doubleTapSuppressionTimer;
  final Map<int, Offset> _pointerPositions = <int, Offset>{};
  final Map<int, Offset> _pointerDownPositions = <int, Offset>{};
  final Map<int, Duration> _pointerDownTimes = <int, Duration>{};
  final Map<int, Offset> _twoFingerTapStarts = <int, Offset>{};
  Duration? _twoFingerTapStartedAt;
  var _twoFingerTapPossible = false;
  Duration? _lastTapUpTime;
  Offset? _lastTapPosition;
  int? _singleTapPointer;
  var _singleTapMoved = false;
  int? _quickZoomPointer;
  Offset? _quickZoomStart;
  Offset? _quickZoomPrevious;
  var _pendingQuickZoomDy = 0.0;
  var _quickZoomUpdateScheduled = false;
  var _quickZoomChanged = false;
  var _suppressNextDoubleTap = false;

  /// Whether a fling animation is active.
  bool get isFlinging => _flingController.isAnimating;

  /// Whether a pointer or trackpad scale gesture has started.
  bool get isScaleGestureActive => _scaleGestureActive;

  /// Stops active gesture motion before an external camera update.
  void stopFling() {
    _flingController.stop();
    _pan.clearPanSamples();
    _tapZoomTimer?.cancel();
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
    _tapZoomTimer?.cancel();
    _doubleTapSuppressionTimer?.cancel();
    _flingController.dispose();
  }

  /// Handles scroll wheel and pointer signal input.
  void onPointerSignal(PointerSignalEvent event) {
    final bridge = host.gestureBridge;
    if (bridge == null || !host.gestureSettings.zoomEnabled) return;
    if (event is! PointerScrollEvent) return;
    host.beginCameraGesture();
    _flingController.stop();
    final rate = host.gestureOptions.scrollWheelZoomRate;
    final factor = event.scrollDelta.dy < 0 ? 1 + rate : 1 - rate;
    final local = event.localPosition;
    bridge.scaleBy(factor, local.dx, local.dy);
    _scheduleGestureRender();
    host.scheduleRepaint();
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

  // A gesture can begin before the map finishes initializing. Track every
  // pointer and check map availability when applying an update.
  /// Starts tracking a pointer and any tap gesture it may form.
  void onPointerDown(PointerDownEvent event) {
    if (_flingController.isAnimating) {
      _flingController.stop();
      _pan.clearPanSamples();
      host.endCameraGesture();
    }
    if (_pointerPositions.isEmpty) {
      final settings = host.gestureSettings;
      _suppressScaleUntilPointersReleased =
          !settings.scrollEnabled &&
          !settings.zoomEnabled &&
          !settings.rotateEnabled &&
          !settings.tiltEnabled;
      _armQuickZoomFromRawTap(event);
      _singleTapPointer = event.pointer;
      _singleTapMoved = false;
    } else {
      _singleTapPointer = null;
      _singleTapMoved = false;
      _lastTapUpTime = null;
      _lastTapPosition = null;
    }
    _pointerPositions[event.pointer] = event.localPosition;
    _pointerDownPositions[event.pointer] = event.localPosition;
    _pointerDownTimes[event.pointer] = event.timeStamp;
    _pointers.down(event.pointer, event.localPosition);
    if (_pointerPositions.length == 2) {
      _twoFingerTapStarts
        ..clear()
        ..addAll(_pointerDownPositions);
      _twoFingerTapStartedAt = _pointerDownTimes.values.reduce(
        (a, b) => a < b ? a : b,
      );
      _twoFingerTapPossible = true;
    } else if (_pointerPositions.length > 2) {
      _cancelTwoFingerTap();
    }
  }

  /// Stops tracking a pointer and completes any recognized tap gesture.
  void onPointerEnd(PointerEvent event) {
    final wasQuickZoomPointer = event.pointer == _quickZoomPointer;
    _rememberCompletedSingleTap(event, wasQuickZoomPointer);
    final twoFingerTap = _finishTwoFingerTapIfRecognized(event);
    _pointerPositions.remove(event.pointer);
    _pointerDownPositions.remove(event.pointer);
    _pointerDownTimes.remove(event.pointer);
    _pointers.up(event.pointer);
    if (_pointerPositions.isEmpty) {
      _suppressScaleUntilPointersReleased = false;
    }
    if (wasQuickZoomPointer) _finishQuickZoom();
    if (twoFingerTap != null) _zoomByTap(-1, twoFingerTap);
  }

  /// Updates pointer tracking and applies recognized gesture movement.
  void onPointerMove(PointerMoveEvent event) {
    _pointerPositions[event.pointer] = event.localPosition;
    if (event.pointer == _singleTapPointer) {
      final down = _pointerDownPositions[event.pointer];
      if (down != null &&
          (event.localPosition - down).distance > kDoubleTapTouchSlop) {
        _singleTapMoved = true;
      }
    }
    _trackTwoFingerTapMove(event);
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
    if (_quickZoomPointer != null ||
        (_suppressScaleUntilPointersReleased &&
            details.kind != PointerDeviceKind.trackpad)) {
      return;
    }
    _beginScaleGesture();
    _trackpadGestureActive = details.kind == PointerDeviceKind.trackpad;
    _previousTrackpadScale = 1;
    _previousTrackpadRotation = 0;
  }

  void _beginScaleGesture() {
    if (_scaleGestureActive) return;
    _scaleGestureActive = true;
    host.beginCameraGesture();
    _flingController.stop();
    _pan.clearPanSamples();
  }

  /// Applies pan, zoom, and rotation updates from a scale recognizer.
  void onScaleUpdate(ScaleUpdateDetails details) {
    if (_quickZoomPointer != null || !_scaleGestureActive) return;
    final bridge = host.gestureBridge;
    if (bridge == null) return;
    final settings = host.gestureSettings;
    if (_trackpadGestureActive) {
      _applyTrackpadUpdate(bridge, settings, details);

      return;
    }
    // Two or more pointers are handled by the multi-pointer tracker, which
    // reads raw positions rather than this recognizer's aggregate.
    if (details.pointerCount >= 2) return;
    if (!settings.scrollEnabled) return;
    final delta = details.focalPointDelta;
    _pan.addPanSample(delta, DateTime.now());
    bridge.moveBy(delta.dx, delta.dy);
    _scheduleGestureRender();
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
      final scale = trackpadScaleDelta(details.scale, _previousTrackpadScale);
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
        _previousTrackpadRotation,
      );
      if (rotation.abs() > 0.0001) {
        bridge.rotateBy(bearingGestureDelta(rotation));
        cameraChanged = true;
      }
    }
    _previousTrackpadScale = details.scale;
    _previousTrackpadRotation = details.rotation;
    if (cameraChanged) _scheduleGestureRender();
  }

  /// Completes a scale gesture and starts a fling when appropriate.
  void onScaleEnd(ScaleEndDetails details) {
    if (_quickZoomPointer != null) return;
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
    if (options.flingEnabled &&
        details.pointerCount <= 1 &&
        host.gestureSettings.scrollEnabled) {
      final velocity = _pan.estimateVelocity();
      if (_pan.isFling(velocity, threshold: options.flingVelocityThreshold)) {
        _startFling(velocity);
        startedFling = true;
      }
    }
    _clearScaleTracking();
    if (!startedFling) host.endCameraGesture();
  }

  void _clearScaleTracking() {
    _pan.clearPanSamples();
    _trackpadGestureActive = false;
    _previousTrackpadScale = 1;
    _previousTrackpadRotation = 0;
  }

  /// Records the focal point of a possible double tap.
  void onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  /// Applies zoom for a recognized double tap when enabled.
  void onDoubleTap() {
    final settings = host.gestureSettings;
    if (_suppressNextDoubleTap) {
      _suppressNextDoubleTap = false;
      _doubleTapSuppressionTimer?.cancel();

      return;
    }
    if (!doubleClickZoomIsEnabled(
      settings.doubleClickZoomEnabled,
      settings.zoomEnabled,
    )) {
      return;
    }
    final size = host.logicalMapSize;
    final position =
        _doubleTapPosition ?? Offset(size.width / 2, size.height / 2);
    _zoomByTap(1, position, enabled: true);
  }

  void _armQuickZoomFromRawTap(PointerDownEvent event) {
    if (!host.gestureOptions.quickZoomEnabled) return;
    final lastTime = _lastTapUpTime;
    final lastPosition = _lastTapPosition;
    if (lastTime == null || lastPosition == null) return;
    final elapsed = event.timeStamp - lastTime;
    if (elapsed < kDoubleTapMinTime ||
        elapsed > kDoubleTapTimeout ||
        (event.localPosition - lastPosition).distance > kDoubleTapSlop) {
      _lastTapUpTime = null;
      _lastTapPosition = null;

      return;
    }
    _lastTapUpTime = null;
    _lastTapPosition = null;
    _quickZoomPointer = event.pointer;
    _quickZoomStart = event.localPosition;
    _quickZoomPrevious = event.localPosition;
    _pendingQuickZoomDy = 0;
    _quickZoomChanged = false;
  }

  void _rememberCompletedSingleTap(
    PointerEvent event,
    bool wasQuickZoomPointer,
  ) {
    if (event.pointer != _singleTapPointer) return;
    final downTime = _pointerDownTimes[event.pointer];
    final isTap =
        !wasQuickZoomPointer &&
        event is PointerUpEvent &&
        !_singleTapMoved &&
        downTime != null &&
        event.timeStamp - downTime <= kDoubleTapTimeout;
    _singleTapPointer = null;
    _singleTapMoved = false;
    if (isTap) {
      _lastTapUpTime = event.timeStamp;
      _lastTapPosition = event.localPosition;
    } else {
      _lastTapUpTime = null;
      _lastTapPosition = null;
    }
  }

  void _zoomByTap(double amount, Offset position, {bool? enabled}) {
    final bridge = host.gestureBridge;
    if (bridge == null || !(enabled ?? host.gestureSettings.zoomEnabled)) {
      return;
    }
    final duration = host.gestureOptions.doubleTapZoomDuration;
    host.beginCameraGesture();
    _flingController.stop();
    _tapZoomTimer?.cancel();
    bridge.scaleByAnimated(
      amount: amount,
      focus: position,
      duration: duration,
      easing: -1,
    );
    host.scheduleRepaint();
    _tapZoomTimer = Timer(duration, () {
      if (host.gestureBridge == null) return;
      host.renderGesture();
      host.endCameraGesture();
    });
  }

  void _trackTwoFingerTapMove(PointerMoveEvent event) {
    if (!_twoFingerTapPossible) return;
    final start = _twoFingerTapStarts[event.pointer];
    if (start == null ||
        (event.localPosition - start).distance > _twoFingerTapSlop) {
      _cancelTwoFingerTap();
    }
  }

  Offset? _finishTwoFingerTapIfRecognized(PointerEvent event) {
    if (!_twoFingerTapPossible ||
        _pointerPositions.length != 2 ||
        _pointers.mode != TwoFingerGestureMode.undecided ||
        !_twoFingerTapStarts.containsKey(event.pointer)) {
      return null;
    }
    final startedAt = _twoFingerTapStartedAt;
    final elapsed = startedAt == null ? null : event.timeStamp - startedAt;
    final current = _pointerPositions[event.pointer] ?? event.localPosition;
    final start = _twoFingerTapStarts[event.pointer]!;
    if (elapsed == null ||
        elapsed > _twoFingerTapTime ||
        (current - start).distance > _twoFingerTapSlop) {
      _cancelTwoFingerTap();

      return null;
    }
    final points = _pointerPositions.values.toList(growable: false);
    final center = (points[0] + points[1]) / 2;
    _cancelTwoFingerTap();

    return center;
  }

  void _cancelTwoFingerTap() {
    _twoFingerTapPossible = false;
    _twoFingerTapStartedAt = null;
    _twoFingerTapStarts.clear();
  }

  bool _applyQuickZoomMove(PointerMoveEvent event) {
    if (event.pointer != _quickZoomPointer ||
        !host.gestureSettings.zoomEnabled ||
        !host.gestureOptions.quickZoomEnabled) {
      return false;
    }
    final start = _quickZoomStart;
    final previous = _quickZoomPrevious;
    if (start == null || previous == null) return false;
    if (!_quickZoomChanged &&
        (event.localPosition.dy - start.dy).abs() <= _quickZoomSlop) {
      return false;
    }
    if (host.gestureBridge == null) return false;
    if (!_quickZoomChanged) {
      host.beginCameraGesture();
      _flingController.stop();
      _quickZoomChanged = true;
      _suppressNextDoubleTap = true;
    }
    final dy = event.localPosition.dy - previous.dy;
    _quickZoomPrevious = event.localPosition;
    _pendingQuickZoomDy += dy;
    _scheduleQuickZoomUpdate();

    return true;
  }

  void _scheduleQuickZoomUpdate() {
    if (_quickZoomUpdateScheduled) return;
    _quickZoomUpdateScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _quickZoomUpdateScheduled = false;
      _applyPendingQuickZoom();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _applyPendingQuickZoom() {
    final bridge = host.gestureBridge;
    final focus = _quickZoomStart;
    final dy = _pendingQuickZoomDy;
    _pendingQuickZoomDy = 0;
    if (bridge == null || focus == null || dy == 0) return;
    final scale = quickZoomScaleDelta(
      dy,
      sensitivity: host.gestureOptions.quickZoomSensitivity,
    );
    bridge.scaleBy(scale, focus.dx, focus.dy);
    host.renderGesture();
  }

  void _finishQuickZoom() {
    final changed = _quickZoomChanged;
    _applyPendingQuickZoom();
    _clearQuickZoomTracking();
    if (changed) {
      // Listener receives pointer-up before DoubleTapGestureRecognizer. Keep
      // suppression until both have processed the event.
      _doubleTapSuppressionTimer?.cancel();
      _doubleTapSuppressionTimer = Timer(
        const Duration(milliseconds: 100),
        () => _suppressNextDoubleTap = false,
      );
    }
    if (changed && host.gestureBridge != null) {
      _renderGestureNow();
      host.endCameraGesture();
    }
  }

  void _clearQuickZoomTracking() {
    _quickZoomPointer = null;
    _quickZoomStart = null;
    _quickZoomPrevious = null;
    _pendingQuickZoomDy = 0;
    _quickZoomChanged = false;
  }

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
    if (status != AnimationStatus.completed) return;
    if (host.gestureBridge == null) return;
    host.renderGesture();
    host.endCameraGesture();
  }
}

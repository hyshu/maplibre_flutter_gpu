part of 'gesture_coordinator.dart';

class _TapGestureState {
  static const twoFingerTapTime = Duration(milliseconds: 300);
  static const twoFingerTapSlop = 12.0;
  static const quickZoomSlop = 4.0;

  Offset? doubleTapPosition;
  Timer? tapZoomTimer;
  Timer? doubleTapSuppressionTimer;
  final pointerDownPositions = <int, Offset>{};
  final pointerDownTimes = <int, Duration>{};
  final twoFingerTapStarts = <int, Offset>{};
  Duration? twoFingerTapStartedAt;
  var twoFingerTapPossible = false;
  Duration? lastTapUpTime;
  Offset? lastTapPosition;
  int? singleTapPointer;
  var singleTapMoved = false;
  int? quickZoomPointer;
  Offset? quickZoomStart;
  Offset? quickZoomPrevious;
  var pendingQuickZoomDy = 0.0;
  var quickZoomUpdateScheduled = false;
  var quickZoomChanged = false;
  var suppressNextDoubleTap = false;

  void dispose() {
    tapZoomTimer?.cancel();
    doubleTapSuppressionTimer?.cancel();
  }
}

extension _TapGestures on MapGestureCoordinator {
  void _trackTapPointerDown(PointerDownEvent event, bool allowSingleTap) {
    if (_pointerPositions.isEmpty) {
      if (allowSingleTap) _armQuickZoomFromRawTap(event);
      _tap.singleTapPointer = allowSingleTap ? event.pointer : null;
      _tap.singleTapMoved = false;
    } else {
      _tap.singleTapPointer = null;
      _tap.singleTapMoved = false;
      _tap.lastTapUpTime = null;
      _tap.lastTapPosition = null;
    }
    _tap.pointerDownPositions[event.pointer] = event.localPosition;
    _tap.pointerDownTimes[event.pointer] = event.timeStamp;
  }

  void _trackTwoFingerTapDown() {
    if (_pointerPositions.length == 2) {
      _tap.twoFingerTapStarts
        ..clear()
        ..addAll(_tap.pointerDownPositions);
      _tap.twoFingerTapStartedAt = _tap.pointerDownTimes.values.reduce(
        (a, b) => a < b ? a : b,
      );
      _tap.twoFingerTapPossible = true;
    } else if (_pointerPositions.length > 2) {
      _cancelTwoFingerTap();
    }
  }

  void _trackTapPointerMove(PointerMoveEvent event) {
    if (event.pointer == _tap.singleTapPointer) {
      final down = _tap.pointerDownPositions[event.pointer];
      if (down != null &&
          (event.localPosition - down).distance > kDoubleTapTouchSlop) {
        _tap.singleTapMoved = true;
      }
    }
    _trackTwoFingerTapMove(event);
  }

  void _forgetTapPointer(int pointer) {
    _tap.pointerDownPositions.remove(pointer);
    _tap.pointerDownTimes.remove(pointer);
  }

  void _handleDoubleTap() {
    final settings = host.gestureSettings;
    if (_tap.suppressNextDoubleTap) {
      _tap.suppressNextDoubleTap = false;
      _tap.doubleTapSuppressionTimer?.cancel();

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
        _tap.doubleTapPosition ?? Offset(size.width / 2, size.height / 2);
    _zoomByTap(1, position, enabled: true);
  }

  void _armQuickZoomFromRawTap(PointerDownEvent event) {
    if (!host.gestureOptions.quickZoomEnabled) return;
    final lastTime = _tap.lastTapUpTime;
    final lastPosition = _tap.lastTapPosition;
    if (lastTime == null || lastPosition == null) return;
    final elapsed = event.timeStamp - lastTime;
    if (elapsed < kDoubleTapMinTime ||
        elapsed > kDoubleTapTimeout ||
        (event.localPosition - lastPosition).distance > kDoubleTapSlop) {
      _tap.lastTapUpTime = null;
      _tap.lastTapPosition = null;

      return;
    }
    _tap.lastTapUpTime = null;
    _tap.lastTapPosition = null;
    _tap.quickZoomPointer = event.pointer;
    _tap.quickZoomStart = event.localPosition;
    _tap.quickZoomPrevious = event.localPosition;
    _tap.pendingQuickZoomDy = 0;
    _tap.quickZoomChanged = false;
  }

  void _rememberCompletedSingleTap(
    PointerEvent event,
    bool wasQuickZoomPointer,
  ) {
    if (event.pointer != _tap.singleTapPointer) return;
    final downTime = _tap.pointerDownTimes[event.pointer];
    final isTap =
        !wasQuickZoomPointer &&
        event is PointerUpEvent &&
        !_tap.singleTapMoved &&
        downTime != null &&
        event.timeStamp - downTime <= kDoubleTapTimeout;
    _tap.singleTapPointer = null;
    _tap.singleTapMoved = false;
    if (isTap) {
      _tap.lastTapUpTime = event.timeStamp;
      _tap.lastTapPosition = event.localPosition;
    } else {
      _tap.lastTapUpTime = null;
      _tap.lastTapPosition = null;
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
    _tap.tapZoomTimer?.cancel();
    bridge.scaleByAnimated(
      amount: amount,
      focus: position,
      duration: duration,
      easing: -1,
    );
    host.scheduleRepaint();
    _tap.tapZoomTimer = Timer(duration, () {
      if (host.gestureBridge == null) return;
      host.renderGesture();
      host.endCameraGesture();
    });
  }

  void _trackTwoFingerTapMove(PointerMoveEvent event) {
    if (!_tap.twoFingerTapPossible) return;
    final start = _tap.twoFingerTapStarts[event.pointer];
    if (start == null ||
        (event.localPosition - start).distance >
            _TapGestureState.twoFingerTapSlop) {
      _cancelTwoFingerTap();
    }
  }

  Offset? _finishTwoFingerTapIfRecognized(PointerEvent event) {
    if (event is! PointerUpEvent) {
      _cancelTwoFingerTap();

      return null;
    }
    if (!_tap.twoFingerTapPossible ||
        _pointerPositions.length != 2 ||
        _pointers.mode != .undecided ||
        !_tap.twoFingerTapStarts.containsKey(event.pointer)) {
      return null;
    }
    final startedAt = _tap.twoFingerTapStartedAt;
    final elapsed = startedAt == null ? null : event.timeStamp - startedAt;
    final current = _pointerPositions[event.pointer] ?? event.localPosition;
    final start = _tap.twoFingerTapStarts[event.pointer]!;
    if (elapsed == null ||
        elapsed > _TapGestureState.twoFingerTapTime ||
        (current - start).distance > _TapGestureState.twoFingerTapSlop) {
      _cancelTwoFingerTap();

      return null;
    }
    final points = _pointerPositions.values.toList(growable: false);
    final center = (points[0] + points[1]) / 2;
    _cancelTwoFingerTap();

    return center;
  }

  void _cancelTwoFingerTap() {
    _tap.twoFingerTapPossible = false;
    _tap.twoFingerTapStartedAt = null;
    _tap.twoFingerTapStarts.clear();
  }

  bool _applyQuickZoomMove(PointerMoveEvent event) {
    if (event.pointer != _tap.quickZoomPointer ||
        !host.gestureSettings.zoomEnabled ||
        !host.gestureOptions.quickZoomEnabled) {
      return false;
    }
    final start = _tap.quickZoomStart;
    final previous = _tap.quickZoomPrevious;
    if (start == null || previous == null) return false;
    if (!_tap.quickZoomChanged &&
        (event.localPosition.dy - start.dy).abs() <=
            _TapGestureState.quickZoomSlop) {
      return false;
    }
    if (host.gestureBridge == null) return false;
    if (!_tap.quickZoomChanged) {
      host.beginCameraGesture();
      _flingController.stop();
      _tap.quickZoomChanged = true;
      _tap.suppressNextDoubleTap = true;
    }
    final dy = event.localPosition.dy - previous.dy;
    _tap.quickZoomPrevious = event.localPosition;
    _tap.pendingQuickZoomDy += dy;
    _scheduleQuickZoomUpdate();

    return true;
  }

  void _scheduleQuickZoomUpdate() {
    if (_tap.quickZoomUpdateScheduled) return;
    _tap.quickZoomUpdateScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _tap.quickZoomUpdateScheduled = false;
      _applyPendingQuickZoom();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _applyPendingQuickZoom() {
    final bridge = host.gestureBridge;
    final focus = _tap.quickZoomStart;
    final dy = _tap.pendingQuickZoomDy;
    _tap.pendingQuickZoomDy = 0;
    if (bridge == null || focus == null || dy == 0) return;
    final scale = quickZoomScaleDelta(
      dy,
      sensitivity: host.gestureOptions.quickZoomSensitivity,
    );
    bridge.scaleBy(scale, focus.dx, focus.dy);
    host.renderGesture();
  }

  void _finishQuickZoom() {
    final changed = _tap.quickZoomChanged;
    _applyPendingQuickZoom();
    _clearQuickZoomTracking();
    if (changed) {
      // Listener receives pointer-up before DoubleTapGestureRecognizer. Keep
      // suppression until both have processed the event.
      _tap.doubleTapSuppressionTimer?.cancel();
      _tap.doubleTapSuppressionTimer = Timer(
        const Duration(milliseconds: 100),
        () => _tap.suppressNextDoubleTap = false,
      );
    }
    if (changed && host.gestureBridge != null) {
      _renderGestureNow();
      host.endCameraGesture();
    }
  }

  void _clearQuickZoomTracking() {
    _tap.quickZoomPointer = null;
    _tap.quickZoomStart = null;
    _tap.quickZoomPrevious = null;
    _tap.pendingQuickZoomDy = 0;
    _tap.quickZoomChanged = false;
  }
}

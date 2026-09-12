part of 'maplibre_map_controller.dart';

mixin _CameraController on _ControllerBinding {
  CameraPosition? _cameraPosition;
  var _cameraTransitionGeneration = 0;

  /// The latest camera position cached by this controller.
  ///
  /// The cache is initialized before [MapLibreMap.onMapCreated] is called, so a
  /// controller received there has a non-null position. Reading this property
  /// does not query MapLibre. Use [queryCameraPosition] to refresh the cache
  /// before reading the result.
  CameraPosition? get cameraPosition {
    _ensureNotDisposed();

    return _cameraPosition;
  }

  /// Whether a programmatic camera transition or pending update is active.
  ///
  /// This includes transitions started by [animateCamera] and [easeCamera]. It
  /// returns `false` when the runtime cannot report camera movement.
  bool get isCameraMoving {
    _ensureNotDisposed();

    return _bridge.isCameraMoving();
  }

  /// Moves the camera immediately according to `update`.
  ///
  /// Starting this move interrupts the completion of any earlier
  /// [animateCamera] or [easeCamera] call. The returned future completes with
  /// `true` when MapLibre accepts the update and `false` when it cannot be
  /// applied. This implementation does not return `null`.
  ///
  /// A successful result does not wait for the updated map frame to render.
  Future<bool?> moveCamera(CameraUpdate update) async {
    _ensureNotDisposed();
    _cameraTransitionGeneration++;
    final applied = _applyCameraUpdate(
      update,
      duration: Duration.zero,
      interpolation: null,
      flyTo: false,
    );
    if (!applied) return false;
    _cameraChanged();

    return true;
  }

  /// Animates the camera according to `update`.
  ///
  /// Full camera positions and geographic bounds request a flight transition.
  /// [CameraUpdate.scrollBy] and [CameraUpdate.zoomBy] use their corresponding
  /// animated operations. Full camera positions, scrolling, and zooming fall
  /// back to eased or immediate moves when their animated operations are
  /// unavailable. Geographic bounds require native camera fitting support.
  ///
  /// `duration` defaults to 300 milliseconds. A duration of [Duration.zero]
  /// applies the update immediately.
  ///
  /// The returned future completes with `true` after the transition settles. It
  /// completes with `false` when MapLibre rejects the update, a newer camera
  /// update or gesture interrupts the transition, the transition does not
  /// settle, or the controller is disposed before completion. This
  /// implementation does not return `null`.
  Future<bool?> animateCamera(CameraUpdate update, {Duration? duration}) async {
    _ensureNotDisposed();
    final transitionDuration = duration ?? const Duration(milliseconds: 300);
    final generation = ++_cameraTransitionGeneration;
    final applied = _applyCameraUpdate(
      update,
      duration: transitionDuration,
      interpolation: null,
      flyTo: true,
    );
    if (!applied) return false;
    _cameraChanged();

    return _waitForCameraTransition(transitionDuration, generation);
  }

  /// Animates the camera according to `update` using an easing transition.
  ///
  /// `duration` defaults to 300 milliseconds. A duration of [Duration.zero]
  /// applies the update immediately. When `interpolation` is `null`, MapLibre
  /// chooses its default interpolation. An unavailable easing operation falls
  /// back to an immediate move.
  ///
  /// The returned future completes with `true` after the transition settles. It
  /// completes with `false` when MapLibre rejects the update, a newer camera
  /// update or gesture interrupts the transition, the transition does not
  /// settle, or the controller is disposed before completion.
  Future<bool> easeCamera(
    CameraUpdate update, {
    Duration? duration,
    CameraAnimationInterpolation? interpolation,
  }) async {
    _ensureNotDisposed();
    final transitionDuration = duration ?? const Duration(milliseconds: 300);
    final generation = ++_cameraTransitionGeneration;
    final applied = _applyCameraUpdate(
      update,
      duration: transitionDuration,
      interpolation: interpolation,
      flyTo: false,
    );
    if (!applied) return false;
    _cameraChanged();

    return _waitForCameraTransition(transitionDuration, generation);
  }

  /// Queries MapLibre for the current camera position and updates the cache.
  ///
  /// The returned future completes with the refreshed [cameraPosition]. A
  /// controller received from [MapLibreMap.onMapCreated] completes with a
  /// non-null position while it remains active.
  Future<CameraPosition?> queryCameraPosition() async {
    _ensureNotDisposed();
    _syncCameraFromBridge();

    return _cameraPosition;
  }

  /// Animates the camera to fit the given geographic bounds.
  ///
  /// `west`, `north`, `south`, and `east` are specified in degrees. `padding` is
  /// applied equally to every viewport edge in logical pixels. `duration`
  /// defaults to 200 milliseconds. A duration of [Duration.zero] applies the
  /// update immediately.
  ///
  /// The returned future completes when the transition settles, is interrupted,
  /// or is rejected. It does not report whether MapLibre accepted the update.
  /// Use [animateCamera] with [CameraUpdate.newLatLngBounds] when that result is
  /// needed.
  Future<void> setCameraBounds({
    required double west,
    required double north,
    required double south,
    required double east,
    required int padding,
    Duration duration = const Duration(milliseconds: 200),
  }) => animateCamera(
    CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(south, west),
        northeast: LatLng(north, east),
      ),
      left: padding.toDouble(),
      top: padding.toDouble(),
      right: padding.toDouble(),
      bottom: padding.toDouble(),
    ),
    duration: duration,
  );

  /// Changes the logical-pixel insets used for camera calculations.
  ///
  /// Each edge in `insets` is measured inward from the corresponding edge of the
  /// [MapLibreMap]. When `animated` is `false`, the change is immediate. When it
  /// is `true`, the camera transitions for `duration`, which defaults to 300
  /// milliseconds.
  ///
  /// The returned future completes after an immediate update is accepted or an
  /// animated transition settles or is interrupted. It throws a [StateError]
  /// when MapLibre rejects the insets.
  Future<void> updateContentInsets(
    EdgeInsets insets, [
    bool animated = false,
    Duration duration = const Duration(milliseconds: 300),
  ]) async {
    _ensureNotDisposed();
    final generation = ++_cameraTransitionGeneration;
    _bridge.setContentInsets(
      top: insets.top,
      left: insets.left,
      bottom: insets.bottom,
      right: insets.right,
      animated: animated,
      duration: duration,
    );
    _cameraChanged();
    if (animated) await _waitForCameraTransition(duration, generation);
  }

  /// Resets the camera bearing to north using the cached [cameraPosition].
  ///
  /// The returned future completes after the immediate camera update is
  /// requested. It does not wait for the updated map frame to render. Target,
  /// zoom, and tilt come from the cache. Consider calling [queryCameraPosition]
  /// first when the camera might have changed since the last rendered frame.
  /// This method does nothing when [cameraPosition] is `null`.
  Future<void> resetNorth() async {
    _ensureNotDisposed();
    final current = _cameraPosition;
    if (current == null) return;

    await moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: current.target,
          zoom: current.zoom,
          tilt: current.tilt,
        ),
      ),
    );
  }

  bool _applyCameraUpdate(
    CameraUpdate update, {
    required Duration duration,
    required CameraAnimationInterpolation? interpolation,
    required bool flyTo,
  }) {
    final current = _cameraPosition;
    if (current == null) return false;
    final easing = interpolation?.index ?? -1;
    switch (update.kind) {
      case .bounds:
        final bounds = update.bounds!;

        return _bridge.fitCameraBounds(
          south: bounds.southwest.latitude,
          west: bounds.west,
          north: bounds.northeast.latitude,
          east: bounds.east,
          left: update.left,
          top: update.top,
          right: update.right,
          bottom: update.bottom,
          duration: duration,
          easing: easing,
          flyTo: flyTo,
        );
      case .scroll:
        if (duration == Duration.zero) {
          _bridge.moveBy(update.dx, update.dy);

          return true;
        }
        return _bridge.moveByAnimated(
          dx: update.dx,
          dy: update.dy,
          duration: duration,
          easing: easing,
        );
      case .zoomBy:
        return _bridge.scaleByAnimated(
          amount: update.amount,
          focus: update.focus,
          duration: duration,
          easing: easing,
        );
      default:
        final next = update.resolveAgainst(current);
        if (duration == Duration.zero) {
          _bridge.setCameraFull(
            next.target.latitude,
            next.target.longitude,
            next.zoom,
            next.bearing,
            next.tilt,
          );

          return true;
        }
        if (flyTo) {
          return _bridge.animateCameraFull(
            latitude: next.target.latitude,
            longitude: next.target.longitude,
            zoom: next.zoom,
            bearing: next.bearing,
            pitch: next.tilt,
            duration: duration,
          );
        }
        return _bridge.easeCameraFull(
          latitude: next.target.latitude,
          longitude: next.target.longitude,
          zoom: next.zoom,
          bearing: next.bearing,
          pitch: next.tilt,
          duration: duration,
          easing: easing,
        );
    }
  }

  void _cameraChanged() {
    final callback = _onCameraChangeRequested;
    if (callback != null) {
      callback();
    } else if (_syncCameraFromBridge()) {
      notifyListeners();
    }
  }

  Future<bool> _waitForCameraTransition(
    Duration duration,
    int generation,
  ) async {
    if (duration == Duration.zero) return true;
    final timeout = duration + const Duration(seconds: 2);
    final stopwatch = Stopwatch()..start();
    var observedMoving = false;
    while (!_disposed && stopwatch.elapsed < timeout) {
      if (generation != _cameraTransitionGeneration) return false;
      final moving = _bridge.isCameraMoving();
      observedMoving = observedMoving || moving;
      if (observedMoving && !moving) {
        _syncCameraFromBridge();

        return true;
      }
      if (!observedMoving && stopwatch.elapsed >= duration) {
        _syncCameraFromBridge();

        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    return !_disposed &&
        generation == _cameraTransitionGeneration &&
        !_bridge.isCameraMoving();
  }

  /// Transfers camera ownership to a gesture.
  ///
  /// This package-internal hook cancels the native transition and causes the
  /// future from an active [animateCamera] or [easeCamera] call to complete with
  /// `false`. It does nothing after the controller is disposed.
  @internal
  void notifyCameraGestureStarted() {
    if (_disposed) return;
    _bridge.cancelCameraTransitions();
    _cameraTransitionGeneration++;
  }

  bool _syncCameraFromBridge() {
    final camera = _bridge.getCamera();
    final next = CameraPosition(
      bearing: camera.bearing,
      target: LatLng(camera.latitude, camera.longitude),
      tilt: camera.pitch,
      zoom: camera.zoom,
    );
    if (next == _cameraPosition) return false;
    _cameraPosition = next;

    return true;
  }

  /// Synchronizes the cached camera after a map frame or gesture update.
  ///
  /// This method is for package code. It returns `true` when the MapLibre camera
  /// differs from the cached [cameraPosition]. When `notifyListeners` is `true`,
  /// a changed position or [viewportChanged] also notifies listeners.
  /// The caller reports viewport changes after a native frame is available
  /// so listeners can project coordinates using the updated viewport.
  bool notifyCameraChanged({
    bool notifyListeners = true,
    bool viewportChanged = false,
  }) {
    _ensureNotDisposed();
    final changed = _syncCameraFromBridge();
    if ((changed || viewportChanged) && notifyListeners) {
      super.notifyListeners();
    }
    return changed;
  }

  void _disposeCamera() {
    _cameraTransitionGeneration++;
    _cameraPosition = null;
  }
}

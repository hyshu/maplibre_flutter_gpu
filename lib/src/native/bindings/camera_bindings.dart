part of '../maplibre_ffi.dart';

/// Camera reads, immediate moves, and animated transitions.
///
/// Optional native operations use a documented fallback when possible.
/// Animated moves become immediate moves, while unavailable bearing and pitch
/// reads return zero.
mixin MaplibreBridgeCameraBindings {
  BridgeSessionLifecycle get _lifecycle;
  NativeSymbolTable get _symbols;
  Pointer<Double> get _cameraPositionOutput;

  // The bridge resolves these native callbacks. A callback remains optional
  // when the corresponding operation has a fallback.
  late final SetCameraD _setCamera;
  SetCameraFullD? _setCameraFull;
  VoidDoubleD? _setMaxPitch;
  VoidDoubleD? _setMinPitch;
  SetBoundsD? _setBounds;
  late final DoubleVoidD _getCameraLat;
  late final DoubleVoidD _getCameraLon;
  late final DoubleVoidD _getCameraZoom;
  GetCameraD? _getCamera;
  DoubleVoidD? _getCameraBearing;
  DoubleVoidD? _getCameraPitch;
  AdjustByD? _rotateBy;
  AdjustByD? _pitchBy;
  CameraEaseD? _cameraEase;
  CameraFlyD? _cameraFly;
  CameraMoveAnimatedD? _cameraMoveAnimated;
  CameraScaleAnimatedD? _cameraScaleAnimated;
  CameraFitBoundsD? _cameraFitBounds;
  Int32VoidD? _isCameraMoving;
  Int32VoidD? _cancelCameraTransitions;
  late final MoveByD _moveBy;
  late final ScaleByD _scaleBy;

  /// Immediately sets the camera center and zoom.
  void setCamera(double lat, double lon, double zoom) {
    _lifecycle.ensureActive();
    _setCamera(lat, lon, zoom);
  }

  /// Immediately sets the complete camera position.
  ///
  /// Latitude, longitude, bearing, and pitch are expressed in degrees. When
  /// the full operation is unavailable, only the center and zoom are applied.
  void setCameraFull(
    double lat,
    double lon,
    double zoom,
    double bearing,
    double pitch,
  ) {
    _lifecycle.ensureActive();
    final callback = _setCameraFull;
    if (callback != null) {
      callback(lat, lon, zoom, bearing, pitch);
    } else {
      _setCamera(lat, lon, zoom);
    }
  }

  /// Sets the maximum camera pitch in degrees.
  ///
  /// Returns false when the native operation is unavailable.
  bool setMaxPitch(double pitch) {
    _lifecycle.ensureActive();
    final callback = _setMaxPitch;
    if (callback == null) return false;
    callback(pitch);

    return true;
  }

  /// Sets the minimum camera pitch in degrees.
  ///
  /// Returns false when the native operation is unavailable.
  bool setMinPitch(double pitch) {
    _lifecycle.ensureActive();
    final callback = _setMinPitch;
    if (callback == null) return false;
    callback(pitch);

    return true;
  }

  /// Eases to the complete camera position over [duration].
  ///
  /// Falls back to an immediate move when animated transitions are
  /// unavailable. Returns whether the transition was accepted.
  bool easeCameraFull({
    required double latitude,
    required double longitude,
    required double zoom,
    required double bearing,
    required double pitch,
    required Duration duration,
    required int easing,
  }) {
    _lifecycle.ensureActive();
    final callback = _cameraEase;
    if (callback == null) {
      setCameraFull(latitude, longitude, zoom, bearing, pitch);

      return true;
    }
    return callback(
          latitude,
          longitude,
          zoom,
          bearing,
          pitch,
          duration.inMilliseconds,
          easing,
        ) !=
        0;
  }

  /// Flies to the complete camera position over [duration].
  ///
  /// Falls back to an eased transition or an immediate move when necessary.
  /// Returns whether the transition was accepted.
  bool animateCameraFull({
    required double latitude,
    required double longitude,
    required double zoom,
    required double bearing,
    required double pitch,
    required Duration duration,
  }) {
    _lifecycle.ensureActive();
    final callback = _cameraFly;
    if (callback == null) {
      return easeCameraFull(
        latitude: latitude,
        longitude: longitude,
        zoom: zoom,
        bearing: bearing,
        pitch: pitch,
        duration: duration,
        easing: -1,
      );
    }
    return callback(
          latitude,
          longitude,
          zoom,
          bearing,
          pitch,
          duration.inMilliseconds,
          -1,
        ) !=
        0;
  }

  /// Moves the camera by a logical-pixel offset over [duration].
  ///
  /// Falls back to an immediate move when animated transitions are
  /// unavailable. Returns whether the transition was accepted.
  bool moveByAnimated({
    required double dx,
    required double dy,
    required Duration duration,
    required int easing,
  }) {
    _lifecycle.ensureActive();
    final callback = _cameraMoveAnimated;
    if (callback == null) {
      moveBy(dx, dy);

      return true;
    }
    return callback(dx, dy, duration.inMilliseconds, easing) != 0;
  }

  /// Changes zoom by [amount] over [duration].
  ///
  /// [amount] is a zoom-level delta rather than a scale factor. When provided,
  /// [focus] is the logical-pixel position that remains fixed. The operation
  /// falls back to an immediate scale or camera update when animation is
  /// unavailable. Returns whether the transition was accepted.
  bool scaleByAnimated({
    required double amount,
    Offset? focus,
    required Duration duration,
    required int easing,
  }) {
    _lifecycle.ensureActive();
    final scale = math.pow(2.0, amount).toDouble();
    final callback = _cameraScaleAnimated;
    if (callback == null) {
      if (focus != null) {
        scaleBy(scale, focus.dx, focus.dy);
      } else {
        setCameraFull(
          getCameraLat(),
          getCameraLon(),
          getCameraZoom() + amount,
          getCameraBearing(),
          getCameraPitch(),
        );
      }
      return true;
    }
    return callback(
          scale,
          focus == null ? 0 : 1,
          focus?.dx ?? 0,
          focus?.dy ?? 0,
          duration.inMilliseconds,
          easing,
        ) !=
        0;
  }

  /// Fits the camera to the geographic bounds and logical-pixel padding.
  ///
  /// Uses a flight when [flyTo] is true and [duration] is nonzero. Otherwise it
  /// uses easing or an immediate move. Returns whether the move was accepted.
  /// Throws an [UnsupportedError] when the native operation is unavailable.
  bool fitCameraBounds({
    required double south,
    required double west,
    required double north,
    required double east,
    required double left,
    required double top,
    required double right,
    required double bottom,
    required Duration duration,
    required int easing,
    required bool flyTo,
  }) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(
      _cameraFitBounds,
      'CameraUpdate.newLatLngBounds',
    );

    return callback(
          south,
          west,
          north,
          east,
          left,
          top,
          right,
          bottom,
          duration.inMilliseconds,
          easing,
          flyTo ? 1 : 0,
        ) !=
        0;
  }

  /// Whether a camera transition or pending camera update is active.
  ///
  /// Returns false when the native operation is unavailable.
  bool isCameraMoving() {
    _lifecycle.ensureActive();

    return (_isCameraMoving?.call() ?? 0) != 0;
  }

  /// Cancels active camera transitions when supported by the native library.
  void cancelCameraTransitions() {
    _lifecycle.ensureActive();
    _cancelCameraTransitions?.call();
  }

  /// Sets geographic and zoom constraints for the camera.
  ///
  /// Geographic bounds are applied only when all four coordinates are given.
  /// Omitting them clears the geographic constraint. Minimum and maximum zoom
  /// can be set independently. The call does nothing when unsupported.
  void setBounds({
    double? south,
    double? west,
    double? north,
    double? east,
    double? minZoom,
    double? maxZoom,
  }) {
    _lifecycle.ensureActive();
    final hasBounds =
        south != null && west != null && north != null && east != null;
    _setBounds?.call(
      hasBounds ? 1 : 0,
      south ?? 0,
      west ?? 0,
      north ?? 0,
      east ?? 0,
      minZoom == null ? 0 : 1,
      minZoom ?? 0,
      maxZoom == null ? 0 : 1,
      maxZoom ?? 0,
    );
  }

  /// Returns the camera center latitude in degrees.
  double getCameraLat() {
    _lifecycle.ensureActive();

    return _getCameraLat();
  }

  /// Returns the camera center longitude in degrees.
  double getCameraLon() {
    _lifecycle.ensureActive();

    return _getCameraLon();
  }

  /// Returns the current camera zoom level.
  double getCameraZoom() {
    _lifecycle.ensureActive();

    return _getCameraZoom();
  }

  /// Returns the camera bearing in degrees, or zero when unavailable.
  double getCameraBearing() {
    _lifecycle.ensureActive();

    return _getCameraBearing?.call() ?? 0;
  }

  /// Returns the camera pitch in degrees, or zero when unavailable.
  double getCameraPitch() {
    _lifecycle.ensureActive();

    return _getCameraPitch?.call() ?? 0;
  }

  /// Returns the current center, zoom, bearing, and pitch.
  ///
  /// Falls back to individual camera reads when the combined native operation
  /// is unavailable.
  ({
    double latitude,
    double longitude,
    double zoom,
    double bearing,
    double pitch,
  })
  getCamera() {
    _lifecycle.ensureActive();
    final callback = _getCamera;
    if (callback != null && callback(_cameraPositionOutput) != 0) {
      final values = _cameraPositionOutput.asTypedList(5);

      return (
        latitude: values[0],
        longitude: values[1],
        zoom: values[2],
        bearing: values[3],
        pitch: values[4],
      );
    }
    return (
      latitude: _getCameraLat(),
      longitude: _getCameraLon(),
      zoom: _getCameraZoom(),
      bearing: _getCameraBearing?.call() ?? 0,
      pitch: _getCameraPitch?.call() ?? 0,
    );
  }

  /// Immediately moves the camera by a logical-pixel offset.
  void moveBy(double dx, double dy) {
    _lifecycle.ensureActive();
    _moveBy(dx, dy);
  }

  /// Immediately scales the camera around a logical-pixel position.
  ///
  /// [scale] is a multiplicative scale factor.
  void scaleBy(double scale, double cx, double cy) {
    _lifecycle.ensureActive();
    _scaleBy(scale, cx, cy);
  }

  /// Immediately changes the camera bearing by [degrees].
  ///
  /// Does nothing when the native operation is unavailable.
  void rotateBy(double degrees) {
    _lifecycle.ensureActive();
    _rotateBy?.call(degrees);
  }

  /// Immediately changes the camera pitch by [degrees].
  ///
  /// Does nothing when the native operation is unavailable.
  void pitchBy(double degrees) {
    _lifecycle.ensureActive();
    _pitchBy?.call(degrees);
  }
}

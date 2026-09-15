import 'dart:math' as math;

import 'package:flutter/widgets.dart' show EdgeInsets, Offset;
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';

/// Records native calls while keeping a mutable camera and style snapshot.
class FakeControllerBridge implements MaplibreBridge {
  new() : lat = 35, lon = 139, zoom = 12, bearing = 15, pitch = 30;

  double lat;
  double lon;
  double zoom;
  double bearing;
  double pitch;
  var callCount = 0;
  var cameraSnapshotCallCount = 0;
  double? lastMoveDx;
  double? lastMoveDy;
  double? lastZoomAmount;
  Offset? lastZoomFocus;
  Duration? lastDuration;
  int? lastEasing;
  var usedFlight = false;
  bool? lastFitFlight;
  double? lastFitWest;
  double? lastFitEast;
  var cancelCount = 0;
  String? styleValue;
  final List<String> layerIds = ['background', 'roads'];
  final List<String> sourceIds = ['composite'];
  final Map<String, bool> layerVisibility = {'background': true, 'roads': true};
  final Map<String, String?> layerFilters = {};
  void Function(String operation)? onStyleNativeCall;

  @override
  void setStyle(String value) {
    onStyleNativeCall?.call('style');
    callCount++;
    styleValue = value;
  }

  @override
  String? getStyle() {
    callCount++;

    return styleValue;
  }

  @override
  List<String> getLayerIds() {
    callCount++;

    return List.of(layerIds);
  }

  @override
  List<String> getSourceIds() {
    callCount++;

    return List.of(sourceIds);
  }

  @override
  void setLayerVisibility(String layerId, bool visible) {
    onStyleNativeCall?.call('visibility');
    callCount++;
    if (!layerVisibility.containsKey(layerId)) {
      throw StateError('layer not found: $layerId');
    }
    layerVisibility[layerId] = visible;
  }

  @override
  bool? getLayerVisibility(String layerId) {
    callCount++;

    return layerVisibility[layerId];
  }

  @override
  bool setLayerFilterJson(String layerId, String filterJson) {
    onStyleNativeCall?.call('filter');
    callCount++;
    if (!layerVisibility.containsKey(layerId)) return false;
    layerFilters[layerId] = filterJson;

    return true;
  }

  @override
  void setFilterJson(String layerId, String filterJson) {
    if (!setLayerFilterJson(layerId, filterJson)) {
      throw StateError('layer not found: $layerId');
    }
  }

  @override
  String? getLayerFilterJson(String layerId) {
    callCount++;

    return layerFilters[layerId];
  }

  @override
  double getCameraLat() {
    callCount++;

    return lat;
  }

  @override
  double getCameraLon() {
    callCount++;

    return lon;
  }

  @override
  double getCameraZoom() {
    callCount++;

    return zoom;
  }

  @override
  double getCameraBearing() {
    callCount++;

    return bearing;
  }

  @override
  double getCameraPitch() {
    callCount++;

    return pitch;
  }

  @override
  ({
    double latitude,
    double longitude,
    double zoom,
    double bearing,
    double pitch,
  })
  getCamera() {
    callCount++;
    cameraSnapshotCallCount++;

    return (
      latitude: lat,
      longitude: lon,
      zoom: zoom,
      bearing: bearing,
      pitch: pitch,
    );
  }

  @override
  void setCamera(double nextLat, double nextLon, double nextZoom) {
    callCount++;
    lat = nextLat;
    lon = nextLon;
    zoom = nextZoom;
  }

  @override
  void setCameraFull(
    double nextLat,
    double nextLon,
    double nextZoom,
    double nextBearing,
    double nextPitch,
  ) {
    callCount++;
    lat = nextLat;
    lon = nextLon;
    zoom = nextZoom;
    bearing = nextBearing;
    pitch = nextPitch;
  }

  @override
  bool easeCameraFull({
    required double latitude,
    required double longitude,
    required double zoom,
    required double bearing,
    required double pitch,
    required Duration duration,
    required int easing,
  }) {
    setCameraFull(latitude, longitude, zoom, bearing, pitch);
    lastDuration = duration;
    lastEasing = easing;

    return true;
  }

  @override
  bool animateCameraFull({
    required double latitude,
    required double longitude,
    required double zoom,
    required double bearing,
    required double pitch,
    required Duration duration,
  }) {
    setCameraFull(latitude, longitude, zoom, bearing, pitch);
    lastDuration = duration;
    usedFlight = true;

    return true;
  }

  @override
  void moveBy(double dx, double dy) {
    callCount++;
    lastMoveDx = dx;
    lastMoveDy = dy;
  }

  @override
  bool moveByAnimated({
    required double dx,
    required double dy,
    required Duration duration,
    required int easing,
  }) {
    moveBy(dx, dy);
    lastDuration = duration;
    lastEasing = easing;

    return true;
  }

  @override
  bool scaleByAnimated({
    required double amount,
    Offset? focus,
    required Duration duration,
    required int easing,
  }) {
    callCount++;
    lastZoomAmount = amount;
    lastZoomFocus = focus;
    lastDuration = duration;
    lastEasing = easing;
    zoom += amount;

    return true;
  }

  @override
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
    callCount++;
    lat = (south + north) / 2;
    lon = (west + east) / 2;
    bearing = 0;
    pitch = 0;
    zoom = 10;
    lastDuration = duration;
    lastEasing = easing;
    lastFitFlight = flyTo;
    lastFitWest = west;
    lastFitEast = east;

    return true;
  }

  @override
  bool isCameraMoving() => false;

  @override
  void cancelCameraTransitions() {
    cancelCount++;
  }

  @override
  ({double south, double west, double north, double east}) getVisibleRegion() =>
      (south: 34, west: 138, north: 36, east: 140);

  @override
  double getMetersPerPixelAtLatitude(double latitude) => latitude * 2;

  EdgeInsets? lastContentInsets;
  bool? lastContentInsetsAnimated;
  Duration? lastContentInsetsDuration;

  @override
  void setContentInsets({
    required double top,
    required double left,
    required double bottom,
    required double right,
    required bool animated,
    required Duration duration,
  }) {
    callCount++;
    lastContentInsets = EdgeInsets.fromLTRB(left, top, right, bottom);
    lastContentInsetsAnimated = animated;
    lastContentInsetsDuration = duration;
  }

  @override
  Offset latLonToScreen(double lat, double lon) {
    callCount++;

    return Offset.zero;
  }

  @override
  var logicalWidth = 800;

  @override
  var logicalHeight = 600;

  @override
  List<Offset> wrappedLatLonsToScreen(
    List<({double latitude, double longitude, int tileWrap})> coordinates,
  ) {
    final worldSize = 512 * math.pow(2, zoom);

    return [
      for (final coordinate in coordinates)
        Offset(
          logicalWidth / 2 +
              (coordinate.longitude + coordinate.tileWrap * 360 - lon) /
                  360 *
                  worldSize,
          logicalHeight / 2,
        ),
    ];
  }

  @override
  ({double latitude, double longitude}) screenToLatLon(double x, double y) {
    callCount++;

    return (latitude: y, longitude: x);
  }

  @override
  List<LabelData> getPlacedLabels() {
    callCount++;

    return const [];
  }

  @override
  bool isMapIdle() {
    callCount++;

    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'dart:async' show Completer, unawaited;
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';

class _FakeBridge implements MaplibreBridge {
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
  int get logicalWidth => 800;

  @override
  int get logicalHeight => 600;

  @override
  List<Offset> wrappedLatLonsToScreen(
    List<({double latitude, double longitude, int tileWrap})> coordinates,
  ) {
    final worldSize = 512 * math.pow(2, zoom);

    return [
      for (final coordinate in coordinates)
        Offset(
          400 +
              (coordinate.longitude + coordinate.tileWrap * 360 - lon) /
                  360 *
                  worldSize,
          300,
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

Future<CameraPosition> _apply(CameraUpdate update) async {
  final bridge = _FakeBridge();
  final controller = MapLibreMapController.bind(bridge);
  await controller.moveCamera(update);
  final result = controller.cameraPosition!;
  controller.dispose();

  return result;
}

class _WorldBridge extends _FakeBridge {
  @override
  ({double south, double west, double north, double east}) getVisibleRegion() =>
      (south: -80, west: -180, north: 80, east: 180);
}

void main() {
  test('visible whole-world bounds remain whole-world when fitted', () async {
    final bridge = _WorldBridge();
    final controller = MapLibreMapController.bind(bridge);
    addTearDown(controller.dispose);
    final bounds = await controller.getVisibleRegion();
    expect(bounds.contains(const LatLng(0, 0)), isTrue);
    expect(bounds.coversAllLongitudes, isTrue);
    await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds));
    expect(bridge.lastFitWest, -180);
    expect(bridge.lastFitEast, 180);
  });

  test('screen offsets retain every visible wrapped world copy', () {
    final bridge = _FakeBridge()
      ..lat = 0
      ..lon = 180
      ..zoom = 0;
    final controller = MapLibreMapController.bind(bridge);

    expect(controller.toScreenOffsets(const LatLng(0, 0)), <Offset>[
      const Offset(144, 300),
      const Offset(656, 300),
    ]);
    controller.dispose();
  });

  test('camera values serialize like maplibre_gl', () {
    const position = CameraPosition(
      bearing: 20,
      target: LatLng(35, 139),
      tilt: 30,
      zoom: 12,
    );
    expect(position.toMap(), <String, dynamic>{
      'bearing': 20.0,
      'target': <double>[35, 139],
      'tilt': 30.0,
      'zoom': 12.0,
    });

    const bounds = LatLngBounds(
      southwest: LatLng(34, 138),
      northeast: LatLng(36, 140),
    );
    expect(CameraUpdate.newCameraPosition(position).toJson(), <dynamic>[
      'newCameraPosition',
      position.toMap(),
    ]);
    expect(CameraUpdate.newLatLng(const LatLng(1, 2)).toJson(), <dynamic>[
      'newLatLng',
      <double>[1, 2],
    ]);
    expect(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 1,
        top: 2,
        right: 3,
        bottom: 4,
      ).toJson(),
      <dynamic>['newLatLngBounds', bounds.toList(), 1.0, 2.0, 3.0, 4.0],
    );
    expect(
      CameraUpdate.newLatLngZoom(const LatLng(1, 2), 3).toJson(),
      <dynamic>[
        'newLatLngZoom',
        <double>[1, 2],
        3.0,
      ],
    );
    expect(CameraUpdate.scrollBy(4, 5).toJson(), <dynamic>[
      'scrollBy',
      4.0,
      5.0,
    ]);
    expect(CameraUpdate.zoomBy(2).toJson(), <dynamic>['zoomBy', 2.0]);
    expect(CameraUpdate.zoomBy(2, const Offset(10, 20)).toJson(), <dynamic>[
      'zoomBy',
      2.0,
      <double>[10, 20],
    ]);
    expect(CameraUpdate.zoomIn().toJson(), <dynamic>['zoomIn']);
    expect(CameraUpdate.zoomOut().toJson(), <dynamic>['zoomOut']);
    expect(CameraUpdate.zoomTo(8).toJson(), <dynamic>['zoomTo', 8.0]);
    expect(CameraUpdate.bearingTo(90).toJson(), <dynamic>['bearingTo', 90.0]);
    expect(CameraUpdate.tiltTo(45).toJson(), <dynamic>['tiltTo', 45.0]);
  });

  test('style inspection and mutation follow maplibre_gl contracts', () async {
    final bridge = _FakeBridge();
    var styleChangeCount = 0;
    var styleMutationCount = 0;
    final controller = MapLibreMapController.bind(
      bridge,
      onStyleChangeRequested: (styleString, resolvedStyle) async {
        styleChangeCount++;
        expect(resolvedStyle, styleString);
        bridge.setStyle(resolvedStyle);
      },
      onStyleMutationRequested: () => styleMutationCount++,
    );
    const style = '{"version":8,"sources":{},"layers":[]}';

    await controller.setStyle(style);
    expect(styleChangeCount, 1);
    expect(await controller.getStyle(), style);
    expect(await controller.getLayerIds(), <String>['background', 'roads']);
    expect(await controller.getSourceIds(), <String>['composite']);

    await controller.setLayerVisibility('roads', false);
    expect(await controller.getLayerVisibility('roads'), isFalse);
    expect(await controller.getLayerVisibility('missing'), isNull);
    expect(styleMutationCount, 1);

    final filter = <dynamic>[
      'all',
      <dynamic>[
        '==',
        <dynamic>['get', 'kind'],
        'park',
      ],
      <dynamic>[
        '>=',
        <dynamic>['get', 'rank'],
        3,
      ],
    ];
    await controller.setFilter('roads', filter);
    expect(await controller.getFilter('roads'), filter);
    expect(styleMutationCount, 2);
    // The two setters share one native path but not one failure contract:
    // setLayerFilter reports a missing layer, setFilter treats it as an error.
    // Neither repaints when nothing changed.
    expect(await controller.setLayerFilter('missing', '["==",1,1]'), isFalse);
    expect(styleMutationCount, 2);
    await expectLater(
      controller.setFilter('missing', const ['==', 1, 1]),
      throwsStateError,
    );
    expect(styleMutationCount, 2);
    controller.dispose();
  });

  test('style snapshot guard immediately precedes native mutation', () async {
    final bridge = _FakeBridge();
    final events = <String>[];
    bridge.onStyleNativeCall = (operation) {
      events.add('native:$operation');
    };
    final controller = MapLibreMapController.bind(
      bridge,
      beforeStyleMutation: () async => events.add('before'),
      onStyleChangeRequested: (_, resolvedStyle) async {
        bridge.setStyle(resolvedStyle);
      },
      onStyleMutationRequested: () => events.add('after'),
    );
    const style = '{"version":8,"sources":{},"layers":[]}';

    await controller.setStyle(style);
    expect(events, <String>['before', 'native:style']);

    events.clear();
    await controller.setLayerVisibility('roads', false);
    expect(events, <String>['before', 'native:visibility', 'after']);

    events.clear();
    await controller.setFilter('roads', const ['==', 1, 1]);
    expect(events, <String>['before', 'native:filter', 'after']);

    events.clear();
    expect(await controller.setLayerFilter('missing', '["==",1,1]'), isFalse);
    expect(events, <String>['before', 'native:filter']);
    controller.dispose();
  });

  test('style mutation awaits the frame snapshot barrier', () async {
    final bridge = _FakeBridge();
    final barrier = Completer<void>();
    final controller = MapLibreMapController.bind(
      bridge,
      beforeStyleMutation: () => barrier.future,
    );
    final visibilityBefore = bridge.layerVisibility['roads'];

    final mutation = controller.setLayerVisibility('roads', false);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.layerVisibility['roads'], visibilityBefore);

    barrier.complete();
    await mutation;
    expect(bridge.layerVisibility['roads'], isFalse);
    controller.dispose();
  });

  test('style mutation cannot resume through a disposed controller', () async {
    final bridge = _FakeBridge();
    final barrier = Completer<void>();
    final controller = MapLibreMapController.bind(
      bridge,
      beforeStyleMutation: () => barrier.future,
    );
    final visibilityBefore = bridge.layerVisibility['roads'];

    final mutation = controller.setLayerVisibility('roads', false);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    barrier.complete();

    await expectLater(mutation, throwsStateError);
    expect(bridge.layerVisibility['roads'], visibilityBefore);
  });

  test('placed labels prefer the widget-owned snapshot provider', () {
    final bridge = _FakeBridge();
    final cached = <LabelData>[];
    final controller = MapLibreMapController.bind(
      bridge,
      placedLabelsProvider: () => cached,
    );
    final callsBefore = bridge.callCount;

    expect(controller.getPlacedLabels(), same(cached));
    expect(bridge.callCount, callsBefore);
    controller.dispose();
  });

  test('camera partial updates preserve valid zero values', () async {
    expect(
      await _apply(CameraUpdate.zoomTo(0)),
      const CameraPosition(
        bearing: 15,
        target: LatLng(35, 139),
        tilt: 30,
        zoom: 0,
      ),
    );
    expect(
      await _apply(CameraUpdate.newLatLng(const LatLng(0, 0))),
      const CameraPosition(
        bearing: 15,
        target: LatLng(0, 0),
        tilt: 30,
        zoom: 12,
      ),
    );
    expect(
      await _apply(CameraUpdate.newLatLngZoom(const LatLng(0, 0), 0)),
      const CameraPosition(
        bearing: 15,
        target: LatLng(0, 0),
        tilt: 30,
        zoom: 0,
      ),
    );
    expect(
      await _apply(
        CameraUpdate.newCameraPosition(
          const CameraPosition(target: LatLng(0, 0), zoom: 0),
        ),
      ),
      const CameraPosition(target: LatLng(0, 0), zoom: 0),
    );
  });

  test('controller preserves and updates bearing and tilt', () async {
    final bridge = _FakeBridge();
    final controller = MapLibreMapController.bind(bridge);

    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(
          bearing: 90,
          target: LatLng(36, 140),
          tilt: 45,
          zoom: 14,
        ),
      ),
    );

    expect(
      controller.cameraPosition,
      const CameraPosition(
        bearing: 90,
        target: LatLng(36, 140),
        tilt: 45,
        zoom: 14,
      ),
    );
    expect(
      await controller.toLatLng(const math.Point<double>(140, 36)),
      const LatLng(36, 140),
    );
    bridge.cameraSnapshotCallCount = 0;
    await controller.queryCameraPosition();
    expect(bridge.cameraSnapshotCallCount, 1);
    controller.dispose();
  });

  test('relative camera updates dispatch and query compatibly', () async {
    final bridge = _FakeBridge();
    final controller = MapLibreMapController.bind(bridge);

    expect(await controller.moveCamera(CameraUpdate.scrollBy(4, 5)), isTrue);
    expect(bridge.lastMoveDx, 4);
    expect(bridge.lastMoveDy, 5);

    expect(
      await controller.moveCamera(CameraUpdate.zoomBy(2, const Offset(10, 20))),
      isTrue,
    );
    expect(bridge.lastZoomAmount, 2);
    expect(bridge.lastZoomFocus, const Offset(10, 20));
    expect((await controller.queryCameraPosition())!.zoom, 14);

    expect(
      await controller.toScreenLocation(const LatLng(35, 139)),
      const math.Point<double>(0, 0),
    );
    expect(
      await controller.toScreenLocationBatch(const [
        LatLng(35, 139),
        LatLng(36, 140),
      ]),
      const [math.Point<double>(0, 0), math.Point<double>(0, 0)],
    );
    expect(
      await controller.getVisibleRegion(),
      const LatLngBounds(
        southwest: LatLng(34, 138),
        northeast: LatLng(36, 140),
      ),
    );
    expect(await controller.getMetersPerPixelAtLatitude(35), 70);
    controller.dispose();
  });

  test('content insets keep each edge on its own axis', () async {
    // The controller unpacks EdgeInsets into four named arguments, so a
    // transposed pair would shift the camera's focal point in a way that
    // still renders a plausible map.
    final bridge = _FakeBridge();
    final controller = MapLibreMapController.bind(bridge);

    await controller.updateContentInsets(const EdgeInsets.fromLTRB(1, 2, 3, 4));

    expect(bridge.lastContentInsets, const EdgeInsets.fromLTRB(1, 2, 3, 4));
    expect(bridge.lastContentInsetsAnimated, isFalse);
    controller.dispose();
  });

  test('content insets only await a transition when animated', () async {
    final bridge = _FakeBridge();
    final controller = MapLibreMapController.bind(bridge);

    // Unanimated: applied immediately, nothing to wait for.
    var completed = false;
    unawaited(
      controller
          .updateContentInsets(const EdgeInsets.all(8))
          .then((_) => completed = true),
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isTrue);
    expect(bridge.lastContentInsetsAnimated, isFalse);

    await controller.updateContentInsets(const EdgeInsets.all(8), true);
    expect(bridge.lastContentInsetsAnimated, isTrue);
    expect(bridge.lastContentInsetsDuration, const Duration(milliseconds: 300));

    await controller.updateContentInsets(
      const EdgeInsets.all(8),
      true,
      const Duration(milliseconds: 10),
    );
    expect(bridge.lastContentInsetsDuration, const Duration(milliseconds: 10));
    controller.dispose();
  });

  test('bounds and easing preserve maplibre_gl camera contracts', () async {
    final bridge = _FakeBridge();
    final controller = MapLibreMapController.bind(bridge);
    const bounds = LatLngBounds(
      southwest: LatLng(34, 138),
      northeast: LatLng(36, 140),
    );

    expect(
      await controller.moveCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          left: 1,
          top: 2,
          right: 3,
          bottom: 4,
        ),
      ),
      isTrue,
    );
    expect(controller.cameraPosition!.target, const LatLng(35, 139));
    expect(controller.cameraPosition!.bearing, 0);
    expect(controller.cameraPosition!.tilt, 0);
    expect(bridge.lastFitFlight, isFalse);

    expect(
      await controller.easeCamera(
        CameraUpdate.bearingTo(180),
        duration: Duration.zero,
        interpolation: CameraAnimationInterpolation.linear,
      ),
      isTrue,
    );
    expect(controller.cameraPosition!.bearing, 180);

    await controller.setCameraBounds(
      west: 138,
      north: 36,
      south: 34,
      east: 140,
      padding: 8,
    );
    expect(bridge.lastDuration, const Duration(milliseconds: 200));
    await controller.setCameraBounds(
      west: 138,
      north: 36,
      south: 34,
      east: 140,
      padding: 8,
      duration: const Duration(milliseconds: 25),
    );
    expect(bridge.lastDuration, const Duration(milliseconds: 25));
    expect(bridge.lastFitFlight, isTrue);
    controller.dispose();
  });

  test('a newer camera update cancels the active animation future', () async {
    final bridge = _FakeBridge();
    final controller = MapLibreMapController.bind(bridge);

    final animation = controller.animateCamera(
      CameraUpdate.zoomTo(15),
      duration: const Duration(milliseconds: 50),
    );
    expect(bridge.lastDuration, const Duration(milliseconds: 50));
    expect(bridge.usedFlight, isTrue);

    expect(await controller.moveCamera(CameraUpdate.zoomTo(10)), isTrue);
    expect(await animation, isFalse);
    expect(controller.cameraPosition!.zoom, 10);
    controller.dispose();
  });

  test('a camera gesture cancels the active native transition', () async {
    final bridge = _FakeBridge();
    final controller = MapLibreMapController.bind(bridge);

    final animation = controller.animateCamera(
      CameraUpdate.zoomTo(15),
      duration: const Duration(milliseconds: 50),
    );
    controller.notifyCameraGestureStarted();

    expect(bridge.cancelCount, 1);
    expect(await animation, isFalse);
    controller.dispose();
  });

  test(
    'programmatic camera callback renders before one listener update',
    () async {
      final bridge = _FakeBridge();
      late MapLibreMapController controller;
      var callbackCount = 0;
      var listenerCount = 0;
      controller = MapLibreMapController.bind(
        bridge,
        onCameraChangeRequested: () {
          callbackCount++;
          controller.notifyCameraChanged();
        },
      )..addListener(() => listenerCount++);

      await controller.moveCamera(CameraUpdate.zoomTo(0));

      expect(callbackCount, 1);
      expect(listenerCount, 1);
      expect(controller.cameraPosition!.zoom, 0);
      controller.dispose();
    },
  );

  test('unchanged native frames do not repeat camera notifications', () {
    final bridge = _FakeBridge();
    final controller = MapLibreMapController.bind(bridge);
    var listenerCount = 0;
    controller.addListener(() => listenerCount++);

    expect(controller.notifyCameraChanged(), isFalse);
    expect(listenerCount, 0);

    bridge.lat = 36;
    expect(controller.notifyCameraChanged(), isTrue);
    expect(listenerCount, 1);
    expect(controller.cameraPosition!.target.latitude, 36);

    expect(controller.notifyCameraChanged(), isFalse);
    expect(listenerCount, 1);

    bridge.zoom = 14;
    expect(controller.notifyCameraChanged(notifyListeners: false), isTrue);
    expect(controller.cameraPosition!.zoom, 14);
    expect(listenerCount, 1);
    controller.dispose();
  });

  test(
    'disposed controller rejects public API without bridge or render callbacks',
    () async {
      final bridge = _FakeBridge();
      var callbackCount = 0;
      final controller = MapLibreMapController.bind(
        bridge,
        onCameraChangeRequested: () => callbackCount++,
      );
      final bridgeCallsBeforeDispose = bridge.callCount;

      controller.dispose();
      controller.dispose();

      expect(() => controller.cameraPosition, throwsStateError);
      await expectLater(
        controller.moveCamera(CameraUpdate.zoomTo(10)),
        throwsStateError,
      );
      await expectLater(
        controller.animateCamera(CameraUpdate.zoomTo(10)),
        throwsStateError,
      );
      await expectLater(
        controller.setStyle('{"version":8,"sources":{},"layers":[]}'),
        throwsStateError,
      );
      await expectLater(controller.getStyle(), throwsStateError);
      await expectLater(controller.getLayerIds(), throwsStateError);
      await expectLater(controller.getSourceIds(), throwsStateError);
      await expectLater(
        controller.setLayerVisibility('roads', false),
        throwsStateError,
      );
      await expectLater(
        controller.getLayerVisibility('roads'),
        throwsStateError,
      );
      await expectLater(
        controller.setFilter('roads', const ['==', 1, 1]),
        throwsStateError,
      );
      await expectLater(controller.getFilter('roads'), throwsStateError);
      await expectLater(
        controller.toScreenLocation(const LatLng(35, 139)),
        throwsStateError,
      );
      expect(controller.getPlacedLabels, throwsStateError);
      expect(() => controller.isMapIdle, throwsStateError);
      expect(() => controller.bridge, throwsStateError);
      expect(controller.notifyCameraChanged, throwsStateError);

      expect(bridge.callCount, bridgeCallsBeforeDispose);
      expect(callbackCount, 0);
    },
  );
}

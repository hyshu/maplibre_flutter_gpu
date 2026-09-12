import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/controller_fixtures.dart';

Future<CameraPosition> _apply(CameraUpdate update) async {
  final bridge = FakeControllerBridge();
  final controller = MapLibreMapController.bind(bridge);
  await controller.moveCamera(update);
  final result = controller.cameraPosition!;
  controller.dispose();

  return result;
}

class _WorldBridge extends FakeControllerBridge {
  @override
  ({double south, double west, double north, double east}) getVisibleRegion() =>
      (south: -80, west: -180, north: 80, east: 180);
}

void main() {
  test('screen offsets retain every visible wrapped world copy', () {
    final bridge = FakeControllerBridge()
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

  test('placed labels prefer the widget-owned snapshot provider', () {
    final bridge = FakeControllerBridge();
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
    final bridge = FakeControllerBridge();
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
    final bridge = FakeControllerBridge();
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
    final bridge = FakeControllerBridge();
    final controller = MapLibreMapController.bind(bridge);

    await controller.updateContentInsets(const EdgeInsets.fromLTRB(1, 2, 3, 4));

    expect(bridge.lastContentInsets, const EdgeInsets.fromLTRB(1, 2, 3, 4));
    expect(bridge.lastContentInsetsAnimated, isFalse);
    controller.dispose();
  });

  test('content insets only await a transition when animated', () async {
    final bridge = FakeControllerBridge();
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
    final bridge = FakeControllerBridge();
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
    final bridge = FakeControllerBridge();
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
    final bridge = FakeControllerBridge();
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
      final bridge = FakeControllerBridge();
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

  test('viewport changes reproject overlays with an unchanged camera', () {
    final bridge = FakeControllerBridge();
    final controller = MapLibreMapController.bind(bridge);
    final camera = controller.cameraPosition;
    final location = camera!.target;
    var offsets = controller.toScreenOffsets(location);
    var listenerCount = 0;
    controller.addListener(() {
      listenerCount++;
      offsets = controller.toScreenOffsets(location);
    });
    expect(offsets, [const Offset(400, 300)]);

    bridge.logicalWidth = 1000;
    bridge.logicalHeight = 800;
    expect(controller.notifyCameraChanged(viewportChanged: true), isFalse);
    expect(controller.cameraPosition, camera);
    expect(offsets, [const Offset(500, 400)]);
    expect(listenerCount, 1);

    expect(controller.notifyCameraChanged(), isFalse);
    expect(listenerCount, 1);

    bridge.logicalWidth = 600;
    expect(
      controller.notifyCameraChanged(
        viewportChanged: true,
        notifyListeners: false,
      ),
      isFalse,
    );
    expect(listenerCount, 1);
    controller.dispose();
  });

  test('unchanged native frames do not repeat camera notifications', () {
    final bridge = FakeControllerBridge();
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
      final bridge = FakeControllerBridge();
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
}

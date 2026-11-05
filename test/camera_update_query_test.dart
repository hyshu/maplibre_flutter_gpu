import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/controller_fixtures.dart';
import 'support/source_files.dart';

/// Checks the fake camera against the fixture's initial values by default.
void _expectCamera(
  FakeControllerBridge bridge, {
  double lat = 35,
  double lon = 139,
  double zoom = 12,
  double bearing = 15,
  double pitch = 30,
}) {
  expect(bridge.lat, lat);
  expect(bridge.lon, lon);
  expect(bridge.zoom, zoom);
  expect(bridge.bearing, bearing);
  expect(bridge.pitch, pitch);
}

void main() {
  const position = CameraPosition(
    target: LatLng(36, 140),
    zoom: 16,
    bearing: 80,
    tilt: 45,
  );
  final updates = {
    'full position': (
      update: CameraUpdate.newCameraPosition(position),
      verify: (FakeControllerBridge bridge) {
        expect(bridge.lat, 36);
        expect(bridge.lon, 140);
        expect(bridge.zoom, 16);
        expect(bridge.bearing, 80);
        expect(bridge.pitch, 45);
      },
    ),
    'bounds': (
      update: CameraUpdate.newLatLngBounds(
        const LatLngBounds(
          southwest: LatLng(34, 138),
          northeast: LatLng(36, 140),
        ),
      ),
      verify: (FakeControllerBridge bridge) {
        expect(bridge.lastFitWest, 138);
        expect(bridge.lastFitEast, 140);
      },
    ),
    'scroll': (
      update: CameraUpdate.scrollBy(4, 5),
      verify: (FakeControllerBridge bridge) {
        expect(bridge.lastMoveDx, 4);
        expect(bridge.lastMoveDy, 5);
      },
    ),
    'zoom delta': (
      update: CameraUpdate.zoomBy(2, const Offset(10, 20)),
      verify: (FakeControllerBridge bridge) {
        expect(bridge.lastZoomAmount, 2);
        expect(bridge.lastZoomFocus, const Offset(10, 20));
        expect(bridge.zoom, 14);
      },
    ),
    'target': (
      update: CameraUpdate.newLatLng(const LatLng(36, 140)),
      verify: (FakeControllerBridge bridge) =>
          _expectCamera(bridge, lat: 36, lon: 140),
    ),
    'target and zoom': (
      update: CameraUpdate.newLatLngZoom(const LatLng(36, 140), 16),
      verify: (FakeControllerBridge bridge) =>
          _expectCamera(bridge, lat: 36, lon: 140, zoom: 16),
    ),
    'zoom': (
      update: CameraUpdate.zoomTo(16),
      verify: (FakeControllerBridge bridge) => _expectCamera(bridge, zoom: 16),
    ),
    'bearing': (
      update: CameraUpdate.bearingTo(80),
      verify: (FakeControllerBridge bridge) =>
          _expectCamera(bridge, bearing: 80),
    ),
    'tilt': (
      update: CameraUpdate.tiltTo(45),
      verify: (FakeControllerBridge bridge) => _expectCamera(bridge, pitch: 45),
    ),
  };
  final methods =
      <
        String,
        Future<bool?> Function(
          MapLibreMapController controller,
          CameraUpdate update,
        )
      >{
        'move': (controller, update) => controller.moveCamera(update),
        'animate': (controller, update) =>
            controller.animateCamera(update, duration: Duration.zero),
        'ease': (controller, update) =>
            controller.easeCamera(update, duration: Duration.zero),
      };

  for (final method in methods.entries) {
    for (final update in updates.entries) {
      test(
        '${method.key} ${update.key} avoids a camera preflight read',
        () async {
          final bridge = FakeControllerBridge();
          var requests = 0;
          final controller = MapLibreMapController.bind(
            bridge,
            onCameraChangeRequested: () => requests++,
          );
          addTearDown(controller.dispose);
          final previousFrameCamera = controller.cameraPosition;
          bridge.cameraSnapshotCallCount = 0;

          expect(await method.value(controller, update.value.update), isTrue);
          expect(bridge.cameraSnapshotCallCount, 0);
          expect(requests, 1);
          expect(controller.cameraPosition, same(previousFrameCamera));
          update.value.verify(bridge);
        },
      );
    }
  }

  test('partial updates reach native without a live camera read', () {
    final controller = SourceFiles.controller;
    final apply = controller.substring(
      controller.indexOf('bool _applyCameraUpdate('),
      controller.indexOf('void _cameraChanged()'),
    );
    expect(apply, isNot(contains('_readCameraFromBridge()')));
    expect(apply, contains('_bridge.applyPartialCamera('));
    final ffi = SourceFiles.ffi;
    expect(ffi, contains("'partial camera updates'"));
    expect(ffi, contains("'maplibre_camera_apply_partial'"));
  });
}

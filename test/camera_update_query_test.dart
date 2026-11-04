import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/controller_fixtures.dart';

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
}

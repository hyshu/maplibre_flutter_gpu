import 'dart:async' show Completer;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/controller_fixtures.dart';

void main() {
  const camera = CameraPosition(
    target: LatLng(36, 140),
    zoom: 1,
    bearing: 80,
    tilt: 45,
  );
  final deltas = {
    'in': (update: CameraUpdate.zoomIn(), amount: 1.0),
    'out': (update: CameraUpdate.zoomOut(), amount: -1.0),
    'by': (update: CameraUpdate.zoomBy(0.5), amount: 0.5),
  };
  for (final entry in deltas.entries) {
    test(
      'zoom ${entry.key} resolves its delta without an absolute position',
      () {
        final resolved = entry.value.update.resolveAgainst(camera);

        expect(
          resolved,
          CameraPosition(
            target: camera.target,
            zoom: camera.zoom + entry.value.amount,
            bearing: camera.bearing,
            tilt: camera.tilt,
          ),
        );
      },
    );
  }

  test(
    'queued zoom steps compose with earlier moves before frame adoption',
    () async {
      final bridge = FakeControllerBridge();
      final barrier = Completer<void>();
      final appliedZooms = <double>[];
      final controller = MapLibreMapController.bind(
        bridge,
        beforeCameraMutation: () => barrier.future,
        onCameraChangeRequested: () => appliedZooms.add(bridge.zoom),
      );
      addTearDown(controller.dispose);
      bridge.cameraSnapshotCallCount = 0;
      final moves = [
        controller.moveCamera(CameraUpdate.zoomTo(17)),
        controller.moveCamera(CameraUpdate.zoomIn()),
        controller.moveCamera(CameraUpdate.zoomOut()),
        controller.moveCamera(CameraUpdate.zoomOut()),
      ];

      expect(appliedZooms, isEmpty);
      barrier.complete();
      expect(await Future.wait(moves), everyElement(isTrue));
      expect(appliedZooms, [17, 18, 17, 16]);
      expect(bridge.lat, 35);
      expect(bridge.lon, 139);
      expect(bridge.bearing, 15);
      expect(bridge.pitch, 30);
      expect(bridge.cameraSnapshotCallCount, 1);
      expect(bridge.lastZoomFocus, isNull);
      expect(controller.cameraPosition!.zoom, 12);
    },
  );

  for (final method in ['animate', 'ease']) {
    for (final entry in deltas.entries.where((entry) => entry.key != 'by')) {
      test('$method zoom ${entry.key} uses native relative scaling', () async {
        final bridge = FakeControllerBridge();
        final controller = MapLibreMapController.bind(
          bridge,
          onCameraChangeRequested: () {},
        );
        addTearDown(controller.dispose);
        const duration = Duration(milliseconds: 1);
        final accepted = method == 'animate'
            ? await controller.animateCamera(
                entry.value.update,
                duration: duration,
              )
            : await controller.easeCamera(
                entry.value.update,
                duration: duration,
                interpolation: CameraAnimationInterpolation.linear,
              );

        expect(accepted, isTrue);
        expect(bridge.lastZoomAmount, entry.value.amount);
        expect(bridge.lastZoomFocus, isNull);
        expect(bridge.lastDuration, duration);
        expect(bridge.lastEasing, method == 'ease' ? 0 : -1);
        expect(bridge.zoom, 12 + entry.value.amount);
        expect(bridge.usedFlight, isFalse);
      });
    }
  }
}

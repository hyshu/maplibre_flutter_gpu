import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/state/gesture/gesture_coordinator.dart';

import 'support/controller_fixtures.dart';

class _Bridge extends FakeControllerBridge {
  bool moving = false;

  @override
  void scaleBy(double scale, double cx, double cy) {}

  @override
  bool animateCameraFull({
    required double latitude,
    required double longitude,
    required double zoom,
    required double bearing,
    required double pitch,
    required Duration duration,
  }) {
    moving = true;

    return true;
  }

  @override
  bool isCameraMoving() => moving;
}

class _Host implements MapGestureHost {
  final bridge = _Bridge();
  final idleDuringMovement = <bool>[];
  var renderCalls = 0;

  @override
  _Bridge get gestureBridge => bridge;

  @override
  MapGestureSettings get gestureSettings => (
    scrollEnabled: true,
    zoomEnabled: true,
    rotateEnabled: true,
    tiltEnabled: true,
    doubleClickZoomEnabled: null,
  );

  @override
  MapGestureOptions get gestureOptions => const MapGestureOptions();

  @override
  Size get logicalMapSize => const Size(400, 300);

  @override
  void beginCameraGesture() {}

  @override
  void endCameraGesture() => idleDuringMovement.add(bridge.isCameraMoving());

  @override
  void renderGesture() => renderCalls++;

  @override
  void scheduleRepaint() {}
}

void main() {
  testWidgets('wheel takeover does not emit idle during new camera animation', (
    tester,
  ) async {
    final host = _Host();
    final coordinator = MapGestureCoordinator(
      vsync: const TestVSync(),
      host: host,
    );
    final controller = MapLibreMapController.bind(
      host.bridge,
      onCameraChangeRequested: coordinator.stopFling,
    );
    addTearDown(controller.dispose);
    addTearDown(coordinator.dispose);
    coordinator.onPointerSignal(
      const PointerScrollEvent(scrollDelta: Offset(0, 1)),
    );
    final animation = controller.animateCamera(CameraUpdate.zoomTo(14));
    await tester.pump();
    expect(host.bridge.moving, isTrue);
    expect(host.idleDuringMovement, isEmpty);
    expect(host.renderCalls, 0);
    await tester.pump(const Duration(milliseconds: 160));
    expect(host.idleDuringMovement, isEmpty);
    expect(host.renderCalls, 0);

    host.bridge.moving = false;
    await tester.pump(const Duration(milliseconds: 16));
    expect(await animation, isTrue);
    coordinator.onPointerSignal(
      const PointerScrollEvent(scrollDelta: Offset(0, 1)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(host.idleDuringMovement, [false]);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

import 'package:visual_e2e_gpu/main.dart' as app;

const _animationDuration = Duration(milliseconds: 500);
const _warmUpRoundTrips = 2;
const _measuredRoundTrips = 10;

const _cameraA = CameraPosition(
  target: LatLng(35.6812, 139.7671),
  zoom: 13.25,
  bearing: 17,
  tilt: 28,
);

const _cameraB = CameraPosition(
  target: LatLng(35.6830, 139.7695),
  zoom: 13.75,
  bearing: 32,
  tilt: 34,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile geometry camera rendering', (tester) async {
    expect(
      kProfileMode,
      isTrue,
      reason: 'Run this benchmark with flutter drive --profile',
    );
    expect(
      visualE2eSceneId,
      'geometry',
      reason: 'The camera path is calibrated for the geometry scene',
    );

    await app.main();
    await tester.pump();

    try {
      await _waitForMapIdle(tester);
      final controller = await app.visualE2eController;

      await _runCameraRoundTrips(
        tester,
        controller,
        roundTrips: _warmUpRoundTrips,
      );

      await binding.watchPerformance(
        () => _runCameraRoundTrips(
          tester,
          controller,
          roundTrips: _measuredRoundTrips,
        ),
        reportKey: 'geometry_camera',
      );

      binding.reportData!['benchmark'] = <String, Object>{
        'scene': visualE2eSceneId,
        'animation_duration_millis': _animationDuration.inMilliseconds,
        'warm_up_round_trips': _warmUpRoundTrips,
        'measured_round_trips': _measuredRoundTrips,
      };
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await stopVisualE2eAssetServer();
    }
  });
}

Future<void> _runCameraRoundTrips(
  WidgetTester tester,
  MapLibreMapController controller, {
  required int roundTrips,
}) async {
  for (var index = 0; index < roundTrips; index += 1) {
    await _animateTo(tester, controller, _cameraB);
    await _animateTo(tester, controller, _cameraA);
  }
}

Future<void> _animateTo(
  WidgetTester tester,
  MapLibreMapController controller,
  CameraPosition camera,
) async {
  final start = await controller.queryCameraPosition() ?? camera;
  const steps = 30;
  final stepDelay = Duration(
    microseconds: _animationDuration.inMicroseconds ~/ steps,
  );
  for (var step = 1; step <= steps; step += 1) {
    final t = step / steps;
    final completed = await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            start.target.latitude +
                (camera.target.latitude - start.target.latitude) * t,
            start.target.longitude +
                (camera.target.longitude - start.target.longitude) * t,
          ),
          zoom: start.zoom + (camera.zoom - start.zoom) * t,
          bearing: start.bearing + (camera.bearing - start.bearing) * t,
          tilt: start.tilt + (camera.tilt - start.tilt) * t,
        ),
      ),
    );
    expect(completed, isTrue, reason: 'Camera step did not complete');
    await tester.pump(stepDelay);
  }
}

Future<void> _waitForMapIdle(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!VisualTestStatus.ready.value) {
    if (DateTime.now().isAfter(deadline)) {
      fail('maplibre_flutter_gpu did not become idle within 60 seconds');
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

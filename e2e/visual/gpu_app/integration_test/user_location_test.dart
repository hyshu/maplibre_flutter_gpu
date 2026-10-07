import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/state/user_location_projection.dart';

import '../../../../tool/user_location/scenarios.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('capture GPU user location against native inputs', (
    tester,
  ) async {
    addTearDown(() async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    var scene = userLocationScenarios.first;
    late StateSetter rebuild;
    MapLibreMapController? controller;
    MapUserLocationRenderState? markerState;
    var loaded = false;
    var builderEnabled = true;
    var builderReturnsNull = false;
    const viewportKey = ValueKey('gpu-location-viewport');
    final captures = <Object>[];
    CameraPosition camera() => CameraPosition(
      target: LatLng(scene['latitude'] as double, scene['longitude'] as double),
      zoom: scene['zoom'] as double,
      bearing: scene['bearing'] as double,
      tilt: scene['pitch'] as double,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            final visible = scene['visible'] as bool? ?? true;

            return Center(
              child: SizedBox(
                key: viewportKey,
                width: scene['width'] as double? ?? 320,
                height: scene['height'] as double? ?? 320,
                child: MapLibreMap(
                  styleString: userLocationStyle,
                  cameraPosition: camera(),
                  cameraConstrainMode: CameraConstrainMode.none,
                  compassEnabled: false,
                  logoEnabled: false,
                  attributionButtonEnabled: false,
                  loadingBuilder: null,
                  userLocation: visible
                      ? MapUserLocation(
                          position: LatLng(
                            scene['locationLatitude'] as double,
                            scene['locationLongitude'] as double,
                          ),
                          headingDegrees: scene['heading'] as double?,
                          accuracyMeters: scene['accuracy'] as double,
                        )
                      : null,
                  userLocationBuilder: builderEnabled
                      ? (context, state) {
                          markerState = state;
                          if (builderReturnsNull) return null;

                          return MapUserLocationMarker(state: state);
                        }
                      : null,
                  onMapCreated: (value) => controller = value,
                  onStyleLoadedCallback: () => loaded = true,
                ),
              ),
            );
          },
        ),
      ),
    );
    for (final next in userLocationScenarios) {
      rebuild(() {
        scene = next;
        markerState = null;
      });
      final visible = scene['visible'] as bool? ?? true;
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      var ready = false;
      while (!ready && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        final frame = controller?.frameState;
        final expected = camera();
        ready =
            loaded &&
            frame != null &&
            (frame.camera.target.latitude - expected.target.latitude).abs() <
                0.000001 &&
            (frame.camera.target.longitude - expected.target.longitude).abs() <
                0.000001 &&
            (frame.camera.zoom - expected.zoom).abs() < 0.000001 &&
            (frame.camera.bearing - expected.bearing).abs() < 0.000001 &&
            (frame.camera.tilt - expected.tilt).abs() < 0.000001 &&
            frame.logicalSize ==
                Size(
                  scene['width'] as double? ?? 320,
                  scene['height'] as double? ?? 320,
                ) &&
            (!visible ||
                (markerState?.frame.sequence == frame.sequence &&
                    markerState?.location.position.latitude ==
                        scene['locationLatitude']));
      }
      expect(
        ready,
        isTrue,
        reason: '$scene ${controller?.frameState} $markerState',
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byType(MapUserLocationMarker),
        visible ? findsOneWidget : findsNothing,
      );
      final viewport = tester.getRect(find.byKey(viewportKey));
      final projected = await controller!.toScreenLocation(
        LatLng(
          scene['locationLatitude'] as double,
          scene['locationLongitude'] as double,
        ),
      );
      final state = markerState;
      captures.add({
        'scene': scene,
        'gpu': {
          'position': [projected.x, projected.y],
          'markerPosition': state == null
              ? null
              : [state.screenPosition.dx, state.screenPosition.dy],
          'headingRadians': state?.headingRadians,
          'accuracyPolygon': state?.accuracyPolygon
              .map((point) => [point.dx, point.dy])
              .toList(),
          'frameSequence': controller!.frameState!.sequence,
          'visible': visible,
        },
        'viewport': [
          viewport.left,
          viewport.top,
          viewport.width,
          viewport.height,
        ],
        'dpr': tester.view.devicePixelRatio,
      });
      await binding.takeScreenshot('gpu-${scene['id']}');
    }
    rebuild(() => builderEnabled = false);
    await tester.pump();
    expect(find.byType(MapUserLocationMarker), findsNothing);
    rebuild(() {
      builderEnabled = true;
      builderReturnsNull = true;
    });
    await tester.pump();
    expect(find.byType(MapUserLocationMarker), findsNothing);
    rebuild(() => builderReturnsNull = false);
    await tester.pump();
    expect(find.byType(MapUserLocationMarker), findsOneWidget);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final pausedFrame = controller!.frameState;
    rebuild(() {
      scene = {...scene, 'visible': false};
    });
    var pendingPump = tester.pump();
    binding.scheduleForcedFrame();
    await pendingPump;
    expect(find.byType(MapUserLocationMarker), findsNothing);
    for (final latitude in [0.008, 0.012]) {
      rebuild(() {
        scene = {
          ...scene,
          'visible': true,
          'locationLatitude': latitude,
          'width': 319.5,
          'height': 281.25,
        };
        markerState = null;
      });
      pendingPump = tester.pump();
      binding.scheduleForcedFrame();
      await pendingPump;
    }
    expect(controller!.frameState, same(pausedFrame));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final resumeDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(resumeDeadline) &&
        (markerState?.location.position.latitude != 0.012 ||
            markerState?.frame.logicalSize != const Size(319, 281))) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(markerState?.location.position.latitude, 0.012);
    expect(markerState?.frame.logicalSize, const Size(319, 281));
    expect(markerState?.viewportSize, const Size(319.5, 281.25));
    expect(markerState!.screenPosition.dx, inInclusiveRange(0, 319.5));
    expect(markerState!.screenPosition.dy, inInclusiveRange(0, 281.25));
    expect(find.byType(MapUserLocationMarker), findsOneWidget);
    final savedFrame = controller!.frameState!;
    final savedTransform = controller!.bridge.frameGetMapTransform();
    expect(savedTransform, isNotNull);
    final savedLocation = markerState!.location;
    final baseline = controller!.bridge.latLonToScreen(
      savedLocation.position.latitude,
      savedLocation.position.longitude,
    );
    double? frozenProjectionError;
    try {
      controller!.bridge.setCameraFull(3, -177, 6, 40, 25);
      final liveProjection = controller!.bridge.latLonToScreen(
        savedLocation.position.latitude,
        savedLocation.position.longitude,
      );
      expect((liveProjection - baseline).distance, greaterThan(30));
      final frozen = UserLocationProjection.capture(
        location: savedLocation,
        frame: savedFrame,
        transform: savedTransform!,
      );
      expect(frozen, isNotNull);
      frozenProjectionError = (frozen!.position - baseline).distance;
      expect(frozenProjectionError, lessThan(0.1));
    } finally {
      final camera = savedFrame.camera;
      controller!.bridge.setCameraFull(
        camera.target.latitude,
        camera.target.longitude,
        camera.zoom,
        camera.bearing,
        camera.tilt,
      );
    }
    binding.reportData = {
      ...?binding.reportData,
      'implementation': 'maplibre_flutter_gpu',
      'captures': captures,
      'frozenProjectionErrorLogicalPixels': frozenProjectionError,
    };
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: !Platform.isIOS);
}

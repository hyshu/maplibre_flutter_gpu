import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

const _style =
    '{"version":8,"sources":{},"layers":['
    '{"id":"background","type":"background",'
    '"paint":{"background-color":"#eeeeee"}}]}';

Offset _mercator(LatLng position, double zoom) {
  final worldSize = 512 * math.pow(2, zoom);
  final sinLatitude = math.sin(position.latitude * math.pi / 180);

  return Offset(
    (position.longitude + 180) / 360 * worldSize,
    (0.5 - math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
        worldSize,
  );
}

Offset _expectedPosition(MapUserLocationRenderState state) {
  final frame = state.frame;
  final delta =
      _mercator(state.location.position, frame.camera.zoom) -
      _mercator(frame.camera.target, frame.camera.zoom);
  final projected = frame.logicalSize.center(Offset.zero) + delta;

  return Offset(
    projected.dx * state.viewportSize.width / frame.logicalSize.width,
    projected.dy * state.viewportSize.height / frame.logicalSize.height,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('location follows rendered frames during native animation', (
    tester,
  ) async {
    Future<void> pump(Duration duration) async {
      // Keep rendering active when the desktop test window is not focused.
      if (binding.lifecycleState != AppLifecycleState.resumed) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await tester.pump(duration);
    }

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    const location = LatLng(35.6814, 139.7667);
    const viewportKey = ValueKey('animated-location-viewport');
    const markerKey = ValueKey('animated-location-marker');
    MapLibreMapController? controller;
    MapUserLocationRenderState? markerState;
    var loaded = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            key: viewportKey,
            width: 320,
            height: 280,
            child: MapLibreMap(
              styleString: _style,
              initialCameraPosition: const CameraPosition(
                target: location,
                zoom: 15,
              ),
              cameraConstrainMode: CameraConstrainMode.none,
              compassEnabled: false,
              logoEnabled: false,
              attributionButtonEnabled: false,
              loadingBuilder: null,
              userLocation: MapUserLocation(position: location),
              userLocationBuilder: (context, state) {
                markerState = state;

                return const IgnorePointer(
                  child: SizedBox.square(
                    key: markerKey,
                    dimension: 16,
                    child: ColoredBox(color: Color(0xff1565c0)),
                  ),
                );
              },
              onMapCreated: (value) => controller = value,
              onStyleLoadedCallback: () => loaded = true,
            ),
          ),
        ),
      ),
    );
    final loadDeadline = DateTime.now().add(const Duration(seconds: 30));
    while ((!loaded || markerState == null) &&
        DateTime.now().isBefore(loadDeadline)) {
      await pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    expect(loaded, isTrue);
    expect(markerState, isNotNull);
    expect(controller, isNotNull);
    expect(find.byKey(markerKey), findsOneWidget);

    var maxProjectionError = 0.0;
    var maxWidgetError = 0.0;
    var maxLiveProjectionDivergence = 0.0;
    final samples = <Map<String, Object>>[];
    final sampledSequences = <int>{};
    void sample() {
      final state = markerState!;
      final camera = state.frame.camera;
      expect(camera.zoom, closeTo(15, 0.000001));
      expect(camera.bearing, closeTo(0, 0.000001));
      expect(camera.tilt, closeTo(0, 0.000001));
      final expected = _expectedPosition(state);
      final projectionError = (state.screenPosition - expected).distance;
      final actualCenter =
          tester.getCenter(find.byKey(markerKey)) -
          tester.getTopLeft(find.byKey(viewportKey));
      final widgetError = (actualCenter - expected).distance;
      final livePosition = controller!.toScreenOffset(location);
      final liveDivergence = (livePosition - expected).distance;
      maxProjectionError = math.max(maxProjectionError, projectionError);
      maxWidgetError = math.max(maxWidgetError, widgetError);
      maxLiveProjectionDivergence = math.max(
        maxLiveProjectionDivergence,
        liveDivergence,
      );
      expect(
        projectionError,
        lessThanOrEqualTo(0.1),
        reason: 'Frame ${state.frame.sequence} must use its rendered camera',
      );
      expect(
        widgetError,
        lessThanOrEqualTo(0.1),
        reason: 'Marker layout must match frame ${state.frame.sequence}',
      );
      if (sampledSequences.add(state.frame.sequence)) {
        samples.add({
          'sequence': state.frame.sequence,
          'latitude': camera.target.latitude,
          'longitude': camera.target.longitude,
          'expectedX': expected.dx,
          'expectedY': expected.dy,
          'projectionError': projectionError,
          'widgetError': widgetError,
          'liveProjectionDivergence': liveDivergence,
        });
      }
    }

    sample();
    final start = _expectedPosition(markerState!);
    var completed = false;
    // Scrolling animates the center while keeping the zoom fixed.
    final animation = controller!
        .animateCamera(
          CameraUpdate.scrollBy(120, 80),
          duration: const Duration(milliseconds: 1500),
        )
        .then((result) {
          completed = true;

          return result;
        });
    final animationDeadline = DateTime.now().add(const Duration(seconds: 30));
    while ((!completed || controller!.isCameraMoving) &&
        DateTime.now().isBefore(animationDeadline)) {
      await pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      sample();
    }
    expect(completed, isTrue, reason: 'Native animation must complete');
    expect(await animation, isTrue);
    await pump(const Duration(milliseconds: 50));
    sample();
    final end = _expectedPosition(markerState!);
    expect((end - start).distance, greaterThan(100));
    final intermediate = samples.where((sample) {
      final position = Offset(
        sample['expectedX']! as double,
        sample['expectedY']! as double,
      );

      return (position - start).distance > 5 && (position - end).distance > 5;
    }).toList();
    expect(
      intermediate.length,
      greaterThanOrEqualTo(8),
      reason: 'Endpoint checks cannot detect stale camera projection',
    );
    binding.reportData = {
      ...?binding.reportData,
      'userLocationAnimation': {
        'intermediateFrames': intermediate.length,
        'maximumProjectionErrorLogicalPixels': maxProjectionError,
        'maximumWidgetErrorLogicalPixels': maxWidgetError,
        'maximumLiveProjectionDivergenceLogicalPixels':
            maxLiveProjectionDivergence,
        'samples': samples,
      },
    };
    debugPrint(
      'Location animation captured ${intermediate.length} intermediate frames. '
      'Maximum logical pixel errors were $maxProjectionError for projection '
      'and $maxWidgetError for marker layout. '
      'Live camera divergence reached $maxLiveProjectionDivergence pixels.',
    );
  });
}

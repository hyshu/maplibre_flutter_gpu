import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

const _style =
    '{"version":8,"sources":{},"layers":['
    '{"id":"background","type":"background",'
    '"paint":{"background-color":"#eeeeee"}}]}';
const _replacementStyle =
    '{"version":8,"sources":{},"layers":['
    '{"id":"background","type":"background",'
    '"paint":{"background-color":"#ddddff"}}]}';
const _mapSize = Size(280, 700);
const _mapKey = ValueKey('external-camera-map');
const _overlayKey = ValueKey('external-camera-overlay');
const _tolerance = 0.001;

bool _matches(CameraPosition? actual, CameraPosition expected) =>
    actual != null &&
    (actual.target.latitude - expected.target.latitude).abs() < _tolerance &&
    (actual.target.longitude - expected.target.longitude).abs() < _tolerance &&
    (actual.zoom - expected.zoom).abs() < _tolerance &&
    (actual.bearing - expected.bearing).abs() < _tolerance &&
    (actual.tilt - expected.tilt).abs() < _tolerance;

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: reason);
  expect(tester.takeException(), isNull);
}

/// Delivers widget updates while lifecycle events still inhibit map rendering.
Future<void> _pumpWhilePaused(WidgetTester tester) async {
  final frame = tester.pump();
  tester.binding.scheduleForcedFrame();
  await frame;
  expect(tester.takeException(), isNull);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('external camera owns native frames until released', (
    tester,
  ) async {
    const startup = CameraPosition(target: LatLng(60, 35), zoom: 0);
    CameraPosition? input = startup;
    var mapSize = _mapSize;
    var style = _style;
    var loadedStyles = 0;
    MapLibreMapController? controller;
    CameraPosition? createdCamera;
    MapFrameState? overlayFrame;
    final frames = <MapFrameState>[];
    late StateSetter rebuild;
    addTearDown(() async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;

            return OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: mapSize.width,
              maxWidth: mapSize.width,
              minHeight: mapSize.height,
              maxHeight: mapSize.height,
              child: MapLibreMap(
                key: _mapKey,
                styleString: style,
                initialCameraPosition: const CameraPosition(
                  target: LatLng(0, 0),
                  zoom: 8,
                ),
                cameraPosition: input,
                cameraConstrainMode: CameraConstrainMode.none,
                gestureOptions: const MapGestureOptions(flingEnabled: false),
                trackCameraPosition: true,
                compassEnabled: false,
                logoEnabled: false,
                attributionButtonEnabled: false,
                loadingBuilder: null,
                onMapCreated: (value) {
                  controller = value;
                  createdCamera = value.cameraPosition;
                },
                onStyleLoadedCallback: () => loadedStyles++,
                onFrame: (frame) {
                  expectSync(controller!.frameState, same(frame));
                  expectSync(controller!.cameraPosition, same(frame.camera));
                  expectSync(frame.logicalSize.width, greaterThan(0));
                  expectSync(frame.logicalSize.height, greaterThan(0));
                  expectSync(frame.devicePixelRatio, greaterThan(0));
                  expectSync(
                    frame.physicalSize,
                    Size(
                      (frame.logicalSize.width * frame.devicePixelRatio)
                          .floorToDouble(),
                      (frame.logicalSize.height * frame.devicePixelRatio)
                          .floorToDouble(),
                    ),
                  );
                  expectSync(
                    frame.sequence,
                    greaterThan(frames.isEmpty ? 0 : frames.last.sequence),
                  );
                  frames.add(frame);
                },
                overlayBuilder: (context, frame) {
                  overlayFrame = frame;

                  return const IgnorePointer(
                    child: SizedBox.expand(key: _overlayKey),
                  );
                },
              ),
            );
          },
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () =>
          loadedStyles == 1 &&
          _matches(controller?.frameState?.camera, startup) &&
          overlayFrame?.sequence == controller?.frameState?.sequence,
      reason: 'The controlled startup camera must reach a native frame.',
    );
    expect(_matches(createdCamera, startup), isTrue);
    expect(_matches(await controller!.queryCameraPosition(), startup), isTrue);
    expect(find.byKey(_overlayKey), findsOneWidget);
    expect(tester.getSize(find.byKey(_mapKey)), _mapSize);
    if (Platform.isAndroid &&
        const bool.fromEnvironment('MAPLIBRE_ENABLE_ASYNC_RENDERING')) {
      expect(controller!.bridge.supportsAsyncRendering, isTrue);
    }

    const resized = Size(420, 320);
    final initialController = controller;
    final resizeSequence = controller!.frameState!.sequence;
    rebuild(() => mapSize = resized);
    await _pumpUntil(
      tester,
      () =>
          controller?.frameState?.logicalSize == resized &&
          controller!.frameState!.sequence > resizeSequence &&
          _matches(controller?.frameState?.camera, startup) &&
          overlayFrame?.sequence == controller?.frameState?.sequence,
      reason: 'Resizing must preserve the same controlled camera input.',
    );
    expect(controller, same(initialController));
    expect(tester.getSize(find.byKey(_mapKey)), resized);
    expect(_matches(await controller!.queryCameraPosition(), startup), isTrue);

    const droppedFirst = CameraPosition(target: LatLng(5, 15), zoom: 2);
    const droppedSecond = CameraPosition(target: LatLng(8, 18), zoom: 2.5);
    const latest = CameraPosition(target: LatLng(12, 30), zoom: 3, bearing: 20);
    final updateStart = frames.length;
    rebuild(() => input = droppedFirst);
    rebuild(() => input = droppedSecond);
    rebuild(() => input = latest);
    await _pumpUntil(
      tester,
      () =>
          _matches(controller?.frameState?.camera, latest) &&
          overlayFrame?.sequence == controller?.frameState?.sequence,
      reason: 'Property updates must adopt the latest camera input.',
    );
    expect(
      frames
          .skip(updateStart)
          .any(
            (frame) =>
                _matches(frame.camera, droppedFirst) ||
                _matches(frame.camera, droppedSecond),
          ),
      isFalse,
    );
    await expectLater(
      controller!.moveCamera(CameraUpdate.zoomTo(5)),
      throwsStateError,
    );
    await tester.drag(find.byKey(_mapKey), const Offset(80, 40));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_matches(await controller!.queryCameraPosition(), latest), isTrue);

    const afterStyle = CameraPosition(
      target: LatLng(25, 45),
      zoom: 4,
      bearing: 30,
    );
    rebuild(() {
      style = _replacementStyle;
      input = afterStyle;
    });
    await _pumpUntil(
      tester,
      () =>
          loadedStyles == 2 &&
          _matches(controller?.frameState?.camera, afterStyle) &&
          overlayFrame?.sequence == controller?.frameState?.sequence,
      reason: 'Style replacement must preserve the latest controlled camera.',
    );

    const pausedFirst = CameraPosition(
      target: LatLng(-5, -15),
      zoom: 2,
      bearing: 40,
    );
    const pausedSecond = CameraPosition(
      target: LatLng(-8, -18),
      zoom: 2.5,
      bearing: 45,
    );
    const resumedLatest = CameraPosition(
      target: LatLng(-12, -30),
      zoom: 3,
      bearing: 50,
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final pausedFrame = controller!.frameState;
    final pauseStart = frames.length;
    rebuild(() => input = pausedFirst);
    await _pumpWhilePaused(tester);
    rebuild(() => input = pausedSecond);
    await _pumpWhilePaused(tester);
    rebuild(() => input = resumedLatest);
    await _pumpWhilePaused(tester);
    expect(controller!.frameState, same(pausedFrame));
    expect(frames.length, pauseStart);
    expect(
      _matches(await controller!.queryCameraPosition(), afterStyle),
      isTrue,
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pumpUntil(
      tester,
      () =>
          _matches(controller?.frameState?.camera, resumedLatest) &&
          overlayFrame?.sequence == controller?.frameState?.sequence,
      reason: 'Resuming must adopt the latest input retained while paused.',
    );
    expect(
      frames
          .skip(pauseStart)
          .any(
            (frame) =>
                _matches(frame.camera, pausedFirst) ||
                _matches(frame.camera, pausedSecond),
          ),
      isFalse,
    );

    rebuild(() => input = null);
    await tester.pump();
    expect(
      _matches(await controller!.queryCameraPosition(), resumedLatest),
      isTrue,
    );
    expect(await controller!.moveCamera(CameraUpdate.zoomTo(5)), isTrue);
    const released = CameraPosition(
      target: LatLng(-12, -30),
      zoom: 5,
      bearing: 50,
    );
    await _pumpUntil(
      tester,
      () => _matches(controller?.frameState?.camera, released),
      reason: 'Releasing control must permit controller camera updates.',
    );
    await tester.drag(find.byKey(_mapKey), const Offset(80, 0));
    await _pumpUntil(
      tester,
      () =>
          (controller!.frameState!.camera.target.longitude -
                  released.target.longitude)
              .abs() >
          0.05,
      reason: 'Releasing control must restore native pan gestures.',
    );
  });

  testWidgets(
    'camera callbacks retain adopted frames when a query advances the cache',
    (tester) async {
      const startup = CameraPosition(target: LatLng(0, 0), zoom: 3);
      const adoptedCamera = CameraPosition(
        target: LatLng(20, 30),
        zoom: 4,
        bearing: 15,
        tilt: 10,
      );
      const nextCamera = CameraPosition(
        target: LatLng(-12, -30),
        zoom: 5,
        bearing: 40,
        tilt: 20,
      );
      MapLibreMapController? controller;
      MapFrameState? adoptedFrame;
      var loaded = false;
      var refreshOnFrame = false;
      final reportedCameras = <CameraPosition>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 280,
              child: MapLibreMap(
                styleString: _style,
                initialCameraPosition: startup,
                cameraConstrainMode: CameraConstrainMode.none,
                trackCameraPosition: true,
                compassEnabled: false,
                logoEnabled: false,
                attributionButtonEnabled: false,
                loadingBuilder: null,
                onMapCreated: (value) => controller = value,
                onStyleLoadedCallback: () => loaded = true,
                onFrame: (frame) {
                  if (!refreshOnFrame ||
                      !_matches(frame.camera, adoptedCamera)) {
                    return;
                  }
                  refreshOnFrame = false;
                  adoptedFrame = frame;
                  expectSync(
                    controller!.bridge.supportsAsyncRendering,
                    isFalse,
                  );
                  controller!.bridge.setCameraFull(
                    nextCamera.target.latitude,
                    nextCamera.target.longitude,
                    nextCamera.zoom,
                    nextCamera.bearing,
                    nextCamera.tilt,
                  );
                  unawaited(controller!.queryCameraPosition());
                  expectSync(
                    _matches(controller!.cameraPosition, nextCamera),
                    isTrue,
                  );
                  expectSync(_matches(frame.camera, adoptedCamera), isTrue);
                },
                onCameraMove: (camera) {
                  if (adoptedFrame == null) return;
                  expectSync(
                    _matches(
                      camera,
                      reportedCameras.isEmpty ? adoptedCamera : nextCamera,
                    ),
                    isTrue,
                  );
                  reportedCameras.add(camera);
                },
              ),
            ),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => loaded && _matches(controller?.frameState?.camera, startup),
        reason: 'The uncontrolled map must adopt its startup camera.',
      );
      refreshOnFrame = true;
      expect(
        await controller!.moveCamera(
          CameraUpdate.newCameraPosition(adoptedCamera),
        ),
        isTrue,
      );
      await _pumpUntil(
        tester,
        () =>
            reportedCameras.length >= 2 &&
            _matches(controller?.frameState?.camera, nextCamera),
        reason:
            'Camera notifications must follow adopted frames even when a live '
            'query has already cached the next camera.',
      );
      expect(_matches(adoptedFrame?.camera, adoptedCamera), isTrue);
      expect(_matches(reportedCameras.first, adoptedCamera), isTrue);
      expect(_matches(reportedCameras[1], nextCamera), isTrue);
      expect(
        controller!.frameState!.sequence,
        greaterThan(adoptedFrame!.sequence),
      );
      expect(
        _matches(await controller!.queryCameraPosition(), nextCamera),
        isTrue,
      );
    },
    skip: !Platform.isMacOS && !Platform.isIOS,
  );
}

import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

const _style =
    '{"version":8,"sources":{},"layers":['
    '{"id":"background","type":"background",'
    '"paint":{"background-color":"#eeeeee"}}]}';

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
  expect(tester.takeException(), isNull);
}

void _expectRequestedBackend(MapLibreMapController controller) {
  if (Platform.isAndroid &&
      const bool.fromEnvironment('MAPLIBRE_ENABLE_ASYNC_RENDERING')) {
    expect(controller.bridge.supportsAsyncRendering, isTrue);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('partial camera moves compose across native frame leases', (
    tester,
  ) async {
    late MapLibreMapController controller;
    var loaded = false;
    var reenter = false;
    Future<List<bool?>>? reentrantMoves;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MapLibreMap(
          styleString: _style,
          initialCameraPosition: const CameraPosition(
            target: LatLng(0, 0),
            zoom: 3,
          ),
          compassEnabled: false,
          logoEnabled: false,
          attributionButtonEnabled: false,
          onMapCreated: (value) => controller = value,
          onStyleLoadedCallback: () => loaded = true,
          onCameraMove: (_) {
            if (!reenter) return;
            reenter = false;
            reentrantMoves = Future.wait([
              controller.moveCamera(CameraUpdate.zoomTo(8)),
              controller.moveCamera(CameraUpdate.bearingTo(40)),
            ]);
          },
        ),
      ),
    );
    await _pumpUntil(tester, () => loaded);
    _expectRequestedBackend(controller);

    Future<void> expectCamera({
      required double zoom,
      required LatLng target,
      double bearing = 0,
    }) async {
      await _pumpUntil(tester, () => !controller.isCameraMoving);
      final actual = await controller.queryCameraPosition();
      expect(actual!.zoom, closeTo(zoom, 0.001));
      expect(actual.target.latitude, closeTo(target.latitude, 0.001));
      expect(actual.target.longitude, closeTo(target.longitude, 0.001));
      expect(actual.bearing, closeTo(bearing, 0.001));
    }

    expect(await controller.moveCamera(CameraUpdate.zoomTo(5)), isTrue);
    expect(
      await controller.moveCamera(CameraUpdate.newLatLng(const LatLng(10, 20))),
      isTrue,
    );
    await expectCamera(zoom: 5, target: const LatLng(10, 20));

    final moves = [
      controller.moveCamera(CameraUpdate.zoomTo(6)),
      controller.moveCamera(CameraUpdate.newLatLng(const LatLng(15, 25))),
    ];
    expect(await Future.wait(moves), [true, true]);
    await expectCamera(zoom: 6, target: const LatLng(15, 25));

    var target = const LatLng(15, 25);
    for (var index = 0; index < 20; index++) {
      final zoom = 5.0 + index % 3;
      target = LatLng(15 + index / 100, 25 + index / 100);
      if (index.isEven) {
        expect(await controller.moveCamera(CameraUpdate.zoomTo(zoom)), isTrue);
        expect(
          await controller.moveCamera(CameraUpdate.newLatLng(target)),
          isTrue,
        );
      } else {
        expect(
          await Future.wait([
            controller.moveCamera(CameraUpdate.zoomTo(zoom)),
            controller.moveCamera(CameraUpdate.newLatLng(target)),
          ]),
          [true, true],
        );
      }
      await expectCamera(zoom: zoom, target: target);
    }

    reenter = true;
    expect(await controller.moveCamera(CameraUpdate.zoomTo(7)), isTrue);
    await _pumpUntil(tester, () => reentrantMoves != null);
    expect(await reentrantMoves, [true, true]);
    await expectCamera(zoom: 8, target: target, bearing: 40);
  });

  testWidgets('disposing the map cancels camera animation without an error', (
    tester,
  ) async {
    late MapLibreMapController controller;
    var loaded = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MapLibreMap(
          styleString: _style,
          initialCameraPosition: const CameraPosition(
            target: LatLng(0, 0),
            zoom: 3,
          ),
          compassEnabled: false,
          logoEnabled: false,
          attributionButtonEnabled: false,
          onMapCreated: (value) => controller = value,
          onStyleLoadedCallback: () => loaded = true,
        ),
      ),
    );
    await _pumpUntil(tester, () => loaded);
    _expectRequestedBackend(controller);
    final animation = controller.animateCamera(
      CameraUpdate.zoomTo(10),
      duration: const Duration(seconds: 5),
    );
    final result = expectLater(animation, completion(isFalse));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await result;
    expect(tester.takeException(), isNull);
  });
}

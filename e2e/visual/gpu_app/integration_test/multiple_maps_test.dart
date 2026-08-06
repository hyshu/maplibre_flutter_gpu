import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders and controls two independent maps', (tester) async {
    final firstCreated = Completer<gpu.MapLibreMapController>();
    final secondCreated = Completer<gpu.MapLibreMapController>();
    final firstLoaded = Completer<void>();
    final secondLoaded = Completer<void>();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Expanded(
              child: gpu.MapLibreMap(
                styleString: gpu.MapLibreStyles.demo,
                initialCameraPosition: const gpu.CameraPosition(
                  target: gpu.LatLng(35.6812, 139.7671),
                  zoom: 10,
                ),
                compassEnabled: false,
                logoEnabled: false,
                attributionButtonEnabled: false,
                onMapCreated: firstCreated.complete,
                onStyleLoadedCallback: firstLoaded.complete,
              ),
            ),
            Expanded(
              child: gpu.MapLibreMap(
                styleString: gpu.MapLibreStyles.demo,
                initialCameraPosition: const gpu.CameraPosition(
                  target: gpu.LatLng(34.6937, 135.5023),
                  zoom: 9,
                ),
                compassEnabled: false,
                logoEnabled: false,
                attributionButtonEnabled: false,
                onMapCreated: secondCreated.complete,
                onStyleLoadedCallback: secondLoaded.complete,
              ),
            ),
          ],
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while ((!firstLoaded.isCompleted || !secondLoaded.isCompleted) &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(firstLoaded.isCompleted, isTrue);
    expect(secondLoaded.isCompleted, isTrue);
    expect(tester.takeException(), isNull);

    final first = await firstCreated.future;
    final second = await secondCreated.future;
    final firstCamera = await first.queryCameraPosition();
    final secondCamera = await second.queryCameraPosition();
    expect(firstCamera, isNotNull);
    expect(secondCamera, isNotNull);
    expect(
      firstCamera!.target.longitude,
      isNot(closeTo(secondCamera!.target.longitude, 0.1)),
    );

    expect(
      await first.moveCamera(
        gpu.CameraUpdate.newLatLng(const gpu.LatLng(43.0642, 141.3469)),
      ),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final movedFirst = await first.queryCameraPosition();
    final unchangedSecond = await second.queryCameraPosition();
    expect(movedFirst!.target.latitude, closeTo(43.0642, 0.01));
    expect(unchangedSecond!.target.latitude, closeTo(34.6937, 0.1));
    expect(tester.takeException(), isNull);

    // Both native images return to the pool after widget disposal. Reusing one
    // must start a clean session rather than retaining either previous map.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    final replacementLoaded = Completer<void>();
    gpu.MapLibreMapController? replacement;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: gpu.MapLibreMap(
          styleString: gpu.MapLibreStyles.demo,
          initialCameraPosition: const gpu.CameraPosition(
            target: gpu.LatLng(33.5904, 130.4017),
            zoom: 8,
          ),
          compassEnabled: false,
          logoEnabled: false,
          attributionButtonEnabled: false,
          onMapCreated: (controller) => replacement = controller,
          onStyleLoadedCallback: replacementLoaded.complete,
        ),
      ),
    );
    final replacementDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (!replacementLoaded.isCompleted &&
        DateTime.now().isBefore(replacementDeadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(replacementLoaded.isCompleted, isTrue);
    final replacementCamera = await replacement!.queryCameraPosition();
    expect(replacementCamera!.target.latitude, closeTo(33.5904, 0.1));
    expect(tester.takeException(), isNull);
  });
}

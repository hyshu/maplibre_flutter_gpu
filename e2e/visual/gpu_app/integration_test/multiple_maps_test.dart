import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

Future<Uint8List> _pixels(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final data = (await image.toByteData())!;

    return Uint8List.fromList(data.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders and controls two independent maps', (tester) async {
    setVisualE2eRuntimeSceneId('geometry');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await stopVisualE2eAssetServer();
      setVisualE2eRuntimeSceneId(null);
    });
    final offlineStyle = (await loadVisualScene()).styleJson;
    final firstCreated = Completer<gpu.MapLibreMapController>();
    final secondCreated = Completer<gpu.MapLibreMapController>();
    final firstLoaded = Completer<void>();
    final secondLoaded = Completer<void>();
    final firstBoundary = GlobalKey();
    final repaint = ValueNotifier(0);
    addTearDown(repaint.dispose);
    var firstFrames = 0;
    var secondFrames = 0;
    var firstGpuFrames = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Expanded(
              child: RepaintBoundary(
                key: firstBoundary,
                child: gpu.MapLibreMap(
                  styleString: offlineStyle,
                  initialCameraPosition: const gpu.CameraPosition(
                    target: gpu.LatLng(35.6812, 139.7671),
                    zoom: 10,
                  ),
                  compassEnabled: false,
                  logoEnabled: false,
                  attributionButtonEnabled: false,
                  onMapCreated: firstCreated.complete,
                  onStyleLoadedCallback: firstLoaded.complete,
                  onFrame: (_) => firstFrames++,
                  gpuRepaint: repaint,
                  gpuMapRenderCallback: (_) => firstGpuFrames++,
                  overlayBuilder: (_, _) => Align(
                    alignment: Alignment.topLeft,
                    child: ValueListenableBuilder<int>(
                      valueListenable: repaint,
                      builder: (_, value, _) => ColoredBox(
                        color: value == 0
                            ? const Color(0xFF00FF00)
                            : const Color(0xFFFF0000),
                        child: const SizedBox(width: 40, height: 40),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: gpu.MapLibreMap(
                styleString: offlineStyle,
                initialCameraPosition: const gpu.CameraPosition(
                  target: gpu.LatLng(34.6937, 135.5023),
                  zoom: 9,
                ),
                compassEnabled: false,
                logoEnabled: false,
                attributionButtonEnabled: false,
                onMapCreated: secondCreated.complete,
                onStyleLoadedCallback: secondLoaded.complete,
                onFrame: (_) => secondFrames++,
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

    await first.setRenderingPaused(paused: true);
    await tester.pump();
    final frozenPixels = await _pixels(firstBoundary);
    final frozenFrame = first.frameState;
    final frozenFrameCount = firstFrames;
    final frozenGpuCount = firstGpuFrames;
    final secondFrameCount = secondFrames;
    expect(frozenGpuCount, greaterThan(0));
    expect(first.isRenderingPaused, isTrue);

    await first.moveCamera(
      gpu.CameraUpdate.newLatLng(const gpu.LatLng(34.3853, 132.4553)),
    );
    await second.moveCamera(
      gpu.CameraUpdate.newLatLng(const gpu.LatLng(33.5904, 130.4017)),
    );
    for (var i = 1; i <= 10; i++) {
      repaint.value = i;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(firstFrames, frozenFrameCount);
    expect(firstGpuFrames, frozenGpuCount);
    expect(first.frameState, same(frozenFrame));
    expect(await _pixels(firstBoundary), orderedEquals(frozenPixels));
    expect(secondFrames, greaterThan(secondFrameCount));
    expect(
      (await first.queryCameraPosition())!.target.latitude,
      closeTo(34.3853, 0.01),
    );

    await first.setRenderingPaused(paused: false);
    final resumeDeadline = DateTime.now().add(const Duration(seconds: 10));
    while ((firstFrames == frozenFrameCount ||
            firstGpuFrames == frozenGpuCount) &&
        DateTime.now().isBefore(resumeDeadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump();
    expect(first.isRenderingPaused, isFalse);
    expect(firstFrames, greaterThan(frozenFrameCount));
    expect(firstGpuFrames, greaterThan(frozenGpuCount));
    expect(first.frameState!.camera.target.latitude, closeTo(34.3853, 0.01));
    expect(await _pixels(firstBoundary), isNot(orderedEquals(frozenPixels)));
    expect(tester.takeException(), isNull);

    await Future.wait([
      first.setRenderingPaused(paused: true),
      first.setRenderingPaused(paused: false),
    ]);
    expect(first.isRenderingPaused, isFalse);

    // Both native images return to the pool after widget disposal. Reusing one
    // must start a clean session rather than retaining either previous map.
    final pausing = second.setRenderingPaused(paused: true);
    await tester.pumpWidget(const SizedBox.shrink());
    await pausing;
    await tester.pump(const Duration(milliseconds: 200));
    final replacementLoaded = Completer<void>();
    gpu.MapLibreMapController? replacement;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: gpu.MapLibreMap(
          styleString: offlineStyle,
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

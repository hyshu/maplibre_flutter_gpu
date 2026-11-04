import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
// The retained delegate is observed without changing its rendering state.
// ignore: implementation_imports
import 'package:maplibre_flutter_gpu/src/widgets/map_gpu_painter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resize reprojects a controller-driven custom marker', (
    tester,
  ) async {
    final size = ValueNotifier(const Size(320, 240));
    final position = ValueNotifier(Offset.zero);
    MapLibreMapController? controller;
    var loaded = false;
    const location = LatLng(0, 0);
    const mapKey = ValueKey('map');
    const markerKey = ValueKey('marker');

    void project() =>
        position.value = controller!.toScreenOffsets(location).single;

    addTearDown(() async {
      controller?.removeListener(project);
      await tester.pumpWidget(const SizedBox.shrink());
      size.dispose();
      position.dispose();
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder(
            valueListenable: size,
            builder: (context, dimensions, _) => SizedBox.fromSize(
              size: dimensions,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MapLibreMap(
                      key: mapKey,
                      styleString:
                          '{"version":8,"sources":{},"layers":['
                          '{"id":"background","type":"background",'
                          '"paint":{"background-color":"#eeeeee"}}]}',
                      initialCameraPosition: const CameraPosition(
                        target: location,
                        zoom: 3,
                      ),
                      trackCameraPosition: true,
                      compassEnabled: false,
                      logoEnabled: false,
                      attributionButtonEnabled: false,
                      scaleControlEnabled: false,
                      onMapCreated: (value) {
                        controller = value;
                        value.addListener(project);
                        project();
                      },
                      onStyleLoadedCallback: () => loaded = true,
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: position,
                    builder: (context, offset, _) => Positioned(
                      left: offset.dx - 5,
                      top: offset.dy - 5,
                      child: const SizedBox(
                        key: markerKey,
                        width: 10,
                        height: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 300 && !loaded; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(loaded, isTrue);
    final camera = controller!.cameraPosition;
    for (final dimensions in [const Size(480, 360), const Size(280, 200)]) {
      size.value = dimensions;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller!.cameraPosition, camera);
      final mapOrigin = tester.getTopLeft(find.byKey(mapKey));
      expect(
        tester.getCenter(find.byKey(markerKey)) - mapOrigin,
        Offset(dimensions.width / 2, dimensions.height / 2),
      );
    }
  });

  testWidgets('retained GPU callbacks identify the same current map frame', (
    tester,
  ) async {
    MapLibreMapController? controller;
    var loaded = false;
    int? mapSequence;
    CameraUpdate? reentrantUpdate;
    Future<bool?>? reentrantMove;
    int? reentrantSequence;
    final samples = <({int overlay, int? map, int? adopted, double? zoom})>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: MapLibreMap(
            styleString:
                '{"version":8,"sources":{},"layers":['
                '{"id":"background","type":"background",'
                '"paint":{"background-color":"#eeeeee"}}]}',
            initialCameraPosition: const CameraPosition(
              target: LatLng(0, 0),
              zoom: 3,
            ),
            compassEnabled: false,
            logoEnabled: false,
            attributionButtonEnabled: false,
            scaleControlEnabled: false,
            loadingBuilder: null,
            onMapCreated: (value) => controller = value,
            onStyleLoadedCallback: () => loaded = true,
            gpuMapRenderCallback: (context) {
              mapSequence = context.frameSequence;
              final update = reentrantUpdate;
              if (update != null) {
                reentrantUpdate = null;
                reentrantSequence = context.frameSequence;
                reentrantMove = controller!.moveCamera(update);
              }
            },
            gpuRenderCallback: (context) {
              samples.add((
                overlay: context.frameSequence,
                map: mapSequence,
                adopted: controller?.frameState?.sequence,
                zoom: context.mapTransform?.zoom,
              ));
              mapSequence = null;
            },
          ),
        ),
      ),
    );

    Future<void> pumpUntil(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ready(), isTrue);
      expect(tester.takeException(), isNull);
    }

    MapGpuPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .whereType<MapGpuPainter>()
        .single;

    await pumpUntil(() => loaded && samples.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 200));
    final retainedPainter = painter();
    final firstSequence = samples.last.map!;
    samples.clear();
    for (final zoom in [4.0, 5.0]) {
      expect(await controller!.moveCamera(CameraUpdate.zoomTo(zoom)), isTrue);
      await pumpUntil(
        () => samples.any(
          (sample) =>
              sample.zoom != null && (sample.zoom! - zoom).abs() < 0.001,
        ),
      );
      expect(painter(), same(retainedPainter));
    }

    reentrantUpdate = CameraUpdate.zoomTo(7);
    expect(await controller!.moveCamera(CameraUpdate.zoomTo(6)), isTrue);
    await pumpUntil(
      () => samples.any(
        (sample) => sample.zoom != null && (sample.zoom! - 7).abs() < 0.001,
      ),
    );
    expect(await reentrantMove, isTrue);
    expect(reentrantSequence, isNotNull);
    expect(samples.any((sample) => sample.map == reentrantSequence), isTrue);
    expect(painter(), same(retainedPainter));
    expect(samples.last.map, greaterThan(firstSequence));
    expect(samples.map((sample) => sample.map).toSet().length, greaterThan(1));
    for (final sample in samples) {
      expect(sample.overlay, sample.map, reason: '$sample');
      expect(sample.overlay, sample.adopted, reason: '$sample');
    }
  });
}

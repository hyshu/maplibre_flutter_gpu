import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

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

    void project() {
      position.value = controller!.toScreenOffsets(location).single;
    }

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
}

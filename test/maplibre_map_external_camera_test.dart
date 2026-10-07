import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/state/gesture/gesture_coordinator.dart';

void main() {
  const camera = CameraPosition(target: LatLng(35, 139), zoom: 12);
  const mapKey = ValueKey('map');

  Widget view(CameraPosition? position) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 0,
        height: 0,
        child: MapLibreMap(
          key: mapKey,
          cameraPosition: position,
          zoomGesturesEnabled: false,
          doubleClickZoomEnabled: true,
        ),
      ),
    ),
  );

  testWidgets('external ownership overrides and restores gesture settings', (
    tester,
  ) async {
    await tester.pumpWidget(view(null));
    final state = tester.state(find.byKey(mapKey));
    final host = state as MapGestureHost;
    expect(host.gestureSettings.scrollEnabled, isTrue);
    expect(host.gestureSettings.zoomEnabled, isFalse);
    expect(host.gestureSettings.doubleClickZoomEnabled, isTrue);

    await tester.pumpWidget(view(camera));
    expect(tester.state(find.byKey(mapKey)), same(state));
    expect(host.gestureSettings, (
      scrollEnabled: false,
      zoomEnabled: false,
      rotateEnabled: false,
      tiltEnabled: false,
      doubleClickZoomEnabled: false,
    ));

    await tester.pumpWidget(view(null));
    expect(host.gestureSettings.scrollEnabled, isTrue);
    expect(host.gestureSettings.rotateEnabled, isTrue);
    expect(host.gestureSettings.tiltEnabled, isTrue);
    expect(host.gestureSettings.zoomEnabled, isFalse);
    expect(host.gestureSettings.doubleClickZoomEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('frame observers and overlays wait for a native frame', (
    tester,
  ) async {
    var frames = 0;
    var overlays = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 0,
            height: 0,
            child: MapLibreMap(
              cameraPosition: camera,
              onFrame: (_) => frames++,
              overlayBuilder: (_, _) {
                overlays++;

                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(frames, 0);
    expect(overlays, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/native/frame_metadata.dart';
import 'package:maplibre_flutter_gpu/src/state/user_location_projection.dart';
import 'package:maplibre_flutter_gpu/src/widgets/user_location_overlay.dart';

MapFrameState _frame({
  double zoom = 16,
  double bearing = 0,
  double tilt = 0,
  double dpr = 2,
  int sequence = 1,
}) => MapFrameState(
  camera: CameraPosition(
    target: const LatLng(0, 0),
    zoom: zoom,
    bearing: bearing,
    tilt: tilt,
  ),
  logicalSize: const Size(300, 200),
  physicalSize: Size(300 * dpr, 200 * dpr),
  devicePixelRatio: dpr,
  sequence: sequence,
);

UserLocationProjection _projection({
  MapUserLocation? location,
  MapFrameState? frame,
  Offset position = const Offset(100, 60),
}) {
  location ??= MapUserLocation(position: const LatLng(0, 0));
  frame ??= _frame();

  return UserLocationProjection.capture(
    location: location,
    frame: frame,
    transform: _transform(frame, location.position, position),
  )!;
}

FrameMapTransform _transform(
  MapFrameState frame,
  LatLng origin,
  Offset position,
) {
  final width = frame.logicalSize.width;
  final height = frame.logicalSize.height;
  final worldSize = 512 * math.pow(2, frame.camera.zoom);
  final sine = math.sin(origin.latitude * math.pi / 180);

  return (
    viewProjectionMatrix: Float32List.fromList([
      height * 2,
      0,
      0,
      0,
      0,
      -width * 2,
      0,
      0,
      0,
      0,
      1,
      0,
      (position.dx * 2 - width) * height,
      (height - position.dy * 2) * width,
      0,
      width * height,
    ]),
    worldSize: worldSize.toDouble(),
    originX: (origin.longitude + 180) / 360 * worldSize,
    originY:
        (0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi)) * worldSize,
    zoom: frame.camera.zoom,
  );
}

Widget _view({
  required UserLocationProjection projection,
  required MapUserLocationWidgetBuilder builder,
  Size size = const Size(300, 200),
  double dpr = 1,
  VoidCallback? onMapTap,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(devicePixelRatio: dpr),
    child: Center(
      child: SizedBox.fromSize(
        key: const ValueKey('viewport'),
        size: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMapTap,
              child: const SizedBox.expand(),
            ),
            UserLocationOverlay(projection: projection, builder: builder),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  test('location validates coordinates and optional measurements', () {
    for (final invalid in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => MapUserLocation(position: LatLng(0, invalid)),
        throwsArgumentError,
      );
      expect(
        () => MapUserLocation(
          position: const LatLng(0, 0),
          headingDegrees: invalid,
        ),
        throwsArgumentError,
      );
      expect(
        () => MapUserLocation(
          position: const LatLng(0, 0),
          accuracyMeters: invalid,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => MapUserLocation(position: const LatLng(double.nan, 0)),
      throwsArgumentError,
    );
    expect(
      () => MapUserLocation(position: const LatLng(0, 0), accuracyMeters: -1),
      throwsArgumentError,
    );
    expect(
      MapUserLocation(position: const LatLng(0, 0)).headingDegrees,
      isNull,
    );
    expect(
      MapUserLocation(
        position: const LatLng(0, 0),
        accuracyMeters: 0,
      ).accuracyMeters,
      0,
    );
  });

  test('equivalent normalized headings have value equality', () {
    final first = MapUserLocation(
      position: const LatLng(35, 139),
      headingDegrees: -90,
      accuracyMeters: 10,
    );
    final second = MapUserLocation(
      position: const LatLng(35, 139),
      headingDegrees: 270,
      accuracyMeters: 10,
    );
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test(
    'projection uses the rendered matrix after the live camera advances',
    () {
      final frame = _frame(bearing: 90);
      const coordinate = LatLng(0, 179.9);
      final rendered = _transform(frame, coordinate, const Offset(150, 100));
      final live = _transform(frame, coordinate, const Offset(900, 500));
      final projection = UserLocationProjection.capture(
        location: MapUserLocation(position: coordinate, headingDegrees: 0),
        frame: frame,
        transform: rendered,
      )!;
      final liveProjection = UserLocationProjection.capture(
        location: projection.location,
        frame: frame,
        transform: live,
      )!;
      expect(liveProjection.position, const Offset(900, 500));
      rendered.viewProjectionMatrix[12] = 900;
      final state = projection.forLayout(const Size(300, 200));
      expect(state.screenPosition, const Offset(150, 100));
      expect(state.frame, same(frame));
      expect(state.headingRadians, closeTo(-math.pi / 2, 1e-12));
      expect(
        projection.forLayout(const Size(600, 400)).screenPosition,
        const Offset(300, 200),
      );
    },
  );

  test('matrix projection chooses the nearest antimeridian world copy', () {
    final frame = _frame(zoom: 0);
    final transform = _transform(
      frame,
      const LatLng(0, 179.9),
      const Offset(150, 100),
    );
    final projection = UserLocationProjection.capture(
      location: MapUserLocation(position: const LatLng(0, -179.9)),
      frame: frame,
      transform: transform,
    )!;
    expect(projection.position.dx, closeTo(150 + 512 * 0.2 / 360, 1e-10));
    expect(projection.position.dy, 100);
  });

  test('matrix projection performs perspective division and rejects the back of the camera', () {
    final frame = _frame(zoom: 0);
    final transform = _transform(
      frame,
      const LatLng(0, 0),
      const Offset(150, 100),
    );
    transform.viewProjectionMatrix[3] = 100;
    final location = MapUserLocation(position: const LatLng(0, 90));
    final projection = UserLocationProjection.capture(
      location: location,
      frame: frame,
      transform: transform,
    )!;
    expect(
      projection.position.dx,
      closeTo(150 + 128 * 60000 / (60000 + 12800), 1e-9),
    );
    expect(projection.position.dy, 100);
    transform.viewProjectionMatrix[15] = -60000;
    expect(
      UserLocationProjection.capture(
        location: location,
        frame: frame,
        transform: transform,
      ),
      isNull,
    );
  });

  test(
    'native accuracy diameter is rounded and scales with latitude and zoom',
    () {
      const metersPerPixel = 2 * math.pi * 6378137 / (512 * 65536);
      MapUserLocationRenderState state(double latitude, double zoom) =>
          _projection(
            location: MapUserLocation(
              position: LatLng(latitude, 0),
              accuracyMeters: metersPerPixel * 10.3,
            ),
            frame: _frame(zoom: zoom),
          ).forLayout(const Size(300, 200));
      final equator = state(0, 16);
      expect(equator.accuracyPolygon[16].dx - equator.screenPosition.dx, 10.5);
      final higherLatitude = state(60, 16);
      expect(
        higherLatitude.accuracyPolygon[16].dx -
            higherLatitude.screenPosition.dx,
        20.5,
      );
      final closerZoom = state(0, 17);
      expect(
        closerZoom.accuracyPolygon[16].dx - closerZoom.screenPosition.dx,
        20.5,
      );
    },
  );

  test(
    'pitch and bearing affect heading and accuracy in the adopted frame',
    () {
      final state = _projection(
        location: MapUserLocation(
          position: const LatLng(0, 0),
          headingDegrees: 100,
          accuracyMeters: 250,
        ),
        frame: _frame(bearing: 55, tilt: 60),
      ).forLayout(const Size(300, 200));
      expect(state.headingRadians, closeTo(math.atan2(1, 0.5), 1e-12));
      final radiusX = state.accuracyPolygon[16].dx - state.screenPosition.dx;
      final radiusY = state.screenPosition.dy - state.accuracyPolygon[0].dy;
      expect(radiusY, closeTo(radiusX * 0.5, 1e-9));
    },
  );

  test('fractional resize scales cached coordinates without applying DPR', () {
    final location = MapUserLocation(
      position: const LatLng(0, 0),
      headingDegrees: 45,
      accuracyMeters: 100,
    );
    final projection = _projection(location: location, frame: _frame(dpr: 3));
    final state = projection.forLayout(const Size(375.75, 150.25));
    expect(state.screenPosition.dx, closeTo(100 * 375.75 / 300, 1e-10));
    expect(state.screenPosition.dy, closeTo(60 * 150.25 / 200, 1e-10));
    expect(
      state.headingRadians,
      closeTo(math.atan2(375.75 / 300, 150.25 / 200), 1e-12),
    );
    final otherDpr = _projection(
      location: location,
      frame: _frame(dpr: 1),
    ).forLayout(state.viewportSize);
    expect(state.accuracyPolygon, otherDpr.accuracyPolygon);
    expect(state.screenPosition, otherDpr.screenPosition);
  });

  test('missing heading and zero accuracy omit only their own geometry', () {
    for (final accuracy in <double?>[null, 0]) {
      final state = _projection(
        location: MapUserLocation(
          position: const LatLng(0, 0),
          accuracyMeters: accuracy,
        ),
      ).forLayout(const Size(300, 200));
      expect(state.headingRadians, isNull);
      expect(state.accuracyPolygon, isEmpty);
      expect(state.screenPosition, const Offset(100, 60));
    }
  });

  test(
    'invalid projection hides location and accuracy snapshots are immutable',
    () {
      expect(
        UserLocationProjection.capture(
          location: MapUserLocation(position: const LatLng(0, 0)),
          frame: _frame(),
          transform: null,
        ),
        isNull,
      );
      final state = _projection(
        location: MapUserLocation(
          position: const LatLng(0, 0),
          accuracyMeters: 10,
        ),
      ).forLayout(const Size(300, 200));
      expect(() => state.accuracyPolygon.clear(), throwsUnsupportedError);
      final points = <Offset>[Offset.zero];
      final snapshot = MapUserLocationRenderState(
        location: state.location,
        frame: state.frame,
        screenPosition: state.screenPosition,
        viewportSize: state.viewportSize,
        accuracyPolygon: points,
      );
      points.clear();
      expect(snapshot.accuracyPolygon, [Offset.zero]);
    },
  );

  testWidgets('custom marker is centered, updates size, and accepts taps', (
    tester,
  ) async {
    var markerTaps = 0;
    var mapTaps = 0;
    const markerKey = ValueKey('marker');
    Widget? builder(BuildContext context, MapUserLocationRenderState state) =>
        GestureDetector(
          onTap: () => markerTaps++,
          child: const SizedBox(
            key: markerKey,
            width: 30,
            height: 20,
            child: ColoredBox(color: Colors.red),
          ),
        );
    await tester.pumpWidget(
      _view(
        projection: _projection(),
        builder: builder,
        onMapTap: () => mapTaps++,
      ),
    );
    var origin = tester.getTopLeft(find.byKey(const ValueKey('viewport')));
    expect(
      tester.getCenter(find.byKey(markerKey)) - origin,
      const Offset(100, 60),
    );
    await tester.tap(find.byKey(markerKey));
    await tester.tapAt(origin + const Offset(250, 150));
    expect(markerTaps, 1);
    expect(mapTaps, 1);

    await tester.pumpWidget(
      _view(
        projection: _projection(position: const Offset(60, 100)),
        builder: builder,
        size: const Size(450.5, 250.5),
      ),
    );
    origin = tester.getTopLeft(find.byKey(const ValueKey('viewport')));
    final actual = tester.getCenter(find.byKey(markerKey)) - origin;
    expect(actual.dx, closeTo(60 * 450.5 / 300, 1e-10));
    expect(actual.dy, closeTo(100 * 250.5 / 200, 1e-10));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default marker passes all pointer events through and stays logical size',
    (tester) async {
      var taps = 0;
      final projection = _projection(
        location: MapUserLocation(
          position: const LatLng(0, 0),
          headingDegrees: 45,
          accuracyMeters: 1000000,
        ),
      );
      await tester.pumpWidget(
        _view(
          projection: projection,
          builder: MapLibreMap.defaultUserLocationBuilder,
          dpr: 3,
          onMapTap: () => taps++,
        ),
      );
      final marker = find.byType(MapUserLocationMarker);
      expect(tester.getSize(marker), const Size(46, 46));
      final origin = tester.getTopLeft(find.byKey(const ValueKey('viewport')));
      await tester.tapAt(origin + const Offset(100, 60));
      await tester.tapAt(origin + const Offset(250, 150));
      expect(taps, 2);
      final paints = tester.widgetList<CustomPaint>(
        find.descendant(of: marker, matching: find.byType(CustomPaint)),
      );
      expect(paints.length, 2);
      for (final element
          in find
              .descendant(of: marker, matching: find.byType(CustomPaint))
              .evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.width, lessThanOrEqualTo(300));
        expect(size.height, lessThanOrEqualTo(200));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('builder null result hides all marker content', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _view(
        projection: _projection(),
        builder: (_, _) {
          calls++;

          return null;
        },
      ),
    );
    expect(calls, 1);
    expect(find.byType(MapUserLocationMarker), findsNothing);
    expect(find.byType(CustomSingleChildLayout), findsNothing);
  });

  testWidgets(
    'small accuracy stays hidden and large accuracy paints beyond dot bounds',
    (tester) async {
      const captureKey = ValueKey('capture');
      const metersPerPixel = 2 * math.pi * 6378137 / (512 * 65536);
      Future<List<int>> pixelAtRadius(double radius) async {
        final projection = _projection(
          location: MapUserLocation(
            position: const LatLng(0, 0),
            accuracyMeters: metersPerPixel * radius,
          ),
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: ColoredBox(
              color: Colors.white,
              child: _view(
                projection: projection,
                builder: MapLibreMap.defaultUserLocationBuilder,
              ),
            ),
          ),
        );
        final origin = tester.getTopLeft(
          find.byKey(const ValueKey('viewport')),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();

          return data!;
        });
        final index =
            ((origin.dy.toInt() + 60) * boundary.size.width.round() +
                origin.dx.toInt() +
                115) *
            4;

        return [
          for (var channel = 0; channel < 4; channel++)
            bytes!.getUint8(index + channel),
        ];
      }

      final hidden = await pixelAtRadius(17);
      expect(hidden[0], hidden[1]);
      expect(hidden[1], hidden[2]);
      final shown = await pixelAtRadius(25);
      expect(shown[2] - shown[0], greaterThan(15));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'map waits for a frame and accepts clearing before initialization',
    (tester) async {
      var calls = 0;
      Widget view(MapUserLocation? location) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 0,
            height: 0,
            child: MapLibreMap(
              userLocation: location,
              userLocationBuilder: (_, _) {
                calls++;

                return const SizedBox.square(dimension: 10);
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        view(MapUserLocation(position: const LatLng(35, 139))),
      );
      await tester.pumpWidget(view(null));
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

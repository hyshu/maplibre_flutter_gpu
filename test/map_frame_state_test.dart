import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/geo/camera.dart';
import 'package:maplibre_flutter_gpu/src/geo/map_frame_state.dart';
import 'package:maplibre_flutter_gpu/src/gpu/render_context.dart';

void main() {
  const camera = CameraPosition(
    target: LatLng(35, 139),
    zoom: 10.5,
    bearing: 90,
    tilt: 30,
  );
  const frame = MapFrameState(
    camera: camera,
    logicalSize: Size(401, 301),
    physicalSize: Size(601, 451),
    devicePixelRatio: 1.5,
    sequence: 1,
  );

  test('retains native sizes without deriving a different render target', () {
    expect(frame.camera, camera);
    expect(frame.logicalSize, const Size(401, 301));
    expect(frame.physicalSize, const Size(601, 451));
    expect(frame.devicePixelRatio, 1.5);
    expect(frame.sequence, 1);
    expect(frame.mapTransform, isNull);
    expect(frame.physicalSize, isNot(frame.logicalSize * 1.5));
  });

  test('equal adopted frame metadata has stable value identity', () {
    final sameFrame = MapFrameState(
      camera: CameraPosition(
        target: LatLng(35, 139),
        zoom: 10.5,
        bearing: 90,
        tilt: 30,
      ),
      logicalSize: const Size(401, 301),
      physicalSize: const Size(601, 451),
      devicePixelRatio: 1.5,
      sequence: 1,
    );

    expect(sameFrame, frame);
    expect(sameFrame.hashCode, frame.hashCode);
    expect(<MapFrameState>{frame, sameFrame}, hasLength(1));
  });

  test('successive frames differ even when the camera does not move', () {
    const nextFrame = MapFrameState(
      camera: camera,
      logicalSize: Size(401, 301),
      physicalSize: Size(601, 451),
      devicePixelRatio: 1.5,
      sequence: 2,
    );

    expect(nextFrame.camera, frame.camera);
    expect(nextFrame, isNot(frame));
    expect(<MapFrameState>{frame, nextFrame}, hasLength(2));
  });

  test('viewport changes remain distinct at the same sequence value', () {
    const resizedFrame = MapFrameState(
      camera: camera,
      logicalSize: Size(800, 600),
      physicalSize: Size(1200, 900),
      devicePixelRatio: 1.5,
      sequence: 1,
    );

    expect(resizedFrame, isNot(frame));
  });

  test('retained frame projection owns its native matrix snapshot', () {
    final matrix = Float32List(16)..[0] = 2;
    final transform = MapLibreGpuMapTransform(
      viewProjectionMatrix: matrix,
      worldSize: 512,
      originX: 256,
      originY: 256,
      zoom: 0,
    );
    final projectedFrame = MapFrameState(
      camera: camera,
      logicalSize: frame.logicalSize,
      physicalSize: frame.physicalSize,
      devicePixelRatio: frame.devicePixelRatio,
      sequence: frame.sequence,
      mapTransform: transform,
    );
    matrix[0] = 9;

    expect(projectedFrame.mapTransform, same(transform));
    expect(projectedFrame.mapTransform!.viewProjectionMatrix[0], 2);
    final origin = projectedFrame.mapTransform!.project(const LatLng(0, 0));
    expect(origin.x, closeTo(0, 1e-10));
    expect(origin.y, closeTo(0, 1e-10));
  });

  test('frame equality includes the optional projection snapshot identity', () {
    MapLibreGpuMapTransform transform() => MapLibreGpuMapTransform(
      viewProjectionMatrix: Float32List(16),
      worldSize: 512,
      originX: 256,
      originY: 256,
      zoom: 0,
    );
    MapFrameState withTransform(MapLibreGpuMapTransform projection) =>
        MapFrameState(
          camera: camera,
          logicalSize: frame.logicalSize,
          physicalSize: frame.physicalSize,
          devicePixelRatio: frame.devicePixelRatio,
          sequence: frame.sequence,
          mapTransform: projection,
        );
    final projection = transform();
    final first = withTransform(projection);
    final sameSnapshot = withTransform(projection);
    final separateSnapshot = withTransform(transform());

    expect(first, sameSnapshot);
    expect(first.hashCode, sameSnapshot.hashCode);
    expect(first, isNot(frame));
    expect(first, isNot(separateSnapshot));
    expect(<MapFrameState>{
      first,
      sameSnapshot,
      separateSnapshot,
    }, hasLength(2));
  });
}

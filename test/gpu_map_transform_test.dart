import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

void main() {
  test('projects coordinates relative to the map origin', () {
    final transform = MapLibreGpuMapTransform(
      viewProjectionMatrix: Float32List(16),
      worldSize: 512,
      originX: 256,
      originY: 256,
      zoom: 0,
    );

    final position = transform.project(const LatLng(0, 0));

    expect(position.x, closeTo(0, 1e-10));
    expect(position.y, closeTo(0, 1e-10));
    expect(
      position.pixelsPerMeter,
      closeTo(512 / (2 * math.pi * 6378137), 1e-12),
    );
  });

  test('chooses the wrapped world copy nearest the camera', () {
    final transform = MapLibreGpuMapTransform(
      viewProjectionMatrix: Float32List(16),
      worldSize: 512,
      originX: 500,
      originY: 256,
      zoom: 0,
    );

    final position = transform.project(const LatLng(0, -179));

    expect(position.x, closeTo(13.4222222222, 1e-8));
  });

  test('owns an independent copy of the native matrix', () {
    final matrix = Float32List(16)..[0] = 4;
    final transform = MapLibreGpuMapTransform(
      viewProjectionMatrix: matrix,
      worldSize: 512,
      originX: 256,
      originY: 256,
      zoom: 0,
    );

    matrix[0] = 9;

    expect(transform.viewProjectionMatrix[0], 4);
  });
}

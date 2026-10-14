import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/render_context.dart';
import 'package:maplibre_flutter_gpu/src/native/frame_metadata.dart';
import 'package:maplibre_flutter_gpu/src/native/signatures.dart';

void main() {
  late Pointer<NativeMapTransformMetadata> metadata;
  final openGlProjection = Float32List.fromList([
    1.5,
    0,
    0,
    0,
    0,
    2,
    0,
    0,
    0.125,
    -0.25,
    -1.5,
    -1,
    7,
    9,
    -5,
    0,
  ]);

  setUp(() {
    metadata = calloc<NativeMapTransformMetadata>();
    final value = metadata.ref;
    for (var index = 0; index < openGlProjection.length; index++) {
      value.viewProjectionMatrix[index] = openGlProjection[index];
    }
    value
      ..worldSize = 8192
      ..originX = 4096
      ..originY = 2048
      ..zoom = 4
      ..valid = 1;
  });

  tearDown(() => calloc.free(metadata));

  test('native frame decoder rejects missing or invalid transforms', () {
    expect(readFrameMapTransform(nullptr), isNull);

    metadata.ref.valid = 0;

    expect(readFrameMapTransform(metadata), isNull);
  });

  test('callback matrix maps the native near and far planes to 0 and 1', () {
    final frame = readFrameMapTransform(metadata)!;
    final callback = _callbackTransform(frame);
    final matrix = callback.viewProjectionMatrix;

    expect(_project(openGlProjection, 0, 0, -2).depth, -1);
    expect(_project(matrix, 0, 0, -2).depth, closeTo(0, 1e-7));
    expect(_project(matrix, 0, 0, -10).depth, closeTo(1, 1e-7));
    expect(_project(matrix, 0, 0, -1).depth, lessThan(0));
    expect(_project(matrix, 0, 0, -11).depth, greaterThan(1));

    final nativePosition = _project(openGlProjection, 3, -4, -6);
    final callbackPosition = _project(matrix, 3, -4, -6);
    expect(callbackPosition.x, nativePosition.x);
    expect(callbackPosition.y, nativePosition.y);
    expect(callbackPosition.w, nativePosition.w);
    expect(callback.worldSize, 8192);
    expect(callback.originX, 4096);
    expect(callback.originY, 2048);
    expect(callback.zoom, 4);
  });

  test('snapshot reads preserve native depth and convert each copy once', () {
    final first = readFrameMapTransform(metadata)!;
    final second = readFrameMapTransform(metadata)!;
    final callback = _callbackTransform(first);

    expect(second.viewProjectionMatrix, first.viewProjectionMatrix);
    expect(callback.viewProjectionMatrix, first.viewProjectionMatrix);
    expect([
      for (var index = 0; index < 16; index++)
        metadata.ref.viewProjectionMatrix[index],
    ], openGlProjection);
    expect(
      _project(second.viewProjectionMatrix, 0, 0, -2).depth,
      closeTo(0, 1e-7),
    );

    first.viewProjectionMatrix[14] = 99;
    metadata.ref.viewProjectionMatrix[14] = 123;

    expect(second.viewProjectionMatrix[14], -2.5);
    expect(callback.viewProjectionMatrix[14], -2.5);
  });
}

MapLibreGpuMapTransform _callbackTransform(FrameMapTransform frame) {
  return MapLibreGpuMapTransform(
    viewProjectionMatrix: frame.viewProjectionMatrix,
    worldSize: frame.worldSize,
    originX: frame.originX,
    originY: frame.originY,
    zoom: frame.zoom,
  );
}

({double x, double y, double depth, double w}) _project(
  Float32List matrix,
  double x,
  double y,
  double z,
) {
  final clipX = matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12];
  final clipY = matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13];
  final clipZ = matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14];
  final clipW = matrix[3] * x + matrix[7] * y + matrix[11] * z + matrix[15];

  return (x: clipX / clipW, y: clipY / clipW, depth: clipZ / clipW, w: clipW);
}

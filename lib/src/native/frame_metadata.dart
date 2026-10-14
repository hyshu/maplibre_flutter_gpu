import 'dart:ffi';
import 'dart:typed_data';

import '../geo/clip_space.dart';
import 'signatures.dart';

/// Premultiplied clear color exported for a native frame.
typedef FrameClearColor = ({
  double red,
  double green,
  double blue,
  double alpha,
});

/// Native command metadata for one frame.
///
/// [commands] and [payload] remain native-owned and must not outlive their frame or
/// snapshot lease.
typedef FrameCommandMetadata = ({
  Pointer<Void> commands,
  int commandCount,
  int commandStride,
  Pointer<Void> payload,
  int payloadSize,
  FrameClearColor? clearColor,
});

/// Dart-owned map transform metadata for one rendered frame.
///
/// [viewProjectionMatrix] is column-major and produces normalized device depth
/// from 0 at the near plane to 1 at the far plane for Flutter GPU.
typedef FrameMapTransform = ({
  Float32List viewProjectionMatrix,
  double worldSize,
  double originX,
  double originY,
  double zoom,
});

/// Copies the native OpenGL map transform into Flutter GPU clip space.
///
/// Returns null when [metadata] is null or invalid. The returned matrix owns its
/// storage and remains valid after the native frame or snapshot lease ends.
FrameMapTransform? readFrameMapTransform(
  Pointer<NativeMapTransformMetadata> metadata,
) {
  if (metadata == nullptr || metadata.ref.valid == 0) return null;
  final value = metadata.ref;
  final matrix = Float32List(16);
  for (var index = 0; index < matrix.length; index++) {
    matrix[index] = value.viewProjectionMatrix[index];
  }
  convertOpenGlToFlutterGpuDepth(ByteData.sublistView(matrix));

  return (
    viewProjectionMatrix: matrix,
    worldSize: value.worldSize,
    originX: value.originX,
    originY: value.originY,
    zoom: value.zoom,
  );
}

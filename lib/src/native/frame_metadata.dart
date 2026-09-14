import 'dart:ffi';
import 'dart:typed_data';

/// Premultiplied clear color exported for a native frame.
typedef FrameClearColor = ({
  double red,
  double green,
  double blue,
  double alpha,
});

/// Native command metadata for one frame.
///
/// [commands] remains native-owned and must not outlive its command frame or
/// snapshot lease.
typedef FrameCommandMetadata = ({
  Pointer<Void> commands,
  int commandCount,
  int commandStride,
  FrameClearColor? clearColor,
});

/// Map transform metadata exported for one rendered frame.
typedef FrameMapTransform = ({
  Float32List viewProjectionMatrix,
  double worldSize,
  double originX,
  double originY,
  double zoom,
});

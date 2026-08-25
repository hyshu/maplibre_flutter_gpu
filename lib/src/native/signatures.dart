// FFI signature typedefs for the native bridge's C ABI.
//
// Names ending in `N` describe the native ABI. Names ending in `D` describe
// the Dart callable. Dynamic lookup validates symbol names but not these
// declarations, so they must remain synchronized with the native headers.
// C boolean and status values cross the ABI as Int32 values.
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef SessionCreateN = Pointer<Void> Function();
typedef SessionCreateD = Pointer<Void> Function();

typedef SessionHandleN = Void Function(Pointer<Void> session);
typedef SessionHandleD = void Function(Pointer<Void> session);

/// Native-owned command metadata for one exported frame.
final class NativeFrameMetadata extends Struct {
  /// Borrowed pointer to the frame's DrawCommand records.
  external Pointer<Void> commands;

  /// Number of DrawCommand records.
  @Int32()
  external int commandCount;

  /// Number of bytes occupied by each DrawCommand record.
  @Int32()
  external int commandStride;

  /// RGBA clear color values.
  @Array(4)
  external Array<Float> clearColor;

  /// Whether [clearColor] contains a value for this frame.
  @Uint32()
  external int hasClearColor;
}

/// Native-owned map transform metadata for one rendered frame.
final class NativeMapTransformMetadata extends Struct {
  /// Column-major view-projection matrix.
  @Array(16)
  external Array<Float> viewProjectionMatrix;

  /// Width of the Mercator world in pixels at [zoom].
  @Double()
  external double worldSize;

  /// Absolute Mercator pixel X used as the projection origin.
  @Double()
  external double originX;

  /// Absolute Mercator pixel Y used as the projection origin.
  @Double()
  external double originY;

  /// Camera zoom used to produce this transform.
  @Double()
  external double zoom;

  /// Whether this metadata contains a valid transform.
  @Uint32()
  external int valid;
}

typedef InitN = Int32 Function(
  Int32 w,
  Int32 h,
  Float pixelRatio,
  Pointer<Utf8> url,
);
typedef InitD = int Function(
  int width,
  int height,
  double pixelRatio,
  Pointer<Utf8> url,
);

typedef Int32VoidN = Int32 Function();
typedef Int32VoidD = int Function();

typedef VoidVoidN = Void Function();
typedef VoidVoidD = void Function();

typedef Uint64VoidN = Uint64 Function();
typedef Uint64VoidD = int Function();

typedef VoidUint64N = Void Function(Uint64 value);
typedef VoidUint64D = void Function(int value);

typedef FrameMetadataN = Pointer<NativeFrameMetadata> Function();
typedef FrameMetadataD = Pointer<NativeFrameMetadata> Function();

typedef MapTransformMetadataN = Pointer<NativeMapTransformMetadata> Function();
typedef MapTransformMetadataD = Pointer<NativeMapTransformMetadata> Function();

typedef RenderRequestN = Void Function();
typedef SetRenderRequestCallbackN = Void Function(
  Pointer<NativeFunction<RenderRequestN>> callback,
);
typedef SetRenderRequestCallbackD = void Function(
  Pointer<NativeFunction<RenderRequestN>> callback,
);

typedef DoubleVoidN = Double Function();
typedef DoubleVoidD = double Function();

typedef GetCameraN = Int32 Function(Pointer<Double> output);
typedef GetCameraD = int Function(Pointer<Double> output);

typedef SetCameraN = Void Function(Double lat, Double lon, Double zoom);
typedef SetCameraD = void Function(double lat, double lon, double zoom);

typedef SetCameraFullN = Void Function(
  Double lat,
  Double lon,
  Double zoom,
  Double bearing,
  Double pitch,
);
typedef SetCameraFullD = void Function(
  double lat,
  double lon,
  double zoom,
  double bearing,
  double pitch,
);

typedef SetBoundsN = Void Function(
  Int32 hasBounds,
  Double south,
  Double west,
  Double north,
  Double east,
  Int32 hasMinZoom,
  Double minZoom,
  Int32 hasMaxZoom,
  Double maxZoom,
);
typedef SetBoundsD = void Function(
  int hasBounds,
  double south,
  double west,
  double north,
  double east,
  int hasMinZoom,
  double minZoom,
  int hasMaxZoom,
  double maxZoom,
);

typedef SetSizeN = Void Function(Int32 w, Int32 h);
typedef SetSizeD = void Function(int width, int height);

typedef ProjectCoordinatesN = Void Function(
  Pointer<Double> latitudes,
  Pointer<Double> longitudes,
  Pointer<Float> outputX,
  Pointer<Float> outputY,
  Int32 count,
);
typedef ProjectCoordinatesD = void Function(
  Pointer<Double> latitudes,
  Pointer<Double> longitudes,
  Pointer<Float> outputX,
  Pointer<Float> outputY,
  int count,
);

typedef ProjectWrappedCoordinatesN = Void Function(
  Pointer<Double> latitudes,
  Pointer<Double> longitudes,
  Pointer<Int32> tileWraps,
  Pointer<Float> outputX,
  Pointer<Float> outputY,
  Int32 count,
);
typedef ProjectWrappedCoordinatesD = void Function(
  Pointer<Double> latitudes,
  Pointer<Double> longitudes,
  Pointer<Int32> tileWraps,
  Pointer<Float> outputX,
  Pointer<Float> outputY,
  int count,
);

typedef MoveByN = Void Function(Double dx, Double dy);
typedef MoveByD = void Function(double dx, double dy);

typedef AdjustByN = Void Function(Double degrees);
typedef AdjustByD = void Function(double degrees);

typedef ScaleByN = Void Function(Double scale, Double cx, Double cy);
typedef ScaleByD = void Function(double scale, double cx, double cy);

typedef CameraEaseN = Int32 Function(
  Double lat,
  Double lon,
  Double zoom,
  Double bearing,
  Double pitch,
  Int32 durationMs,
  Int32 easing,
);
typedef CameraEaseD = int Function(
  double lat,
  double lon,
  double zoom,
  double bearing,
  double pitch,
  int durationMs,
  int easing,
);

typedef CameraFlyN = CameraEaseN;
typedef CameraFlyD = CameraEaseD;

typedef CameraMoveAnimatedN = Int32 Function(
  Double dx,
  Double dy,
  Int32 durationMs,
  Int32 easing,
);
typedef CameraMoveAnimatedD = int Function(
  double dx,
  double dy,
  int durationMs,
  int easing,
);

typedef CameraScaleAnimatedN = Int32 Function(
  Double scale,
  Int32 hasAnchor,
  Double x,
  Double y,
  Int32 durationMs,
  Int32 easing,
);
typedef CameraScaleAnimatedD = int Function(
  double scale,
  int hasAnchor,
  double x,
  double y,
  int durationMs,
  int easing,
);

typedef CameraFitBoundsN = Int32 Function(
  Double south,
  Double west,
  Double north,
  Double east,
  Double left,
  Double top,
  Double right,
  Double bottom,
  Int32 durationMs,
  Int32 easing,
  Int32 flyTo,
);
typedef CameraFitBoundsD = int Function(
  double south,
  double west,
  double north,
  double east,
  double left,
  double top,
  double right,
  double bottom,
  int durationMs,
  int easing,
  int flyTo,
);

typedef SetContentInsetsN = Int32 Function(
  Double top,
  Double left,
  Double bottom,
  Double right,
  Int32 animated,
);
typedef SetContentInsetsD = int Function(
  double top,
  double left,
  double bottom,
  double right,
  int animated,
);

typedef SetContentInsetsWithDurationN = Int32 Function(
  Double top,
  Double left,
  Double bottom,
  Double right,
  Int32 animated,
  Int32 durationMs,
);
typedef SetContentInsetsWithDurationD = int Function(
  double top,
  double left,
  double bottom,
  double right,
  int animated,
  int durationMs,
);

typedef GetVisibleRegionN = Int32 Function(
  Pointer<Double> south,
  Pointer<Double> west,
  Pointer<Double> north,
  Pointer<Double> east,
);
typedef GetVisibleRegionD = int Function(
  Pointer<Double> south,
  Pointer<Double> west,
  Pointer<Double> north,
  Pointer<Double> east,
);

typedef DoubleArgN = Double Function(Double value);
typedef DoubleArgD = double Function(double value);
typedef VoidDoubleN = Void Function(Double value);
typedef VoidDoubleD = void Function(double value);

typedef StyleStringVoidN = Pointer<Utf8> Function();
typedef StyleStringVoidD = Pointer<Utf8> Function();
typedef StyleSetN = Int32 Function(Pointer<Utf8> value);
typedef StyleSetD = int Function(Pointer<Utf8> value);
typedef StyleSetVisibilityN = Int32 Function(
  Pointer<Utf8> layerId,
  Int32 visible,
);
typedef StyleSetVisibilityD = int Function(Pointer<Utf8> layerId, int visible);
typedef StyleGetVisibilityN = Int32 Function(
  Pointer<Utf8> layerId,
  Pointer<Int32> visible,
);
typedef StyleGetVisibilityD = int Function(
  Pointer<Utf8> layerId,
  Pointer<Int32> visible,
);
typedef StyleSetFilterN = Int32 Function(
  Pointer<Utf8> layerId,
  Pointer<Utf8> filterJson,
);
typedef StyleSetFilterD = int Function(
  Pointer<Utf8> layerId,
  Pointer<Utf8> filterJson,
);
typedef StyleGetFilterN = Pointer<Utf8> Function(Pointer<Utf8> layerId);
typedef StyleGetFilterD = Pointer<Utf8> Function(Pointer<Utf8> layerId);
typedef StyleAddLayerN = Int32 Function(
  Pointer<Utf8> layerJson,
  Pointer<Utf8> beforeLayerId,
);
typedef StyleAddLayerD = int Function(
  Pointer<Utf8> layerJson,
  Pointer<Utf8> beforeLayerId,
);
typedef StyleLayerJsonN = Int32 Function(
  Pointer<Utf8> layerId,
  Pointer<Utf8> propertiesJson,
);
typedef StyleLayerJsonD = int Function(
  Pointer<Utf8> layerId,
  Pointer<Utf8> propertiesJson,
);
typedef StyleLayerIdN = Int32 Function(Pointer<Utf8> layerId);
typedef StyleLayerIdD = int Function(Pointer<Utf8> layerId);

typedef LatLonToScreenN = Void Function(
  Double lat,
  Double lon,
  Pointer<Double> outX,
  Pointer<Double> outY,
);
typedef LatLonToScreenD = void Function(
  double lat,
  double lon,
  Pointer<Double> outX,
  Pointer<Double> outY,
);

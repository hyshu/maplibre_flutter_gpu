import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_gpu/gpu.dart' as gpu;

import '../geo/camera.dart';

/// Records additional Flutter GPU draw commands in a MapLibre render stage.
///
/// The callback runs synchronously during paint. Bind a pipeline, buffers,
/// uniforms, and textures to [MapLibreGpuRenderContext.renderPass], then call
/// `draw(vertexCount)` or `drawIndexed(indexCount)`. The map owns and submits
/// the command buffer.
typedef MapLibreGpuRenderCallback = void Function(
  MapLibreGpuRenderContext context,
);

/// Controls how custom GPU geometry interacts with MapLibre's depth buffer.
enum MapLibreGpuDepthMode {
  /// Clears depth before the callback.
  ///
  /// When a depth attachment is available, custom geometry depth-tests against
  /// itself but appears above MapLibre buildings and terrain.
  isolated,

  /// Loads MapLibre's depth.
  ///
  /// When a depth attachment is available, custom geometry can be occluded by
  /// MapLibre buildings and terrain.
  shared,
}

/// Flutter GPU objects and viewport metadata for an additional map draw pass.
///
/// The pass targets the same color texture and uses the same [gpu.GpuContext]
/// as MapLibre's Flutter GPU renderer. See [depthMode] for depth initialization.
///
/// This object and [renderPass] are valid only while the callback is running.
/// Do not retain or submit them. GPU resources created through [gpuContext]
/// remain owned by the application and should be cached and released by it.
final class MapLibreGpuRenderContext {
  const MapLibreGpuRenderContext({
    required this.gpuContext,
    required this.renderPass,
    required this.logicalSize,
    required this.physicalSize,
    required this.devicePixelRatio,
    required this.frameSequence,
    this.mapTransform,
    this.hasDepthStencilAttachment = false,
    this.depthMode = MapLibreGpuDepthMode.isolated,
  });

  /// The exact Flutter GPU context used by the map renderer.
  final gpu.GpuContext gpuContext;

  /// A pass that loads and preserves the map's existing color texture.
  final gpu.RenderPass renderPass;

  /// Map viewport size in Flutter logical pixels.
  final Size logicalSize;

  /// Map render-target size in physical pixels.
  final Size physicalSize;

  /// Device pixel ratio used when the map render target was created.
  final double devicePixelRatio;

  /// Monotonically increasing sequence that identifies a MapLibre frame.
  final int frameSequence;

  /// Map-space camera transform for the exact rendered frame.
  ///
  /// This is `null` when the native renderer does not provide a map transform.
  /// [MapLibreGpuMapTransform.viewProjectionMatrix] transforms positions from
  /// [MapLibreGpuMapTransform.project] with heights expressed in meters.
  final MapLibreGpuMapTransform? mapTransform;

  /// Whether [renderPass] has a depth/stencil attachment.
  ///
  /// When true, callbacks may enable depth testing and depth writes so custom
  /// geometry self-occludes. Check [depthMode] to determine whether the
  /// attachment was cleared or loaded from MapLibre.
  final bool hasDepthStencilAttachment;

  /// Depth initialization selected for this callback pass.
  final MapLibreGpuDepthMode depthMode;
}

/// Map camera state used to place custom GPU geometry in geographic space.
final class MapLibreGpuMapTransform {
  MapLibreGpuMapTransform({
    required Float32List viewProjectionMatrix,
    required this.worldSize,
    required this.originX,
    required this.originY,
    required this.zoom,
  }) : assert(viewProjectionMatrix.length == 16),
       viewProjectionMatrix = Float32List.fromList(viewProjectionMatrix);

  static const _earthRadiusMeters = 6378137.0;
  static const _maximumLatitude = 85.0511287798066;

  /// Column-major matrix accepting origin-relative world pixels for X/Y and
  /// meters above sea level for Z.
  ///
  /// Its near plane matches MapLibre fill extrusions so values written to the
  /// shared depth attachment are directly comparable.
  final Float32List viewProjectionMatrix;

  /// Width of the Mercator world in pixels at [zoom].
  final double worldSize;

  /// Absolute Mercator pixel X used as the origin of projected positions.
  final double originX;

  /// Absolute Mercator pixel Y used as the origin of projected positions.
  final double originY;

  /// Map zoom used to produce this transform.
  final double zoom;

  /// Projects [coordinate] to origin-relative Mercator world pixels and its
  /// local ground scale.
  MapLibreGpuMapPosition project(LatLng coordinate) {
    final latitude = coordinate.latitude
        .clamp(-_maximumLatitude, _maximumLatitude)
        .toDouble();
    var absoluteX = (coordinate.longitude + 180) / 360 * worldSize;
    final sinLatitude = math.sin(latitude * math.pi / 180);
    final absoluteY =
        (0.5 -
            math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
        worldSize;

    // Choose the wrapped copy closest to the camera origin.
    final halfWorld = worldSize / 2;
    while (absoluteX - originX > halfWorld) {
      absoluteX -= worldSize;
    }
    while (absoluteX - originX < -halfWorld) {
      absoluteX += worldSize;
    }

    final metersPerPixel =
        math.cos(latitude * math.pi / 180) *
        2 *
        math.pi *
        _earthRadiusMeters /
        worldSize;

    return MapLibreGpuMapPosition(
      x: absoluteX - originX,
      y: absoluteY - originY,
      pixelsPerMeter: 1 / metersPerPixel,
    );
  }
}

/// Origin-relative world position and local ground scale for one coordinate.
final class MapLibreGpuMapPosition {
  const MapLibreGpuMapPosition({
    required this.x,
    required this.y,
    required this.pixelsPerMeter,
  });

  /// Mercator world pixel X relative to [MapLibreGpuMapTransform.originX].
  final double x;

  /// Mercator world pixel Y relative to [MapLibreGpuMapTransform.originY].
  final double y;

  /// World pixels representing one ground meter at this latitude.
  final double pixelsPerMeter;
}

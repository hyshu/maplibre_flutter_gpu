/// @docImport '../widgets/maplibre_map.dart';
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;

import '../geo/camera.dart';
import '../labels/label_data.dart';
import '../native/maplibre_ffi.dart' hide LabelData;
import 'layer_properties.dart';
import 'style_resolver.dart';

part 'camera_controller.dart';
part 'controller_binding.dart';
part 'projection_controller.dart';
part 'style_controller.dart';

/// Controls the camera and style of a single [MapLibreMap].
///
/// A controller is provided by [MapLibreMap.onMapCreated] after the map renderer
/// has initialized. The style might still be loading. The [MapLibreMap] owns the
/// controller and disposes it when the widget is removed. App code must not call
/// [dispose] or use the controller after its owning map has been removed. Calls
/// that access the disposed map generally throw a [StateError].
///
/// This controller is also a [ChangeNotifier]. When
/// [MapLibreMap.trackCameraPosition] is `true`, rendered camera changes update
/// the cached [cameraPosition] and notify listeners. Viewport size changes
/// also notify listeners so custom overlays can reproject their coordinates.
/// Direct queries through [queryCameraPosition] update the cache without
/// notifying listeners. Use
/// [MapLibreMap.onCameraMove] when a callback is more convenient than a
/// listener.
///
/// Members that require an operation unavailable in the loaded runtime throw an
/// [UnsupportedError] unless their documentation describes a fallback.
///
/// ```dart
/// MapLibreMap(
///   initialCameraPosition: const CameraPosition(
///     target: LatLng(35.6812, 139.7671),
///     zoom: 12,
///   ),
///   onMapCreated: (controller) {
///     controller.moveCamera(CameraUpdate.zoomTo(13));
///   },
/// );
/// ```
///
/// See also:
///
///  * [MapLibreMap], which creates and owns this controller.
///  * [CameraUpdate], which describes camera changes.
///  * [CameraPosition], which describes the current viewpoint.
class MapLibreMapController extends _ControllerBinding
    with _CameraController, _StyleController, _ProjectionController {
  new _(
    super.bridge, {
    super.onCameraChangeRequested,
    super.beforeCameraMutation,
    super.onStyleChangeRequested,
    super.beforeStyleMutation,
    super.onStyleMutationRequested,
    super.placedLabelsProvider,
  });

  /// Creates a controller bound to an initialized `bridge`.
  ///
  /// This factory is for package internals. App code obtains a controller from
  /// [MapLibreMap.onMapCreated]. The controller reads the initial camera before
  /// returning, but does not own or destroy `bridge`. The bridge must remain
  /// active until the controller is disposed.
  factory bind(
    MaplibreBridge bridge, {
    VoidCallback? onCameraChangeRequested,
    Future<void> Function()? beforeCameraMutation,
    Future<void> Function(String styleString, String resolvedStyle)?
    onStyleChangeRequested,
    Future<void> Function()? beforeStyleMutation,
    VoidCallback? onStyleMutationRequested,
    List<LabelData> Function()? placedLabelsProvider,
  }) {
    final controller = MapLibreMapController._(
      bridge,
      onCameraChangeRequested: onCameraChangeRequested,
      beforeCameraMutation: beforeCameraMutation,
      onStyleChangeRequested: onStyleChangeRequested,
      beforeStyleMutation: beforeStyleMutation,
      onStyleMutationRequested: onStyleMutationRequested,
      placedLabelsProvider: placedLabelsProvider,
    );
    controller._syncCameraFromBridge();

    return controller;
  }

  /// Returns the latest symbols accepted by MapLibre's placement pass.
  ///
  /// Each [LabelData] describes placed text, an icon, or both. The returned list
  /// is a snapshot from the latest processed map frame. It is empty before
  /// placement data becomes available or when no symbols are placed. The
  /// returned list must be treated as read-only.
  List<LabelData> getPlacedLabels() {
    _ensureNotDisposed();

    return _placedLabelsProvider?.call() ?? _bridge.getPlacedLabels();
  }

  /// Whether the native map had no pending work after its last frame.
  ///
  /// This includes tile, network, and native camera transition work. It does not
  /// account for a Flutter fling animation. The value is an instantaneous
  /// status query. [MapLibreMap.onMapIdle] waits for both native work and Flutter
  /// camera animation to settle.
  bool get isMapIdle {
    _ensureNotDisposed();

    return _bridge.isMapIdle();
  }

  /// Returns the borrowed bridge used by package internals.
  ///
  /// This getter is not an application API. The controller does not own the
  /// returned bridge. The bridge must not be destroyed through this reference.
  @visibleForTesting
  MaplibreBridge get bridge {
    _ensureNotDisposed();

    return _bridge;
  }

  /// Releases the controller after its owning [MapLibreMap] is removed.
  ///
  /// The owning map calls this method automatically. App code must not call it.
  /// Calling it more than once has no effect. Active [animateCamera] and
  /// [easeCamera] futures complete with `false`. Calls that access the disposed
  /// map generally throw a [StateError].
  @override
  void dispose() {
    if (_disposed) return;
    _disposeCamera();
    _disposeStyle();
    super.dispose();
  }
}

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
import 'style_resolver.dart';
import 'layer_properties.dart';
import '../native/maplibre_ffi.dart' hide LabelData;

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
/// the cached [cameraPosition] and notify listeners. Direct queries through
/// [queryCameraPosition] update the cache without notifying listeners. Use
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
class MapLibreMapController extends ChangeNotifier {
  MapLibreMapController._(
    this._bridge, {
    this._onCameraChangeRequested,
    this._onStyleChangeRequested,
    this._beforeStyleMutation,
    this._onStyleMutationRequested,
    this._placedLabelsProvider,
  });

  final MaplibreBridge _bridge;
  VoidCallback? _onCameraChangeRequested;
  Future<void> Function(String styleString, String resolvedStyle)?
  _onStyleChangeRequested;
  Future<void> Function()? _beforeStyleMutation;
  VoidCallback? _onStyleMutationRequested;
  List<LabelData> Function()? _placedLabelsProvider;
  CameraPosition? _cameraPosition;
  var _disposed = false;
  var _cameraTransitionGeneration = 0;
  var _styleChangeGeneration = 0;

  /// Creates a controller bound to an initialized `bridge`.
  ///
  /// This factory is for package internals. App code obtains a controller from
  /// [MapLibreMap.onMapCreated]. The controller reads the initial camera before
  /// returning, but does not own or destroy `bridge`. The bridge must remain
  /// active until the controller is disposed.
  factory MapLibreMapController.bind(
    MaplibreBridge bridge, {
    VoidCallback? onCameraChangeRequested,
    Future<void> Function(String styleString, String resolvedStyle)?
    onStyleChangeRequested,
    Future<void> Function()? beforeStyleMutation,
    VoidCallback? onStyleMutationRequested,
    List<LabelData> Function()? placedLabelsProvider,
  }) {
    final controller = MapLibreMapController._(
      bridge,
      onCameraChangeRequested: onCameraChangeRequested,
      onStyleChangeRequested: onStyleChangeRequested,
      beforeStyleMutation: beforeStyleMutation,
      onStyleMutationRequested: onStyleMutationRequested,
      placedLabelsProvider: placedLabelsProvider,
    );
    controller._syncCameraFromBridge();

    return controller;
  }

  /// The latest camera position cached by this controller.
  ///
  /// The cache is initialized before [MapLibreMap.onMapCreated] is called, so a
  /// controller received there has a non-null position. Reading this property
  /// does not query MapLibre. Use [queryCameraPosition] to refresh the cache
  /// before reading the result.
  CameraPosition? get cameraPosition {
    _ensureNotDisposed();

    return _cameraPosition;
  }

  /// Whether a programmatic camera transition or pending update is active.
  ///
  /// This includes transitions started by [animateCamera] and [easeCamera]. It
  /// returns `false` when the runtime cannot report camera movement.
  bool get isCameraMoving {
    _ensureNotDisposed();

    return _bridge.isCameraMoving();
  }

  /// Starts loading a replacement map style from `styleString`.
  ///
  /// `styleString` can be raw style JSON, a URL, an absolute file path, a
  /// `file:` URI, or a Flutter asset path. Relative paths are loaded from the
  /// asset bundle before the style is passed to MapLibre.
  ///
  /// For the current request, the returned future completes after the input has
  /// been resolved and MapLibre has accepted the style request. It does not wait
  /// for the style to finish loading. Use [MapLibreMap.onStyleLoadedCallback] to
  /// observe that event. When style requests overlap, an older pending future
  /// completes without applying its style.
  ///
  /// Throws an [ArgumentError] when `styleString` is empty. Asset-loading errors
  /// are propagated. Throws a [StateError] when MapLibre rejects the style.
  Future<void> setStyle(String styleString) async {
    _ensureNotDisposed();
    final generation = ++_styleChangeGeneration;
    final resolvedStyle = await resolveMapStyleString(styleString);
    _ensureNotDisposed();

    if (generation != _styleChangeGeneration) return;

    final callback = _onStyleChangeRequested;
    await _prepareStyleMutation();

    if (generation != _styleChangeGeneration) return;

    if (callback != null) {
      await callback(styleString, resolvedStyle);
    } else {
      _bridge.setStyle(resolvedStyle);
    }
  }

  /// Returns the current style as JSON.
  ///
  /// The returned future completes with `null` when MapLibre cannot provide the
  /// style document. It does not wait for an in-progress style load to finish.
  Future<String?> getStyle() async {
    _ensureNotDisposed();

    return _bridge.getStyle();
  }

  /// Returns the IDs of all layers in the current style, in style order.
  ///
  /// Each returned element is a [String]. Non-string elements are omitted. The
  /// future throws a [FormatException] when MapLibre returns malformed JSON and
  /// a [StateError] when the decoded value is not a list.
  Future<List> getLayerIds() async {
    _ensureNotDisposed();

    return _bridge.getLayerIds();
  }

  /// Returns the IDs of all sources in the current style.
  ///
  /// Non-string elements are omitted. The future throws a [FormatException]
  /// when MapLibre returns malformed JSON and a [StateError] when the decoded
  /// value is not a list.
  Future<List<String>> getSourceIds() async {
    _ensureNotDisposed();

    return _bridge.getSourceIds();
  }

  /// Returns attribution HTML resolved from the current style sources.
  ///
  /// This includes attribution loaded through TileJSON source URLs. Empty and
  /// duplicate values are omitted. The returned list is empty when no source
  /// declares attribution.
  Future<List<String>> getSourceAttributions() async {
    _ensureNotDisposed();
    final values = _bridge.getSourceAttributions();

    return values
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  /// Shows or hides the layer identified by `layerId`.
  ///
  /// The returned future completes after MapLibre accepts the change and a map
  /// update has been requested. It does not wait for the next frame to render.
  ///
  /// Throws a [StateError] when the layer does not exist or MapLibre rejects the
  /// change.
  Future<void> setLayerVisibility(String layerId, bool visible) async {
    _ensureNotDisposed();
    await _prepareStyleMutation();
    _bridge.setLayerVisibility(layerId, visible);
    _onStyleMutationRequested?.call();
  }

  /// Returns whether the layer identified by `layerId` is visible.
  ///
  /// The returned future completes with `null` when the layer does not exist.
  /// It throws a [StateError] when MapLibre cannot read the visibility value.
  Future<bool?> getLayerVisibility(String layerId) async {
    _ensureNotDisposed();

    return _bridge.getLayerVisibility(layerId);
  }

  /// Adds a fill-extrusion layer such as a 3D building layer.
  ///
  /// `sourceId` identifies an existing source and `layerId` identifies the new
  /// layer. If `belowLayerId` is provided, the new layer is inserted immediately
  /// before that layer in style order. `sourceLayer` selects a layer within a
  /// vector source.
  ///
  /// `minzoom` is inclusive and `maxzoom` is exclusive. `filter` must be a
  /// JSON-encodable MapLibre filter expression. `enableInteraction` has no
  /// effect because this package does not expose interactive layer events.
  ///
  /// The returned future completes after MapLibre accepts the layer and a map
  /// update has been requested. It does not wait for the next frame to render.
  /// Throws a [StateError] when an identifier, source, property, or expression is
  /// rejected.
  Future<void> addFillExtrusionLayer(
    String sourceId,
    String layerId,
    FillExtrusionLayerProperties properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    bool enableInteraction = true,
  }) => addLayer(
    sourceId,
    layerId,
    properties,
    belowLayerId: belowLayerId,
    sourceLayer: sourceLayer,
    minzoom: minzoom,
    maxzoom: maxzoom,
    filter: filter,
    enableInteraction: enableInteraction,
  );

  /// Adds the style layer described by `properties`.
  ///
  /// Only [FillExtrusionLayerProperties] is supported. Other property types
  /// cause an [UnsupportedError]. `sourceId` identifies an existing source and
  /// `layerId` identifies the new layer. If `belowLayerId` is provided, the new
  /// layer is inserted immediately before that layer in style order.
  ///
  /// `sourceLayer` selects a layer within a vector source. `minzoom` is
  /// inclusive and `maxzoom` is exclusive. `filter` must be a JSON-encodable
  /// MapLibre filter expression. `enableInteraction` has no effect because this
  /// package does not expose interactive layer events.
  ///
  /// The returned future completes after MapLibre accepts the layer and a map
  /// update has been requested. It does not wait for the next frame to render.
  /// Throws a [StateError] when an identifier, source, property, or expression is
  /// rejected.
  Future<void> addLayer(
    String sourceId,
    String layerId,
    LayerProperties properties, {
    String? belowLayerId,
    bool enableInteraction = true,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
  }) async {
    _ensureNotDisposed();
    if (properties is! FillExtrusionLayerProperties) {
      throw UnsupportedError(
        'Only FillExtrusionLayerProperties is currently supported',
      );
    }
    final values = properties.toJson();
    final visibility = values.remove('visibility');
    final layer = <String, dynamic>{
      'id': layerId,
      'type': 'fill-extrusion',
      'source': sourceId,
      'source-layer': ?sourceLayer,
      'minzoom': ?minzoom,
      'maxzoom': ?maxzoom,
      'filter': ?filter,
      if (visibility != null) 'layout': {'visibility': visibility},
      'paint': values,
    };
    await _prepareStyleMutation();
    _bridge.addStyleLayerJson(jsonEncode(layer), belowLayerId: belowLayerId);
    _onStyleMutationRequested?.call();
  }

  /// Applies `properties` to the layer identified by `layerId`.
  ///
  /// A `null` property value resets that property to its style-spec default.
  /// Property values must be JSON encodable. The returned future completes after
  /// MapLibre accepts the properties and a map update has been requested. It
  /// does not wait for the next frame to render.
  ///
  /// Throws a [StateError] when the layer does not exist or a property value is
  /// rejected.
  Future<void> setLayerProperties(
    String layerId,
    LayerProperties properties,
  ) async {
    _ensureNotDisposed();
    await _prepareStyleMutation();
    _bridge.setStyleLayerPropertiesJson(
      layerId,
      jsonEncode(properties.toJson(skipNulls: false)),
    );
    _onStyleMutationRequested?.call();
  }

  /// Removes the style layer identified by `layerId`.
  ///
  /// The returned future completes after MapLibre accepts the removal and a map
  /// update has been requested. It does not wait for the next frame to render.
  /// Throws a [StateError] when the layer does not exist or cannot be removed.
  Future<void> removeLayer(String layerId) async {
    _ensureNotDisposed();
    await _prepareStyleMutation();
    _bridge.removeStyleLayer(layerId);
    _onStyleMutationRequested?.call();
  }

  /// Replaces a layer's filter with `filter`, a decoded MapLibre filter
  /// expression such as `['==', ['get', 'class'], 'street']`.
  ///
  /// A `null` filter clears the current filter. The value must be JSON
  /// encodable. The returned future completes after MapLibre accepts the filter
  /// and a map update has been requested. It does not wait for the next frame to
  /// render.
  ///
  /// Throws a [StateError] when the layer does not exist or MapLibre rejects the
  /// expression. Use [setLayerFilter] when rejection is an expected outcome.
  Future<void> setFilter(String layerId, Object? filter) async {
    await _applyFilterJson(
      layerId,
      jsonEncode(filter),
      throwWhenUnapplied: true,
    );
  }

  /// Attempts to replace a layer's filter using raw JSON in `filter`.
  ///
  /// The JSON value `null` clears the filter. The returned future completes with
  /// `true` when the filter was applied. It completes with `false` when the layer
  /// does not exist or MapLibre rejects the expression. A `false` result leaves
  /// the style unchanged.
  Future<bool> setLayerFilter(String layerId, String filter) =>
      _applyFilterJson(layerId, filter, throwWhenUnapplied: false);

  /// The one path to native for both filter setters.
  ///
  /// `throwWhenUnapplied` selects which failure contract applies. The native
  /// call and the repaint that follows a real change are shared, so the two
  /// public methods cannot drift on when the map redraws.
  Future<bool> _applyFilterJson(
    String layerId,
    String filterJson, {
    required bool throwWhenUnapplied,
  }) async {
    _ensureNotDisposed();
    if (throwWhenUnapplied) {
      // The bridge raises MapLibre's own error text, which is more useful than
      // anything reconstructable from a bool.
      await _prepareStyleMutation();
      _bridge.setFilterJson(layerId, filterJson);
      _onStyleMutationRequested?.call();

      return true;
    }
    await _prepareStyleMutation();
    final applied = _bridge.setLayerFilterJson(layerId, filterJson);
    if (applied) _onStyleMutationRequested?.call();

    return applied;
  }

  /// Returns the decoded filter for the layer identified by `layerId`.
  ///
  /// The returned future completes with `null` when the layer has no filter. It
  /// throws a [StateError] when the layer does not exist or its filter cannot be
  /// read. It throws a [FormatException] when MapLibre returns invalid JSON.
  Future<Object?> getFilter(String layerId) async {
    _ensureNotDisposed();
    final filter = _bridge.getLayerFilterJson(layerId);

    return filter == null ? null : jsonDecode(filter);
  }

  /// Moves the camera immediately according to `update`.
  ///
  /// Starting this move interrupts the completion of any earlier
  /// [animateCamera] or [easeCamera] call. The returned future completes with
  /// `true` when MapLibre accepts the update and `false` when it cannot be
  /// applied. This implementation does not return `null`.
  ///
  /// A successful result does not wait for the updated map frame to render.
  Future<bool?> moveCamera(CameraUpdate update) async {
    _ensureNotDisposed();
    _cameraTransitionGeneration++;
    final applied = _applyCameraUpdate(
      update,
      duration: Duration.zero,
      interpolation: null,
      flyTo: false,
    );
    if (!applied) return false;
    _cameraChanged();

    return true;
  }

  /// Animates the camera according to `update`.
  ///
  /// Full camera positions and geographic bounds request a flight transition.
  /// [CameraUpdate.scrollBy] and [CameraUpdate.zoomBy] use their corresponding
  /// animated operations. Full camera positions, scrolling, and zooming fall
  /// back to eased or immediate moves when their animated operations are
  /// unavailable. Geographic bounds require native camera fitting support.
  ///
  /// `duration` defaults to 300 milliseconds. A duration of [Duration.zero]
  /// applies the update immediately.
  ///
  /// The returned future completes with `true` after the transition settles. It
  /// completes with `false` when MapLibre rejects the update, a newer camera
  /// update or gesture interrupts the transition, the transition does not
  /// settle, or the controller is disposed before completion. This
  /// implementation does not return `null`.
  Future<bool?> animateCamera(CameraUpdate update, {Duration? duration}) async {
    _ensureNotDisposed();
    final transitionDuration = duration ?? const Duration(milliseconds: 300);
    final generation = ++_cameraTransitionGeneration;
    final applied = _applyCameraUpdate(
      update,
      duration: transitionDuration,
      interpolation: null,
      flyTo: true,
    );
    if (!applied) return false;
    _cameraChanged();

    return _waitForCameraTransition(transitionDuration, generation);
  }

  /// Animates the camera according to `update` using an easing transition.
  ///
  /// `duration` defaults to 300 milliseconds. A duration of [Duration.zero]
  /// applies the update immediately. When `interpolation` is `null`, MapLibre
  /// chooses its default interpolation. An unavailable easing operation falls
  /// back to an immediate move.
  ///
  /// The returned future completes with `true` after the transition settles. It
  /// completes with `false` when MapLibre rejects the update, a newer camera
  /// update or gesture interrupts the transition, the transition does not
  /// settle, or the controller is disposed before completion.
  Future<bool> easeCamera(
    CameraUpdate update, {
    Duration? duration,
    CameraAnimationInterpolation? interpolation,
  }) async {
    _ensureNotDisposed();
    final transitionDuration = duration ?? const Duration(milliseconds: 300);
    final generation = ++_cameraTransitionGeneration;
    final applied = _applyCameraUpdate(
      update,
      duration: transitionDuration,
      interpolation: interpolation,
      flyTo: false,
    );
    if (!applied) return false;
    _cameraChanged();

    return _waitForCameraTransition(transitionDuration, generation);
  }

  /// Queries MapLibre for the current camera position and updates the cache.
  ///
  /// The returned future completes with the refreshed [cameraPosition]. A
  /// controller received from [MapLibreMap.onMapCreated] completes with a
  /// non-null position while it remains active.
  Future<CameraPosition?> queryCameraPosition() async {
    _ensureNotDisposed();
    _syncCameraFromBridge();

    return _cameraPosition;
  }

  /// Projects `latLng` into the map viewport's logical-pixel coordinate space.
  ///
  /// The origin is the top-left corner of the [MapLibreMap]. The returned
  /// future completes with the horizontal and vertical position relative to
  /// that origin. Use [toScreenOffset] when a synchronous [Offset] is more
  /// convenient.
  Future<math.Point<num>> toScreenLocation(LatLng latLng) async {
    final value = toScreenOffset(latLng);

    return math.Point<double>(value.dx, value.dy);
  }

  /// Projects each coordinate in `latLngs` into logical viewport pixels.
  ///
  /// The origin is the top-left corner of the [MapLibreMap]. The returned list
  /// preserves input order and is empty when `latLngs` is empty. The future
  /// completes after all coordinates have been projected.
  Future<List<math.Point<num>>> toScreenLocationBatch(
    Iterable<LatLng> latLngs,
  ) async {
    _ensureNotDisposed();
    final result = <math.Point<num>>[];
    for (final latLng in latLngs) {
      final value = _bridge.latLonToScreen(latLng.latitude, latLng.longitude);
      result.add(math.Point<double>(value.dx, value.dy));
    }
    return result;
  }

  /// Projects `latLng` into logical viewport pixels synchronously.
  ///
  /// The returned [Offset] is relative to the top-left corner of the
  /// [MapLibreMap].
  Offset toScreenOffset(LatLng latLng) {
    _ensureNotDisposed();

    return _bridge.latLonToScreen(latLng.latitude, latLng.longitude);
  }

  /// Converts a logical viewport position to a geographic coordinate.
  ///
  /// `screenLocation` is relative to the top-left corner of the [MapLibreMap].
  /// The returned future completes with the coordinate under that position. Use
  /// [toLatLngOffset] when a synchronous [Offset] input is more convenient.
  Future<LatLng> toLatLng(math.Point<num> screenLocation) async =>
      toLatLngOffset(
        Offset(screenLocation.x.toDouble(), screenLocation.y.toDouble()),
      );

  /// Converts a logical viewport `screenLocation` to a coordinate synchronously.
  ///
  /// `screenLocation` is relative to the top-left corner of the [MapLibreMap].
  LatLng toLatLngOffset(Offset screenLocation) {
    _ensureNotDisposed();
    final result = _bridge.screenToLatLon(screenLocation.dx, screenLocation.dy);

    return LatLng(result.latitude, result.longitude);
  }

  /// Returns the geographic bounds visible in the current viewport.
  ///
  /// The bounds are latitude and longitude aligned. A viewport that crosses the
  /// antimeridian can produce bounds whose southwest longitude is greater than
  /// its northeast longitude. The future throws a [StateError] when MapLibre
  /// cannot determine the bounds.
  Future<LatLngBounds> getVisibleRegion() async {
    _ensureNotDisposed();
    final region = _bridge.getVisibleRegion();

    return LatLngBounds(
      southwest: LatLng(region.south, region.west),
      northeast: LatLng(region.north, region.east),
    );
  }

  /// Returns ground meters represented by one logical pixel at `latitude`.
  ///
  /// `latitude` is specified in degrees. The scale is calculated at the current
  /// camera zoom. The returned future completes with the scale for that
  /// latitude.
  Future<double> getMetersPerPixelAtLatitude(double latitude) async {
    _ensureNotDisposed();

    return _bridge.getMetersPerPixelAtLatitude(latitude);
  }

  /// Animates the camera to fit the given geographic bounds.
  ///
  /// `west`, `north`, `south`, and `east` are specified in degrees. `padding` is
  /// applied equally to every viewport edge in logical pixels. `duration`
  /// defaults to 200 milliseconds. A duration of [Duration.zero] applies the
  /// update immediately.
  ///
  /// The returned future completes when the transition settles, is interrupted,
  /// or is rejected. It does not report whether MapLibre accepted the update.
  /// Use [animateCamera] with [CameraUpdate.newLatLngBounds] when that result is
  /// needed.
  Future<void> setCameraBounds({
    required double west,
    required double north,
    required double south,
    required double east,
    required int padding,
    Duration duration = const Duration(milliseconds: 200),
  }) => animateCamera(
    CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(south, west),
        northeast: LatLng(north, east),
      ),
      left: padding.toDouble(),
      top: padding.toDouble(),
      right: padding.toDouble(),
      bottom: padding.toDouble(),
    ),
    duration: duration,
  );

  /// Changes the logical-pixel insets used for camera calculations.
  ///
  /// Each edge in `insets` is measured inward from the corresponding edge of the
  /// [MapLibreMap]. When `animated` is `false`, the change is immediate. When it
  /// is `true`, the camera transitions for `duration`, which defaults to 300
  /// milliseconds.
  ///
  /// The returned future completes after an immediate update is accepted or an
  /// animated transition settles or is interrupted. It throws a [StateError]
  /// when MapLibre rejects the insets.
  Future<void> updateContentInsets(
    EdgeInsets insets, [
    bool animated = false,
    Duration duration = const Duration(milliseconds: 300),
  ]) async {
    _ensureNotDisposed();
    final generation = ++_cameraTransitionGeneration;
    _bridge.setContentInsets(
      top: insets.top,
      left: insets.left,
      bottom: insets.bottom,
      right: insets.right,
      animated: animated,
      duration: duration,
    );
    _cameraChanged();
    if (animated) await _waitForCameraTransition(duration, generation);
  }

  /// Resets the camera bearing to north using the cached [cameraPosition].
  ///
  /// The returned future completes after the immediate camera update is
  /// requested. It does not wait for the updated map frame to render. Target,
  /// zoom, and tilt come from the cache. Consider calling [queryCameraPosition]
  /// first when the camera might have changed since the last rendered frame.
  /// This method does nothing when [cameraPosition] is `null`.
  Future<void> resetNorth() async {
    _ensureNotDisposed();
    final current = _cameraPosition;
    if (current == null) return;

    await moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: current.target,
          zoom: current.zoom,
          tilt: current.tilt,
        ),
      ),
    );
  }

  bool _applyCameraUpdate(
    CameraUpdate update, {
    required Duration duration,
    required CameraAnimationInterpolation? interpolation,
    required bool flyTo,
  }) {
    final current = _cameraPosition;
    if (current == null) return false;
    final easing = interpolation?.index ?? -1;
    switch (update.kind) {
      case CameraUpdateKind.bounds:
        final bounds = update.bounds!;

        return _bridge.fitCameraBounds(
          south: bounds.southwest.latitude,
          west: bounds.southwest.longitude,
          north: bounds.northeast.latitude,
          east: bounds.northeast.longitude,
          left: update.left,
          top: update.top,
          right: update.right,
          bottom: update.bottom,
          duration: duration,
          easing: easing,
          flyTo: flyTo,
        );
      case CameraUpdateKind.scroll:
        if (duration == Duration.zero) {
          _bridge.moveBy(update.dx, update.dy);

          return true;
        }
        return _bridge.moveByAnimated(
          dx: update.dx,
          dy: update.dy,
          duration: duration,
          easing: easing,
        );
      case CameraUpdateKind.zoomBy:
        return _bridge.scaleByAnimated(
          amount: update.amount,
          focus: update.focus,
          duration: duration,
          easing: easing,
        );
      default:
        final next = update.resolveAgainst(current);
        if (duration == Duration.zero) {
          _bridge.setCameraFull(
            next.target.latitude,
            next.target.longitude,
            next.zoom,
            next.bearing,
            next.tilt,
          );

          return true;
        }
        if (flyTo) {
          return _bridge.animateCameraFull(
            latitude: next.target.latitude,
            longitude: next.target.longitude,
            zoom: next.zoom,
            bearing: next.bearing,
            pitch: next.tilt,
            duration: duration,
          );
        }
        return _bridge.easeCameraFull(
          latitude: next.target.latitude,
          longitude: next.target.longitude,
          zoom: next.zoom,
          bearing: next.bearing,
          pitch: next.tilt,
          duration: duration,
          easing: easing,
        );
    }
  }

  void _cameraChanged() {
    final callback = _onCameraChangeRequested;
    if (callback != null) {
      callback();
    } else if (_syncCameraFromBridge()) {
      notifyListeners();
    }
  }

  Future<bool> _waitForCameraTransition(
    Duration duration,
    int generation,
  ) async {
    if (duration == Duration.zero) return true;
    final timeout = duration + const Duration(seconds: 2);
    final stopwatch = Stopwatch()..start();
    var observedMoving = false;
    while (!_disposed && stopwatch.elapsed < timeout) {
      if (generation != _cameraTransitionGeneration) return false;
      final moving = _bridge.isCameraMoving();
      observedMoving = observedMoving || moving;
      if (observedMoving && !moving) {
        _syncCameraFromBridge();

        return true;
      }
      if (!observedMoving && stopwatch.elapsed >= duration) {
        _syncCameraFromBridge();

        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    return !_disposed &&
        generation == _cameraTransitionGeneration &&
        !_bridge.isCameraMoving();
  }

  /// Transfers camera ownership to a gesture.
  ///
  /// This package-internal hook cancels the native transition and causes the
  /// future from an active [animateCamera] or [easeCamera] call to complete with
  /// `false`. It does nothing after the controller is disposed.
  @internal
  void notifyCameraGestureStarted() {
    if (_disposed) return;
    _bridge.cancelCameraTransitions();
    _cameraTransitionGeneration++;
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

  Future<void> _prepareStyleMutation() async {
    final callback = _beforeStyleMutation;
    if (callback != null) await callback();
    _ensureNotDisposed();
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

  bool _syncCameraFromBridge() {
    final camera = _bridge.getCamera();
    final next = CameraPosition(
      bearing: camera.bearing,
      target: LatLng(camera.latitude, camera.longitude),
      tilt: camera.pitch,
      zoom: camera.zoom,
    );
    if (next == _cameraPosition) return false;
    _cameraPosition = next;

    return true;
  }

  /// Synchronizes the cached camera after a map frame or gesture update.
  ///
  /// This method is for package code. It returns `true` when the MapLibre camera
  /// differs from the cached [cameraPosition]. When `notifyListeners` is `true`,
  /// a changed position also notifies this controller's listeners.
  bool notifyCameraChanged({bool notifyListeners = true}) {
    _ensureNotDisposed();
    final changed = _syncCameraFromBridge();
    if (changed && notifyListeners) super.notifyListeners();

    return changed;
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('MapLibreMapController used after dispose');
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
    _disposed = true;
    _cameraTransitionGeneration++;
    _styleChangeGeneration++;
    _onCameraChangeRequested = null;
    _onStyleChangeRequested = null;
    _beforeStyleMutation = null;
    _onStyleMutationRequested = null;
    _placedLabelsProvider = null;
    _cameraPosition = null;
    super.dispose();
  }
}

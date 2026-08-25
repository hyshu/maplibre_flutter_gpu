import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../labels/label_data.dart';
import 'abi_generated.dart';
import 'bridge_lifecycle.dart';
import 'label_export_decoder.dart';
import 'library_loader.dart';
import 'signatures.dart';
import 'symbol_table.dart';

export '../labels/label_data.dart'
    show
        LabelAffineTransform,
        LabelData,
        LabelPathPoint,
        LabelTextJustify,
        LabelTextSection;

part 'bindings/camera_bindings.dart';
part 'bindings/label_bindings.dart';
part 'bindings/projection_bindings.dart';
part 'bindings/render_scheduling_bindings.dart';
part 'bindings/style_bindings.dart';

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

/// Pins one native command-export snapshot until Flutter GPU records it.
///
/// Sharing the lease across frame consumers keeps labels, camera state, and
/// command pointers on one native generation.
final class NativeFrameSnapshotLease {
  NativeFrameSnapshotLease._(MaplibreBridge bridge, this.generation)
    : _bridge = bridge;

  MaplibreBridge? _bridge;

  /// Monotonic native identity. Zero is reserved for "no snapshot".
  final int generation;

  /// Whether this lease has not been released.
  bool get isActive => _bridge != null;

  /// Forwards at most one release to native.
  void release() {
    final bridge = _bridge;
    if (bridge == null) return;
    _bridge = null;
    bridge.frameRelease(generation);
  }
}

/// Owns one native MapLibre session and exposes its FFI operations.
class MaplibreBridge
    with
        MaplibreBridgeCameraBindings,
        MaplibreBridgeLabelBindings,
        MaplibreBridgeProjectionBindings,
        MaplibreBridgeRenderSchedulingBindings,
        MaplibreBridgeStyleBindings {
  static const int initSuccess = nativeInitSuccess;
  static const int initFailure = nativeInitFailure;
  static const int initBusy = nativeInitBusy;

  late final DynamicLibrary _lib;
  String? _androidLibraryPath;
  late final Pointer<Void> _nativeSession;
  late final SessionCreateD _createNativeSession;
  late final SessionHandleD _selectNativeSession;
  late final SessionHandleD _releaseNativeSession;
  @override
  final BridgeSessionLifecycle _lifecycle = BridgeSessionLifecycle();
  @override
  final NativeSymbolTable _symbols = NativeSymbolTable();

  late final InitD _init;
  late final LatLonToScreenD _latLonToScreen;
  ProjectCoordinatesD? _projectCoordinates;
  ProjectWrappedCoordinatesD? _projectWrappedCoordinates;
  LatLonToScreenD? _screenToLatLon;
  late final SetSizeD _setSize;
  late final VoidVoidD _destroy;
  var _logicalWidth = 0;
  var _logicalHeight = 0;
  NativeCallable<RenderRequestN>? _renderRequestCallable;
  Int32VoidD? _asyncRenderSupported;
  Int32VoidD? _renderFrameAsync;
  Uint64VoidD? _frameAcquire;
  VoidUint64D? _frameRelease;
  bool? _supportsAsyncRendering;
  static const bool _enableAsyncRendering = bool.fromEnvironment(
    'MAPLIBRE_ENABLE_ASYNC_RENDERING',
  );

  // Reusable native outputs for scalar coordinate projection.
  final _outX = calloc<Double>();
  final _outY = calloc<Double>();
  Pointer<Double> _projectionLatitudes = nullptr;
  Pointer<Double> _projectionLongitudes = nullptr;
  Pointer<Int32> _projectionTileWraps = nullptr;
  Pointer<Float> _projectionX = nullptr;
  Pointer<Float> _projectionY = nullptr;
  var _projectionCapacity = 0;
  @override
  final Pointer<Double> _cameraPositionOutput = calloc<Double>(5);
  @override
  final Pointer<Double> _cameraOutput = calloc<Double>(4);
  @override
  final Pointer<Int32> _styleBoolOutput = calloc<Int32>();

  MaplibreBridge._(this._androidLibraryPath) {
    if (Platform.isIOS || Platform.isMacOS) {
      debugPrint(
        '[MaplibreBridge] loading from process '
        '(${Platform.operatingSystem})',
      );
      _lib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      final libraryPath = _androidLibraryPath;
      if (libraryPath == null) {
        throw StateError('Android native session was not acquired');
      }
      debugPrint('[MaplibreBridge] loading session from: $libraryPath');
      _lib = DynamicLibrary.open(libraryPath);
    } else if (Platform.isLinux) {
      final libraryPath = resolveBridgeLibraryPath('libmaplibre_bridge.so');
      debugPrint('[MaplibreBridge] loading from: $libraryPath');
      _lib = DynamicLibrary.open(libraryPath);
    } else if (Platform.isWindows) {
      final libraryPath = resolveBridgeLibraryPath('maplibre_bridge.dll');
      debugPrint('[MaplibreBridge] loading from: $libraryPath');
      _lib = DynamicLibrary.open(libraryPath);
    } else {
      throw UnsupportedError(
        'MapLibre bridge is not available on ${Platform.operatingSystem}',
      );
    }
    _lookUpSymbols();
    _nativeSession = _createNativeSession();
    if (_nativeSession == nullptr) {
      throw StateError('MapLibre native session allocation failed');
    }
    _lifecycle.onActivate = _activateNativeSession;
  }

  static const MethodChannel _androidSessions = MethodChannel(
    'dev.maplibre.fluttergpu/native_sessions',
  );

  /// Creates a native map session in the process-wide bridge runtime.
  ///
  /// The opaque session keeps map state isolated while MapLibre work remains
  /// serialized on the native owner queue.
  static Future<MaplibreBridge> create() async {
    String? androidLibraryPath;
    if (Platform.isAndroid) {
      androidLibraryPath = await _androidSessions.invokeMethod<String>(
        'acquire',
      );
      if (androidLibraryPath == null || androidLibraryPath.isEmpty) {
        throw StateError('Android native session acquisition returned no path');
      }
    }
    try {
      return MaplibreBridge._(androidLibraryPath);
    } catch (_) {
      if (androidLibraryPath != null) {
        await _androidSessions.invokeMethod<void>('release', {
          'path': androidLibraryPath,
        });
      }
      rethrow;
    }
  }

  static Future<void> _releaseAndroidSession(String path) async {
    try {
      await _androidSessions.invokeMethod<void>('release', {'path': path});
    } on MissingPluginException {
      // Engine teardown can race a widget's final dispose.
    }
  }

  /// Resolves every native entry point.
  ///
  /// Missing required symbols fail immediately. Feature-group availability is
  /// reported only when every lookup succeeds.
  void _lookUpSymbols() {
    _createNativeSession = _lib.lookupFunction<SessionCreateN, SessionCreateD>(
      'maplibre_session_create',
    );
    _selectNativeSession = _lib.lookupFunction<SessionHandleN, SessionHandleD>(
      'maplibre_session_select',
    );
    _releaseNativeSession = _lib.lookupFunction<SessionHandleN, SessionHandleD>(
      'maplibre_session_release',
    );
    _init = _lib.lookupFunction<InitN, InitD>('maplibre_init');
    _renderFrame = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
      'maplibre_render_frame',
    );
    _isIdle = _lib.lookupFunction<Int32VoidN, Int32VoidD>('maplibre_is_idle');
    _setCamera = _lib.lookupFunction<SetCameraN, SetCameraD>(
      'maplibre_set_camera',
    );
    // Calls using this optional group provide fallbacks when possible.
    _symbols.lookUpGroup('camera transform and style state', () {
      _setCameraFull = _lib.lookupFunction<SetCameraFullN, SetCameraFullD>(
        'maplibre_set_camera_full',
      );
      _setBounds = _lib.lookupFunction<SetBoundsN, SetBoundsD>(
        'maplibre_set_bounds',
      );
      _getCameraBearing = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
        'maplibre_get_camera_bearing',
      );
      _getCameraPitch = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
        'maplibre_get_camera_pitch',
      );
      _rotateBy = _lib.lookupFunction<AdjustByN, AdjustByD>(
        'maplibre_rotate_by',
      );
      _pitchBy = _lib.lookupFunction<AdjustByN, AdjustByD>('maplibre_pitch_by');
      _screenToLatLon = _lib.lookupFunction<LatLonToScreenN, LatLonToScreenD>(
        'maplibre_screen_to_lat_lon',
      );
      _isStyleLoaded = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_is_style_loaded',
      );
    });
    // Calls using this group either provide a fallback or report that the
    // native feature is unavailable.
    _symbols.lookUpGroup('animated camera transitions', () {
      _cameraEase = _lib.lookupFunction<CameraEaseN, CameraEaseD>(
        'maplibre_camera_ease_to',
      );
      _cameraFly = _lib.lookupFunction<CameraFlyN, CameraFlyD>(
        'maplibre_camera_fly_to',
      );
      _cameraMoveAnimated = _lib
          .lookupFunction<CameraMoveAnimatedN, CameraMoveAnimatedD>(
            'maplibre_camera_move_by_animated',
          );
      _cameraScaleAnimated = _lib
          .lookupFunction<CameraScaleAnimatedN, CameraScaleAnimatedD>(
            'maplibre_camera_scale_by_animated',
          );
      _cameraFitBounds = _lib
          .lookupFunction<CameraFitBoundsN, CameraFitBoundsD>(
            'maplibre_camera_fit_bounds',
          );
      _isCameraMoving = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_is_camera_moving',
      );
      _cancelCameraTransitions = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_cancel_camera_transitions',
      );
      _setContentInsets = _lib
          .lookupFunction<SetContentInsetsN, SetContentInsetsD>(
            'maplibre_set_content_insets',
          );
      _getVisibleRegion = _lib
          .lookupFunction<GetVisibleRegionN, GetVisibleRegionD>(
            'maplibre_get_visible_region',
          );
      _getMetersPerPixelAtLatitude = _lib
          .lookupFunction<DoubleArgN, DoubleArgD>(
            'maplibre_get_meters_per_pixel_at_latitude',
          );
    });
    _symbols.lookUpGroup('content inset duration', () {
      _setContentInsetsWithDuration = _lib
          .lookupFunction<
            SetContentInsetsWithDurationN,
            SetContentInsetsWithDurationD
          >('maplibre_set_content_insets_with_duration');
    });
    _symbols.lookUpGroup('extended camera pitch', () {
      _setMinPitch = _lib.lookupFunction<VoidDoubleN, VoidDoubleD>(
        'maplibre_set_min_pitch',
      );
      _setMaxPitch = _lib.lookupFunction<VoidDoubleN, VoidDoubleD>(
        'maplibre_set_max_pitch',
      );
    });
    _symbols.lookUpGroup('runtime style mutation', () {
      _styleLastError = _lib.lookupFunction<StyleStringVoidN, StyleStringVoidD>(
        'maplibre_style_last_error',
      );
      _styleSet = _lib.lookupFunction<StyleSetN, StyleSetD>(
        'maplibre_style_set',
      );
      _styleGetJson = _lib.lookupFunction<StyleStringVoidN, StyleStringVoidD>(
        'maplibre_style_get_json',
      );
      _styleGetLayerIds = _lib
          .lookupFunction<StyleStringVoidN, StyleStringVoidD>(
            'maplibre_style_get_layer_ids',
          );
      _styleGetSourceIds = _lib
          .lookupFunction<StyleStringVoidN, StyleStringVoidD>(
            'maplibre_style_get_source_ids',
          );
      _styleSetLayerVisibility = _lib
          .lookupFunction<StyleSetVisibilityN, StyleSetVisibilityD>(
            'maplibre_style_set_layer_visibility',
          );
      _styleGetLayerVisibility = _lib
          .lookupFunction<StyleGetVisibilityN, StyleGetVisibilityD>(
            'maplibre_style_get_layer_visibility',
          );
      _styleSetFilter = _lib.lookupFunction<StyleSetFilterN, StyleSetFilterD>(
        'maplibre_style_set_filter',
      );
      _styleGetFilter = _lib.lookupFunction<StyleGetFilterN, StyleGetFilterD>(
        'maplibre_style_get_filter',
      );
    });
    _symbols.lookUpGroup('runtime layer creation', () {
      _styleAddLayer = _lib.lookupFunction<StyleAddLayerN, StyleAddLayerD>(
        'maplibre_style_add_layer',
      );
      _styleSetLayerProperties = _lib
          .lookupFunction<StyleLayerJsonN, StyleLayerJsonD>(
            'maplibre_style_set_layer_properties',
          );
      _styleRemoveLayer = _lib.lookupFunction<StyleLayerIdN, StyleLayerIdD>(
        'maplibre_style_remove_layer',
      );
    });
    _symbols.lookUpGroup('resolved style attributions', () {
      _styleGetSourceAttributions = _lib
          .lookupFunction<StyleStringVoidN, StyleStringVoidD>(
            'maplibre_style_get_source_attributions',
          );
    });
    _getCameraLat = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
      'maplibre_get_camera_lat',
    );
    _getCameraLon = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
      'maplibre_get_camera_lon',
    );
    _getCameraZoom = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
      'maplibre_get_camera_zoom',
    );
    _symbols.lookUpGroup('camera snapshot', () {
      _getCamera = _lib.lookupFunction<GetCameraN, GetCameraD>(
        'maplibre_get_camera',
      );
    });
    _moveBy = _lib.lookupFunction<MoveByN, MoveByD>('maplibre_move_by');
    _scaleBy = _lib.lookupFunction<ScaleByN, ScaleByD>('maplibre_scale_by');
    _latLonToScreen = _lib.lookupFunction<LatLonToScreenN, LatLonToScreenD>(
      'maplibre_lat_lon_to_screen',
    );
    _symbols.lookUpGroup('batch coordinate projection', () {
      _projectCoordinates = _lib
          .lookupFunction<ProjectCoordinatesN, ProjectCoordinatesD>(
            'maplibre_project_coordinates',
          );
    });
    _symbols.lookUpGroup('wrapped batch coordinate projection', () {
      _projectWrappedCoordinates = _lib
          .lookupFunction<
            ProjectWrappedCoordinatesN,
            ProjectWrappedCoordinatesD
          >('maplibre_project_wrapped_coordinates');
    });
    _setSize = _lib.lookupFunction<SetSizeN, SetSizeD>('maplibre_set_size');
    _destroy = _lib.lookupFunction<VoidVoidN, VoidVoidD>('maplibre_destroy');
    // Missing event callbacks use the polling scheduler.
    _symbols.lookUpGroup('event-driven rendering', () {
      _setRenderRequestCallback = _lib
          .lookupFunction<SetRenderRequestCallbackN, SetRenderRequestCallbackD>(
            'maplibre_set_render_request_callback',
          );
      _processEvents = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_process_events',
      );
      _frameNeedsRepaint = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_frame_needs_repaint',
      );
    });
    _symbols.lookUpGroup('asynchronous frame snapshots', () {
      _asyncRenderSupported = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_async_render_supported',
      );
      _renderFrameAsync = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_render_frame_async',
      );
      _frameAcquire = _lib.lookupFunction<Uint64VoidN, Uint64VoidD>(
        'maplibre_frame_acquire',
      );
      _frameRelease = _lib.lookupFunction<VoidUint64N, VoidUint64D>(
        'maplibre_frame_release',
      );
    });
    _initDrawCommandFFI();
  }

  void _activateNativeSession() => _selectNativeSession(_nativeSession);

  /// Optional ABI groups the loaded library does not provide.
  ///
  /// The returned diagnostic list is unmodifiable.
  List<String> get missingNativeFeatures =>
      List<String>.unmodifiable(_symbols.missingFeatures);

  /// Initializes the native map with a logical size, pixel ratio, and style URL.
  ///
  /// Returns one of [initSuccess], [initFailure], or [initBusy].
  int init(int width, int height, double pixelRatio, String styleUrl) {
    final result = _lifecycle.initialize(() {
      _activateNativeSession();
      final urlPtr = styleUrl.toNativeUtf8();
      try {
        return _init(width, height, pixelRatio, urlPtr.cast());
      } finally {
        calloc.free(urlPtr);
      }
    });
    if (result == initSuccess) {
      _logicalWidth = width;
      _logicalHeight = height;
    }

    return result;
  }

  /// Current logical viewport width.
  int get logicalWidth => _logicalWidth;

  /// Current logical viewport height.
  int get logicalHeight => _logicalHeight;

  /// Synchronously renders one native command frame.
  int renderFrame() {
    _lifecycle.ensureActive();

    return _renderFrame();
  }

  /// Whether native can render command-export frames on its owner thread.
  ///
  /// Requires the `MAPLIBRE_ENABLE_ASYNC_RENDERING` Dart environment flag, all
  /// snapshot entry points, and support from the current native backend.
  bool get supportsAsyncRendering {
    _lifecycle.ensureActive();

    return _supportsAsyncRendering ??=
        _enableAsyncRendering &&
        _symbols.provides('asynchronous frame snapshots') &&
        _asyncRenderSupported!.call() != 0;
  }

  /// Queues or coalesces a render on native's owner thread.
  ///
  /// Returns false when no render is needed. Completion arrives through the
  /// existing render-request callback. Callers must not treat acceptance as a
  /// completed frame.
  bool renderFrameAsync() {
    _lifecycle.ensureActive();
    if (!supportsAsyncRendering) return false;

    return _renderFrameAsync!.call() > 0;
  }

  /// Acquires the latest immutable command snapshot.
  ///
  /// A non-zero generation pins every frame pointer until [frameRelease].
  /// Zero means native has not published a snapshot yet.
  int frameAcquire() {
    _lifecycle.ensureActive();
    if (!supportsAsyncRendering) return 0;

    return _frameAcquire!.call();
  }

  /// Acquires the latest snapshot as an idempotent lease.
  ///
  /// Returns null when native has not published a snapshot.
  NativeFrameSnapshotLease? acquireFrameSnapshot() {
    final generation = frameAcquire();

    return generation == 0
        ? null
        : NativeFrameSnapshotLease._(this, generation);
  }

  /// Releases a snapshot previously returned by [frameAcquire].
  void frameRelease(int generation) {
    if (generation == 0) return;
    _lifecycle.ensureActive();
    // Check symbol availability rather than current async support so an
    // acquired lease can always be returned to native.
    if (_symbols.provides('asynchronous frame snapshots')) {
      _frameRelease!.call(generation);
    }
  }

  /// Whether the map is fully rendered and settled.
  ///
  /// A settled map has no pending tiles or transitions after its latest frame.
  bool isMapIdle() {
    _lifecycle.ensureActive();

    return _isIdle() != 0;
  }

  late final Int32VoidD _renderFrame;
  late final Int32VoidD _isIdle;

  /// Projects a geographic coordinate to logical screen pixels.
  ///
  /// [lat] and [lon] are expressed in degrees.
  Offset latLonToScreen(double lat, double lon) {
    _lifecycle.ensureActive();
    _latLonToScreen(lat, lon, _outX, _outY);

    return Offset(_outX.value, _outY.value);
  }

  /// Projects geographic points in one native call.
  ///
  /// Results preserve input order and use logical screen pixels. When batch
  /// projection is unavailable, each coordinate uses [latLonToScreen].
  List<Offset> latLonsToScreen(
    List<({double latitude, double longitude})> coordinates,
  ) {
    _lifecycle.ensureActive();
    final count = coordinates.length;
    if (count == 0) return const <Offset>[];
    final project = _projectCoordinates;
    if (project == null) {
      return <Offset>[
        for (final coordinate in coordinates)
          latLonToScreen(coordinate.latitude, coordinate.longitude),
      ];
    }
    _ensureProjectionCapacity(count);
    for (var index = 0; index < count; index++) {
      final coordinate = coordinates[index];
      _projectionLatitudes[index] = coordinate.latitude;
      _projectionLongitudes[index] = coordinate.longitude;
    }
    project(
      _projectionLatitudes,
      _projectionLongitudes,
      _projectionX,
      _projectionY,
      count,
    );

    return [
      for (var index = 0; index < count; index++)
        Offset(_projectionX[index], _projectionY[index]),
    ];
  }

  /// Projects coordinates at explicit horizontal world copies.
  List<Offset> wrappedLatLonsToScreen(
    List<({double latitude, double longitude, int tileWrap})> coordinates,
  ) {
    _lifecycle.ensureActive();
    final count = coordinates.length;
    if (count == 0) return const <Offset>[];
    final project = _projectWrappedCoordinates;
    if (project == null) {
      return latLonsToScreen([
        for (final coordinate in coordinates)
          (latitude: coordinate.latitude, longitude: coordinate.longitude),
      ]);
    }
    _ensureProjectionCapacity(count);
    for (var index = 0; index < count; index++) {
      final coordinate = coordinates[index];
      _projectionLatitudes[index] = coordinate.latitude;
      _projectionLongitudes[index] = coordinate.longitude;
      _projectionTileWraps[index] = coordinate.tileWrap;
    }
    project(
      _projectionLatitudes,
      _projectionLongitudes,
      _projectionTileWraps,
      _projectionX,
      _projectionY,
      count,
    );

    return [
      for (var index = 0; index < count; index++)
        Offset(_projectionX[index], _projectionY[index]),
    ];
  }

  /// Ensures the reusable native projection buffers can hold [count] points.
  void _ensureProjectionCapacity(int count) {
    if (_projectionCapacity >= count) return;
    var capacity = _projectionCapacity == 0 ? 64 : _projectionCapacity;
    while (capacity < count) {
      capacity *= 2;
    }
    if (_projectionCapacity != 0) {
      calloc
        ..free(_projectionLatitudes)
        ..free(_projectionLongitudes)
        ..free(_projectionTileWraps)
        ..free(_projectionX)
        ..free(_projectionY);
    }
    _projectionLatitudes = calloc<Double>(capacity);
    _projectionLongitudes = calloc<Double>(capacity);
    _projectionTileWraps = calloc<Int32>(capacity);
    _projectionX = calloc<Float>(capacity);
    _projectionY = calloc<Float>(capacity);
    _projectionCapacity = capacity;
  }

  /// Converts logical screen pixels to a geographic coordinate in degrees.
  ///
  /// Throws an [UnsupportedError] when native inverse projection is
  /// unavailable.
  ({double latitude, double longitude}) screenToLatLon(double x, double y) {
    _lifecycle.ensureActive();
    final callback = _screenToLatLon;
    if (callback == null) {
      throw UnsupportedError(
        'screenToLatLon requires rebuilt MapLibre native libraries',
      );
    }
    callback(x, y, _outX, _outY);

    return (latitude: _outX.value, longitude: _outY.value);
  }

  /// Sets the native map viewport size in logical pixels.
  void setSize(int width, int height) {
    _lifecycle.ensureActive();
    _setSize(width, height);
    _logicalWidth = width;
    _logicalHeight = height;
  }

  // Native DrawCommand entry points.
  VoidVoidD? _frameBegin;
  VoidVoidD? _frameEnd;
  Int32VoidD? _frameGetCommandCount;
  Pointer<Void> Function()? _frameGetCommands;
  Int32VoidD? _frameGetCommandStride;
  Pointer<Float> Function()? _frameGetClearColor;
  FrameMetadataD? _frameGetMetadata;
  MapTransformMetadataD? _frameGetMapTransform;

  void _initDrawCommandFFI() {
    _symbols.lookUpGroup('split label placement export', () {
      _getLabelStaticCount = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_static_count',
      );
      _getLabelStaticRecords = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_get_label_static_records',
          );
      _getLabelStaticStride = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_static_stride',
      );
      _getLabelStaticBlob = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_get_label_static_blob',
          );
      _getLabelStaticBlobSize = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_static_blob_size',
      );
      _getLabelStaticVersion = _lib
          .lookupFunction<Uint32 Function(), int Function()>(
            'maplibre_get_label_static_version',
          );
      _getLabelStaticContentVersion = _lib
          .lookupFunction<Uint32 Function(), int Function()>(
            'maplibre_get_label_static_content_version',
          );
      _getLabelDynamicCount = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_dynamic_count',
      );
      _getLabelDynamicRecords = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_get_label_dynamic_records',
          );
      _getLabelDynamicStride = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_dynamic_stride',
      );
      _getLabelDynamicBlob = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_get_label_dynamic_blob',
          );
      _getLabelDynamicBlobSize = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_dynamic_blob_size',
      );
      _getLabelDynamicVersion = _lib
          .lookupFunction<Uint32 Function(), int Function()>(
            'maplibre_get_label_dynamic_version',
          );
    });
    // Label placement export is optional. The map can render without it.
    _symbols.lookUpGroup('label placement export', () {
      _getLabelCount = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_count',
      );
      _getLabels = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_get_labels',
          );
      _getLabelStride = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_stride',
      );
      _getLabelBlob = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_get_label_blob',
          );
      _getLabelBlobSize = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_get_label_blob_size',
      );
      _getLabelsVersion = _lib
          .lookupFunction<Uint32 Function(), int Function()>(
            'maplibre_get_labels_version',
          );
    });
    try {
      _frameBegin = _lib.lookupFunction<VoidVoidN, VoidVoidD>(
        'maplibre_frame_begin',
      );
      _frameEnd = _lib.lookupFunction<VoidVoidN, VoidVoidD>(
        'maplibre_frame_end',
      );
      _frameGetCommandCount = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_frame_get_command_count',
      );
      _frameGetCommands = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_frame_get_commands',
          );
      _frameGetCommandStride = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_frame_get_command_stride',
      );
      _frameGetClearColor = _lib
          .lookupFunction<Pointer<Float> Function(), Pointer<Float> Function()>(
            'maplibre_frame_get_clear_color',
          );
      try {
        _frameGetMetadata = _lib.lookupFunction<FrameMetadataN, FrameMetadataD>(
          'maplibre_frame_get_metadata',
        );
      } catch (_) {
        // Metadata falls back to the individual accessors.
      }
      try {
        _frameGetMapTransform = _lib
            .lookupFunction<MapTransformMetadataN, MapTransformMetadataD>(
              'maplibre_frame_get_map_transform',
            );
      } catch (_) {
        // GPU overlays can render without map-space metadata.
      }
    } catch (_) {
      // Command export is unavailable on this native backend.
    }
  }

  /// Begins a synchronous native command frame when command export is available.
  void frameBegin() {
    _lifecycle.ensureActive();
    _frameBegin?.call();
  }

  /// Ends the current synchronous native command frame when available.
  void frameEnd() {
    _lifecycle.ensureActive();
    _frameEnd?.call();
  }

  /// Reassembles metadata from the individual field accessors.
  FrameCommandMetadata _frameGetMetadataPiecewise() {
    final clearColorPtr = _frameGetClearColor?.call() ?? nullptr;
    FrameClearColor? clearColor;
    if (clearColorPtr != nullptr) {
      final rgba = clearColorPtr.asTypedList(4);
      clearColor = (
        red: rgba[0].toDouble(),
        green: rgba[1].toDouble(),
        blue: rgba[2].toDouble(),
        alpha: rgba[3].toDouble(),
      );
    }
    return (
      commands: _frameGetCommands?.call() ?? nullptr,
      commandCount: _frameGetCommandCount?.call() ?? 0,
      commandStride: _frameGetCommandStride?.call() ?? 0,
      clearColor: clearColor,
    );
  }

  /// Returns command metadata for the current native frame.
  ///
  /// The command pointer remains native-owned and is valid only for the
  /// current command frame or pinned snapshot.
  FrameCommandMetadata frameGetMetadata() {
    _lifecycle.ensureActive();
    final metadata = _frameGetMetadata?.call() ?? nullptr;
    if (metadata != nullptr) {
      final value = metadata.ref;
      final clearColor = value.hasClearColor == 0
          ? null
          : (
              red: value.clearColor[0].toDouble(),
              green: value.clearColor[1].toDouble(),
              blue: value.clearColor[2].toDouble(),
              alpha: value.clearColor[3].toDouble(),
            );

      return (
        commands: value.commands,
        commandCount: value.commandCount,
        commandStride: value.commandStride,
        clearColor: clearColor,
      );
    }
    return _frameGetMetadataPiecewise();
  }

  /// Returns a copy of the current frame's map transform metadata.
  ///
  /// Returns null when native does not provide a valid transform.
  FrameMapTransform? frameGetMapTransform() {
    _lifecycle.ensureActive();
    final metadata = _frameGetMapTransform?.call() ?? nullptr;
    if (metadata == nullptr || metadata.ref.valid == 0) return null;
    final value = metadata.ref;

    return (
      viewProjectionMatrix: Float32List.fromList([
        for (var index = 0; index < 16; index++)
          value.viewProjectionMatrix[index],
      ]),
      worldSize: value.worldSize,
      originX: value.originX,
      originY: value.originY,
      zoom: value.zoom,
    );
  }

  var _devicePixelRatio = 1.0;

  /// Device pixel ratio associated with the current map viewport.
  double get devicePixelRatio {
    _lifecycle.ensureActive();

    return _devicePixelRatio;
  }

  /// Updates the device pixel ratio associated with the map viewport.
  set devicePixelRatio(double value) {
    _lifecycle.ensureActive();
    _devicePixelRatio = value;
  }

  /// Installs an isolate-safe native wake handler.
  ///
  /// Native may invoke the function pointer from any thread. [NativeCallable]
  /// posts the callback to the owning isolate. Does nothing when native render
  /// notifications are unavailable.
  void setRenderRequestHandler(VoidCallback handler) {
    _lifecycle.ensureActive();
    final register = _setRenderRequestCallback;
    if (register == null) return;
    clearRenderRequestHandler();
    final callable = NativeCallable<RenderRequestN>.listener(handler);
    _renderRequestCallable = callable;
    register(callable.nativeFunction);
  }

  @override
  void clearRenderRequestHandler() {
    final callable = _renderRequestCallable;
    if (callable == null) return;
    _setRenderRequestCallback?.call(
      nullptr.cast<NativeFunction<RenderRequestN>>(),
    );
    _renderRequestCallable = null;
    callable.close();
  }

  /// Destroys the map session and releases all locally owned native resources.
  ///
  /// Repeated calls do nothing.
  void destroy() {
    if (_lifecycle.disposed) return;
    _activateNativeSession();
    clearRenderRequestHandler();
    try {
      _lifecycle.dispose(
        destroyNativeSession: _destroy,
        releaseLocalResources: () {
          calloc.free(_outX);
          calloc.free(_outY);
          if (_projectionCapacity != 0) {
            calloc
              ..free(_projectionLatitudes)
              ..free(_projectionLongitudes)
              ..free(_projectionTileWraps)
              ..free(_projectionX)
              ..free(_projectionY);
          }
          calloc.free(_cameraPositionOutput);
          calloc.free(_cameraOutput);
          calloc.free(_styleBoolOutput);
        },
      );
    } finally {
      _releaseNativeSession(_nativeSession);
    }
    final androidLibraryPath = _androidLibraryPath;
    _androidLibraryPath = null;
    if (androidLibraryPath != null) {
      // The process image remains loaded. This only completes the plugin-side
      // session bookkeeping after native destruction.
      unawaited(_releaseAndroidSession(androidLibraryPath));
    }
  }
}

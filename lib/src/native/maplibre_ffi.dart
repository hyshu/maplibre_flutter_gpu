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
import 'frame_metadata.dart';
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

export 'frame_metadata.dart';

part 'bindings/camera_bindings.dart';
part 'bindings/frame_bindings.dart';
part 'bindings/label_bindings.dart';
part 'bindings/projection_bindings.dart';
part 'bindings/render_scheduling_bindings.dart';
part 'bindings/style_bindings.dart';
part 'bindings/symbol_lookup.dart';
part 'frame_snapshot.dart';

/// Owns one native MapLibre session and exposes its FFI operations.
class MaplibreBridge
    with
        MaplibreBridgeCameraBindings,
        MaplibreBridgeFrameBindings,
        MaplibreBridgeLabelBindings,
        MaplibreBridgeProjectionBindings,
        MaplibreBridgeRenderSchedulingBindings,
        MaplibreBridgeStyleBindings {
  static const initSuccess = nativeInitSuccess;
  static const initFailure = nativeInitFailure;
  static const initBusy = nativeInitBusy;

  late final DynamicLibrary _lib;
  String? _androidLibraryPath;
  late final Pointer<Void> _nativeSession;
  late final SessionCreateD _createNativeSession;
  late final SessionHandleD _selectNativeSession;
  late final SessionHandleD _releaseNativeSession;
  @override
  final _lifecycle = BridgeSessionLifecycle();
  @override
  final _symbols = NativeSymbolTable();

  late final InitD _init;
  late final SetSizeD _setSize;
  late final VoidVoidD _destroy;
  var _logicalWidth = 0;
  var _logicalHeight = 0;

  new _(this._androidLibraryPath) {
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

  static const _androidSessions = MethodChannel(
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

  void _activateNativeSession() => _selectNativeSession(_nativeSession);

  /// Optional ABI groups the loaded library does not provide.
  ///
  /// The returned diagnostic list is unmodifiable.
  List<String> get missingNativeFeatures =>
      .unmodifiable(_symbols.missingFeatures);

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

  /// Sets the native map viewport size in logical pixels.
  void setSize(int width, int height) {
    _lifecycle.ensureActive();
    _setSize(width, height);
    _logicalWidth = width;
    _logicalHeight = height;
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
          _releaseProjectionResources();
          _releaseCameraResources();
          _releaseStyleResources();
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

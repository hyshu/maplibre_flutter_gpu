part of '../maplibre_ffi.dart';

/// Selects asynchronous rendering only when the native ABI supports it.
///
/// [enabled] defaults to true and accepts a compile-time diagnostic override.
/// The camera capability is checked by symbol presence because its runtime
/// value can temporarily require releasing a frame before a camera mutation.
/// [queryNativeSupport] runs only after every static requirement is satisfied.
bool nativeAsyncRenderingSupported({
  required NativeSymbolTable symbols,
  required int Function()? queryNativeSupport,
  bool enabled = const bool.fromEnvironment(
    'MAPLIBRE_ENABLE_ASYNC_RENDERING',
    defaultValue: true,
  ),
}) =>
    enabled &&
    symbols.provides('asynchronous frame snapshots') &&
    symbols.provides('camera snapshot preservation') &&
    (queryNativeSupport?.call() ?? 0) != 0;

/// Native command frames, metadata, and asynchronous snapshot leases.
///
/// Command pointers remain native-owned until their frame or lease ends.
mixin MaplibreBridgeFrameBindings {
  BridgeSessionLifecycle get _lifecycle;
  NativeSymbolTable get _symbols;

  late final Int32VoidD _renderFrame;
  Int32VoidD? _asyncRenderSupported;
  Int32VoidD? _renderFrameAsync;
  Uint64VoidD? _frameAcquire;
  VoidUint64D? _frameRelease;
  bool? _supportsAsyncRendering;

  /// Synchronously renders one native command frame.
  int renderFrame() {
    _lifecycle.ensureActive();

    return _renderFrame();
  }

  /// Whether native can render command-export frames on its owner thread.
  ///
  /// Enabled by default on every platform whose native library provides
  /// snapshot leases and camera preservation. Set
  /// `MAPLIBRE_ENABLE_ASYNC_RENDERING=false` at compile time to use
  /// synchronous rendering.
  bool get supportsAsyncRendering {
    _lifecycle.ensureActive();

    return _supportsAsyncRendering ??= nativeAsyncRenderingSupported(
      symbols: _symbols,
      queryNativeSupport: _asyncRenderSupported,
    );
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

  // Native DrawCommand entry points.
  VoidVoidD? _frameBegin;
  VoidVoidD? _frameEnd;
  Int32VoidD? _frameGetCommandCount;
  Pointer<Void> Function()? _frameGetCommands;
  Int32VoidD? _frameGetCommandStride;
  Pointer<Float> Function()? _frameGetClearColor;
  FrameMetadataD? _frameGetMetadata;
  MapTransformMetadataD? _frameGetMapTransform;

  void _lookUpFrameSymbols(DynamicLibrary library) {
    try {
      _frameBegin = library.lookupFunction<VoidVoidN, VoidVoidD>(
        'maplibre_frame_begin',
      );
      _frameEnd = library.lookupFunction<VoidVoidN, VoidVoidD>(
        'maplibre_frame_end',
      );
      _frameGetCommandCount = library.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_frame_get_command_count',
      );
      _frameGetCommands = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_frame_get_commands',
          );
      _frameGetCommandStride = library.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_frame_get_command_stride',
      );
      _frameGetClearColor = library
          .lookupFunction<Pointer<Float> Function(), Pointer<Float> Function()>(
            'maplibre_frame_get_clear_color',
          );
      try {
        _frameGetMetadata = library
            .lookupFunction<FrameMetadataN, FrameMetadataD>(
              'maplibre_frame_get_metadata',
            );
      } catch (_) {
        // Metadata falls back to the individual accessors.
      }
      try {
        _frameGetMapTransform = library
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
    final stride = _frameGetCommandStride?.call() ?? 0;

    return (
      commands: _frameGetCommands?.call() ?? nullptr,
      // The compact ABI requires the single-call arena metadata.
      commandCount: stride == DrawCommandAbi.size
          ? 0
          : _frameGetCommandCount?.call() ?? 0,
      commandStride: stride,
      payload: nullptr,
      payloadSize: 0,
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
        // Payload fields are present only for the matching command ABI.
        payload: value.commandStride == DrawCommandAbi.size
            ? value.payload
            : nullptr,
        payloadSize: value.commandStride == DrawCommandAbi.size
            ? value.payloadSize
            : 0,
        clearColor: clearColor,
      );
    }
    return _frameGetMetadataPiecewise();
  }

  /// Returns a copy of the current frame's map transform metadata.
  ///
  /// The matrix uses Flutter GPU's normalized depth range from 0 to 1.
  /// Returns null when native does not provide a valid transform.
  FrameMapTransform? frameGetMapTransform() {
    _lifecycle.ensureActive();

    return readFrameMapTransform(_frameGetMapTransform?.call() ?? nullptr);
  }

  /// Requires the transform captured with exported native frames.
  ///
  /// Throws an [UnsupportedError] when the loaded bridge lacks this feature.
  void requireFrameMapTransformSupport() {
    _lifecycle.ensureActive();
    _symbols.requireSymbol(
      _frameGetMapTransform,
      'MapLibreMap location projection',
      feature: 'frame map transform metadata',
    );
  }
}

part of '../maplibre_map.dart';

extension _MapInitialization on _MapLibreMapState {
  Future<void> _initMap() async {
    if (_initializing || _initialized || _initializationError != null) return;
    _initializing = true;
    try {
      if (!mounted) return;

      final viewport = _viewport.applied;
      if (viewport == null) return;
      final shaderLibrary = await loadMapShaderLibrary();
      if (!mounted) return;
      if (!_hasBridge) {
        final bridge = await MaplibreBridge.create();
        if (!mounted) {
          bridge.destroy();

          return;
        }
        _bridge = bridge;
        _hasBridge = true;
      }

      final style = await resolveRequestedStyle(
        requestedStyle: () => widget.styleString,
        isAlive: () => mounted,
      );
      if (style == null) return;
      // Layout can change while shaders, the bridge, or the style are loading.
      final latestViewport = _viewport.applied!;
      _viewport.adoptForInitialization(
        latestViewport.logicalSize,
        latestViewport.dpr,
      );
      final gpuRenderer = GpuFrameRenderer(shaders: shaderLibrary);
      if (!_startNativeMap(style.resolved)) {
        gpuRenderer.dispose();

        return;
      }
      _bindNativeMap(
        requested: style.requested,
        resolved: style.resolved,
        gpuRenderer: gpuRenderer,
      );
      await _pumpUntilStyleLoaded();
      if (!mounted) return;

      // Register native render requests after synchronous startup completes.
      _rendered = true;
      _bridge.setRenderRequestHandler(_onNativeRenderRequested);
      renderGesture();
      _updateMapState(() {});
      scheduleRepaint();
    } catch (error, stackTrace) {
      debugPrint('[MapLibreMap] initialization failed: $error\n$stackTrace');
      if (mounted) {
        _updateMapState(() => _initializationError = error.toString());
      }
    } finally {
      _initializing = false;
    }
  }

  /// Starts the native map and records any initialization error.
  bool _startNativeMap(String resolvedStyle) {
    final result = _bridge.init(
      _viewport.logicalWidth,
      _viewport.logicalHeight,
      _viewport.devicePixelRatio,
      resolvedStyle,
    );
    if (result == MaplibreBridge.initSuccess) {
      _initialized = true;

      return true;
    }
    final message = result == MaplibreBridge.initBusy
        ? 'A native map session is already active. Dispose it before retrying.'
        : 'MapLibre native initialization failed (error $result).';
    debugPrint('[MapLibreMap] $message');
    if (mounted) {
      _updateMapState(() => _initializationError = message);
    }
    return false;
  }

  /// Connects the Dart controller and renderer to the native map.
  void _bindNativeMap({
    required String requested,
    required String resolved,
    required GpuFrameRenderer gpuRenderer,
  }) {
    _gpuRenderer = gpuRenderer;
    _bridge.devicePixelRatio = _viewport.devicePixelRatio;

    _loadSpriteAtlas(resolved, baseStyleUrl: requested);

    final initial = widget.initialCameraPosition;
    if (initial != null) {
      _bridge.setCameraFull(
        initial.target.latitude,
        initial.target.longitude,
        initial.zoom,
        initial.bearing,
        initial.tilt,
      );
    }

    _controller = MapLibreMapController.bind(
      _bridge,
      onCameraChangeRequested: _onProgrammaticCameraChange,
      beforeCameraMutation: _releaseFrameSnapshotBeforeMutation,
      onStyleChangeRequested: _onProgrammaticStyleChange,
      beforeStyleMutation: _releaseFrameSnapshotBeforeMutation,
      onStyleMutationRequested: _onProgrammaticStyleMutation,
      placedLabelsProvider: _placedLabelsForController,
    );
    widget.onMapCreated?.call(_controller!);
  }

  /// Renders until the style is loaded across consecutive frames.
  ///
  /// Stops after a bounded number of attempts.
  Future<void> _pumpUntilStyleLoaded() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      _bridge.frameBegin();
      _bridge.renderFrame();
      _bridge.frameEnd();
      final wasStyleLoaded = _style.isLoaded;
      _updateStyleLoadedState();
      if (_style.isLoaded && wasStyleLoaded) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
  }
}

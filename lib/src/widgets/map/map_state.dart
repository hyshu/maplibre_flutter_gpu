part of '../maplibre_map.dart';

class _MapLibreMapState extends State<MapLibreMap>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements MapGestureHost {
  late final MaplibreBridge _bridge;
  var _hasBridge = false;
  GpuFrameRenderer? _gpuRenderer;
  final _gpuStratumResources = MapGpuResourcePool();
  MapLibreMapController? _controller;
  var _initializing = false;
  var _initialized = false;
  var _rendered = false;
  String? _initializationError;

  late final MapRenderScheduler _renders;
  final _labels = MapLabelSource();
  final _style = MapStyleSession<SpriteAtlas>(
    loadAtlas: SpriteAtlas.load,
    disposeAtlas: (atlas) => atlas.dispose(),
  );

  final _viewport = MapViewport();
  final _gpuFrame = ValueNotifier(0);
  final _symbolVersion = ValueNotifier(0);
  final _symbolLayoutVersion = ValueNotifier(0);
  // Notify viewport listeners only after a native frame is available.
  var _viewportNotificationPending = false;
  final _controlsVersion = ValueNotifier(0);
  var _nativeCommandLayerIndices = const <int>{};
  var _symbolGpuStratumSlots = const <int>[0];
  NativeFrameSnapshotLease? _pendingFrameSnapshot;
  var _lastProcessedFrameGeneration = 0;
  var _applyingFrameSnapshot = false;
  var _releaseSnapshotAfterApply = false;
  Completer<void>? _styleMutationBarrier;

  late final MapGestureCoordinator _gestures;
  final _gestureRegionKey = GlobalKey();
  MacosTrackpadTiltRegistration? _macosTrackpadTilt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gestures = .new(vsync: this, host: this);
    _macosTrackpadTilt = MacosTrackpadTiltRegistration.register(
      onStart: _gestures.onMacosTrackpadTiltStart,
      onUpdate: _gestures.onMacosTrackpadTiltUpdate,
      onEnd: _gestures.onMacosTrackpadTiltEnd,
    );
    _renders = .new(
      isAlive: () => mounted && _initialized,
      hasPendingNativeWork: () => _hasBridge && _bridge.processEvents(),
      render: () {
        renderGesture();
        _finishScheduledRender();
      },
    );
  }

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
      final gpuRenderer = GpuFrameRenderer(
        bridge: _bridge,
        shaders: shaderLibrary,
      );
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
      setState(() {});
      scheduleRepaint();
    } catch (error, stackTrace) {
      debugPrint('[MapLibreMap] initialization failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _initializationError = error.toString());
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
      setState(() => _initializationError = message);
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
      onStyleChangeRequested: _onProgrammaticStyleChange,
      beforeStyleMutation: _releaseFrameSnapshotBeforeStyleMutation,
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

  void _applyCameraConstraints() {
    final bounds = widget.cameraTargetBounds.bounds;
    final zoom = widget.minMaxZoomPreference;
    final tilt = widget.minMaxTiltPreference;
    // Widen each range first so both upward and downward changes are valid.
    _bridge.setBounds(
      south: bounds?.southwest.latitude,
      west: bounds?.west,
      north: bounds?.northeast.latitude,
      east: bounds?.east,
    );
    _bridge.setBounds(
      south: bounds?.southwest.latitude,
      west: bounds?.west,
      north: bounds?.northeast.latitude,
      east: bounds?.east,
      minZoom: zoom.minZoom,
      maxZoom: zoom.maxZoom,
    );
    _bridge.setMinPitch(0);
    _bridge.setMaxPitch(180);
    _bridge.setMinPitch(tilt.minTilt ?? 0);
    _bridge.setMaxPitch(tilt.maxTilt ?? 60);
  }

  void _updateStyleLoadedState() {
    if (_style.isLoaded || !_bridge.isStyleLoaded()) return;
    _style.markLoaded();
    _applyCameraConstraints();
    widget.onStyleLoadedCallback?.call();
  }

  void _loadSpriteAtlas(String styleSource, {String? baseStyleUrl}) {
    unawaited(
      _style
          .loadSpriteAtlas(
            styleSource,
            baseStyleUrl: baseStyleUrl,
            isAlive: () => mounted && _initialized,
          )
          .then((adopted) {
            if (!adopted) return;
            setState(() {
              _labels.cacheScreenPositions(_bridge, _style.spriteAtlas);
            });
          }),
    );
  }

  Future<void> _onProgrammaticStyleChange(
    String styleString,
    String resolvedStyle,
  ) async {
    if (!mounted || !_initialized) {
      throw StateError('MapLibreMap is not available for a style change');
    }
    setState(() {
      _style.beginStyleChange();
      _labels.reset();
    });
    _programmaticCameraIdlePending = false;
    _bridge.setStyle(resolvedStyle);
    _loadSpriteAtlas(resolvedStyle, baseStyleUrl: styleString);
    renderGesture();
    scheduleRepaint();
  }

  Future<void> _releaseFrameSnapshotBeforeStyleMutation() {
    if (_applyingFrameSnapshot) {
      _releaseSnapshotAfterApply = true;

      return (_styleMutationBarrier ??= .new()).future;
    }
    _releasePendingFrameSnapshot();

    return Future<void>.value();
  }

  void _releasePendingFrameSnapshot() {
    final snapshot = _pendingFrameSnapshot;
    _pendingFrameSnapshot = null;
    snapshot?.release();
  }

  void _finishApplyingFrameSnapshot() {
    _applyingFrameSnapshot = false;
    if (!_releaseSnapshotAfterApply) return;
    _releaseSnapshotAfterApply = false;
    final barrier = _styleMutationBarrier;
    _styleMutationBarrier = null;
    try {
      _releasePendingFrameSnapshot();
      barrier?.complete();
    } catch (error, stackTrace) {
      barrier?.completeError(error, stackTrace);
    }
  }

  List<LabelData> _placedLabelsForController() => _labels.placedLabels;

  bool _gpuRenderingAllowed() =>
      _initialized && _rendered && _renders.isAppActive;

  void _onProgrammaticStyleMutation() {
    if (!mounted || !_initialized) return;
    renderGesture();
    scheduleRepaint();
  }

  void _scheduleViewportUpdate(Size logicalSize, double dpr) {
    if (!_viewport.request(logicalSize, dpr)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _viewport.cancel();

        return;
      }
      final viewport = _viewport.takePending();
      if (viewport == null) return;
      _applyViewport(viewport.logicalSize, viewport.dpr);
    });
  }

  void _applyViewport(Size logicalSize, double observedDpr) {
    final resized = _viewport.applyLayout(
      logicalSize,
      observedDpr,
      initialized: _initialized,
    );
    if (!_initialized) {
      if (!_initializing) _initMap();

      return;
    }
    if (!resized) return;
    _viewportNotificationPending = true;
    final bridge = _bridge;
    // Release the previous-size snapshot before rendering the resized map.
    final staleSnapshot =
        _pendingFrameSnapshot ?? bridge.acquireFrameSnapshot();
    _pendingFrameSnapshot = null;
    try {
      bridge.setSize(_viewport.logicalWidth, _viewport.logicalHeight);
    } finally {
      staleSnapshot?.release();
    }
    renderGesture();
    if (mounted) setState(() {});
    scheduleRepaint();
  }

  var _programmaticCameraIdlePending = false;

  @override
  void scheduleRepaint() {
    if (_renders.isRepaintPending || !_initialized || !_renders.isAppActive) {
      return;
    }
    final bridge = _bridge;
    final needsRepaint = bridge.frameNeedsRepaint;
    final cameraMoving = bridge.isCameraMoving();
    final flingAnimating = _gestures.isFlinging;
    final mapIdle = bridge.isMapIdle();
    if (isMapRenderSettled(
      styleLoaded: _style.isLoaded,
      mapIdle: mapIdle,
      cameraMoving: cameraMoving,
      flingAnimating: flingAnimating,
    )) {
      widget.onMapIdle?.call();

      return;
    }
    if (!shouldScheduleFrame(
      needsRepaint: needsRepaint,
      cameraMoving: cameraMoving,
      flingAnimating: flingAnimating,
      supportsEventDrivenRendering: bridge.supportsEventDrivenRendering,
      styleLoaded: _style.isLoaded,
      mapIdle: mapIdle,
    )) {
      return;
    }
    final needsContinuousFrame = needsRepaint || cameraMoving || flingAnimating;
    final interval = needsContinuousFrame
        ? const Duration(milliseconds: 16)
        : const Duration(milliseconds: 150);
    _renders.scheduleRepaint(interval);
  }

  void _onNativeRenderRequested() {
    if (!mounted || !_initialized) return;
    _renders.scheduleNativeRender();
  }

  void _finishScheduledRender() {
    _emitProgrammaticCameraIdleIfSettled();
    if (isMapRenderSettled(
      styleLoaded: _style.isLoaded,
      mapIdle: _bridge.isMapIdle(),
      cameraMoving: _bridge.isCameraMoving(),
      flingAnimating: _gestures.isFlinging,
    )) {
      widget.onMapIdle?.call();

      return;
    }
    scheduleRepaint();
  }

  void _onProgrammaticCameraChange() {
    if (!mounted || !_initialized) return;
    _gestures.stopFling();
    _programmaticCameraIdlePending = true;
    // Coalesce camera updates and native render requests into one frame.
    _renders.scheduleNativeRender(force: true);
  }

  void _emitProgrammaticCameraIdleIfSettled() {
    if (!_programmaticCameraIdlePending || _bridge.isCameraMoving()) return;
    _programmaticCameraIdlePending = false;
    widget.onCameraIdle?.call();
  }

  @override
  void renderGesture() {
    // Leave startup snapshots to the synchronous initialization pump.
    if (!_initialized || !_rendered) return;
    if (!_renders.isAppActive) {
      _renders.deferToResume();

      return;
    }
    final bridge = _bridge;
    final usesAsyncRendering = bridge.supportsAsyncRendering;
    NativeFrameSnapshotLease? acquiredSnapshot;
    if (usesAsyncRendering) {
      final pendingSnapshot = _pendingFrameSnapshot;
      if (pendingSnapshot?.isActive ?? false) {
        // Repaint an applied snapshot without advancing frame state again.
        _gpuFrame.value++;
        bridge.renderFrameAsync();

        return;
      }
      _pendingFrameSnapshot = null;
      acquiredSnapshot = bridge.acquireFrameSnapshot();
      if (acquiredSnapshot == null) {
        bridge.renderFrameAsync();

        return;
      }
      if (acquiredSnapshot.generation == _lastProcessedFrameGeneration) {
        acquiredSnapshot.release();
        bridge.renderFrameAsync();

        return;
      }
      _pendingFrameSnapshot = acquiredSnapshot;
    } else {
      bridge.frameBegin();
      bridge.renderFrame();
      bridge.frameEnd();
    }
    _applyingFrameSnapshot = true;
    try {
      final wasStyleLoaded = _style.isLoaded;
      _updateStyleLoadedState();
      final controller = _controller;
      final cameraChanged =
          controller?.notifyCameraChanged(
            notifyListeners: widget.trackCameraPosition,
            viewportChanged: _viewportNotificationPending,
          ) ??
          false;
      _viewportNotificationPending = false;
      final nextZoom =
          controller?.cameraPosition?.zoom ?? _bridge.getCameraZoom();
      _gpuRenderer?.zoom = nextZoom;
      _gpuRenderer?.frameSeq++;
      final labelsChanged = _labels.syncFromNative(bridge);
      final nextNativeCommandLayerIndices = _gpuRenderer!.commandLayerIndices(
        bridge.frameGetMetadata(),
      );
      final spriteAtlasChanged = _labels.hasDifferentSpriteAtlas(
        _style.spriteAtlas,
      );
      final labelsNeedProjection =
          labelsChanged ||
          spriteAtlasChanged ||
          (cameraChanged && _labels.entries.isNotEmpty);
      if (labelsNeedProjection) {
        _labels.cacheScreenPositions(bridge, _style.spriteAtlas);
      }
      final usesSingleGpuSurface =
          widget.gpuMapRenderCallback != null ||
          widget.gpuRenderCallback != null ||
          widget.symbolCompositingMode == .fastOverlay;
      final nextSymbolGpuStratumSlots = usesSingleGpuSurface
          ? const <int>[0]
          : symbolGpuStratumSlots(
              _labels.symbolLayerIndices,
              nativeCommandLayerIndices: nextNativeCommandLayerIndices,
            );
      final symbolGpuTopologyChanged = !listEquals(
        _symbolGpuStratumSlots,
        nextSymbolGpuStratumSlots,
      );
      _nativeCommandLayerIndices = nextNativeCommandLayerIndices;
      _symbolGpuStratumSlots = nextSymbolGpuStratumSlots;
      if (cameraChanged && widget.onCameraMove != null) {
        final pos = controller?.cameraPosition;
        if (pos != null) widget.onCameraMove?.call(pos);
      }
      if (acquiredSnapshot != null) {
        _lastProcessedFrameGeneration = acquiredSnapshot.generation;
      }
      _gpuFrame.value++;
      if (!wasStyleLoaded && _style.isLoaded) {
        setState(() {});
      } else {
        if (labelsChanged || spriteAtlasChanged || symbolGpuTopologyChanged) {
          _symbolVersion.value++;
        } else if (labelsNeedProjection) {
          _symbolLayoutVersion.value++;
        }
        if (cameraChanged &&
            (widget.compassEnabled || widget.scaleControlEnabled)) {
          _controlsVersion.value++;
        }
      }
      // Queue native work after all synchronous frame state has been read.
      if (usesAsyncRendering) {
        bridge.renderFrameAsync();
      }
    } catch (_) {
      if (identical(_pendingFrameSnapshot, acquiredSnapshot)) {
        _pendingFrameSnapshot = null;
      }
      acquiredSnapshot?.release();
      rethrow;
    } finally {
      _finishApplyingFrameSnapshot();
    }
  }

  void _onFrameSnapshotReleased(NativeFrameSnapshotLease snapshot) {
    if (identical(_pendingFrameSnapshot, snapshot)) {
      _pendingFrameSnapshot = null;
    }
  }

  NativeFrameSnapshotLease? _frameSnapshotForPaint() => _pendingFrameSnapshot;

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scaleGesturesDisabled =
        !widget.scrollGesturesEnabled &&
        !widget.zoomGesturesEnabled &&
        !widget.rotateGesturesEnabled &&
        !widget.tiltGesturesEnabled;
    final scaleGesturesWereEnabled =
        oldWidget.scrollGesturesEnabled ||
        oldWidget.zoomGesturesEnabled ||
        oldWidget.rotateGesturesEnabled ||
        oldWidget.tiltGesturesEnabled;
    final flingDisabled =
        !widget.scrollGesturesEnabled || !widget.gestureOptions.flingEnabled;
    if ((scaleGesturesWereEnabled && scaleGesturesDisabled) ||
        (flingDisabled && _gestures.isFlinging)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scaleGesturesStillDisabled =
            !widget.scrollGesturesEnabled &&
            !widget.zoomGesturesEnabled &&
            !widget.rotateGesturesEnabled &&
            !widget.tiltGesturesEnabled;
        if (scaleGesturesStillDisabled) {
          _gestures.cancelScaleGestureAndEndGesture();
        }
        if (!widget.scrollGesturesEnabled ||
            !widget.gestureOptions.flingEnabled) {
          _gestures.cancelFlingAndEndGesture();
        }
      });
    }
    if (_initialized && oldWidget.styleString != widget.styleString) {
      final controller = _controller;
      if (controller != null) {
        unawaited(
          controller.setStyle(widget.styleString).catchError((
            Object error,
            StackTrace stackTrace,
          ) {
            debugPrint(
              '[MapLibreMap] style update failed: $error\n$stackTrace',
            );
          }),
        );
      }
      return;
    }
    if (!_initialized || !_style.isLoaded) return;
    if (oldWidget.cameraTargetBounds == widget.cameraTargetBounds &&
        oldWidget.minMaxZoomPreference == widget.minMaxZoomPreference &&
        oldWidget.minMaxTiltPreference == widget.minMaxTiltPreference) {
      return;
    }
    _applyCameraConstraints();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_initialized) return;
      renderGesture();
      scheduleRepaint();
    });
  }

  @override
  void dispose() {
    _initialized = false;
    WidgetsBinding.instance.removeObserver(this);
    _macosTrackpadTilt?.dispose();
    _renders.dispose();
    _gestures.dispose();
    _controller?.dispose();
    _controller = null;
    _pendingFrameSnapshot?.release();
    _pendingFrameSnapshot = null;
    if (_hasBridge) {
      _hasBridge = false;
      _bridge.destroy();
    }
    _gpuRenderer?.dispose();
    _gpuRenderer = null;
    _gpuStratumResources.dispose();
    _gpuFrame.dispose();
    _symbolVersion.dispose();
    _symbolLayoutVersion.dispose();
    _controlsVersion.dispose();
    _labels.reset();
    _style.dispose();
    _viewport.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _renders.setAppActive(state == .resumed);

  Widget _buildRenderedMap(Size screenSize) {
    if (!_rendered) return const SizedBox.expand();

    return _MapLayerComposition(
      options: widget,
      screenSize: screenSize,
      bridge: _bridge,
      gpuRenderer: _gpuRenderer!,
      resources: _gpuStratumResources,
      viewport: _viewport,
      labels: _labels,
      symbolLayoutVersion: _symbolLayoutVersion,
      gpuFrame: _gpuFrame,
      nativeCommandLayerIndices: _nativeCommandLayerIndices,
      gpuRenderingAllowed: _gpuRenderingAllowed,
      frameSnapshotProvider: _frameSnapshotForPaint,
      onFrameSnapshotReleased: _onFrameSnapshotReleased,
    );
  }

  void _emitMapClick(Offset localPosition, OnMapClickCallback? callback) {
    if (!_initialized || callback == null) return;
    try {
      final coordinate = _bridge.screenToLatLon(
        localPosition.dx,
        localPosition.dy,
      );
      callback(
        .new(localPosition.dx, localPosition.dy),
        .new(coordinate.latitude, coordinate.longitude),
      );
    } on UnsupportedError catch (error) {
      debugPrint('[MapLibreMap] map click unavailable: $error');
    }
  }

  @override
  MaplibreBridge? get gestureBridge =>
      mounted && _initialized && _rendered ? _bridge : null;

  @override
  MapGestureSettings get gestureSettings => (
    scrollEnabled: widget.scrollGesturesEnabled,
    zoomEnabled: widget.zoomGesturesEnabled,
    rotateEnabled: widget.rotateGesturesEnabled,
    tiltEnabled: widget.tiltGesturesEnabled,
    doubleClickZoomEnabled: widget.doubleClickZoomEnabled,
  );

  @override
  MapGestureOptions get gestureOptions => widget.gestureOptions;

  @override
  Size get logicalMapSize => _viewport.logicalSize;

  @override
  void beginCameraGesture() {
    _programmaticCameraIdlePending = false;
    _controller?.notifyCameraGestureStarted();
  }

  @override
  void endCameraGesture() {
    widget.onCameraIdle?.call();
    scheduleRepaint();
  }

  @override
  Widget build(context) => LayoutBuilder(
    builder: (context, constraints) {
      final logicalSize = mapLayoutSize(constraints);
      if (logicalSize == null) return const SizedBox.shrink();

      final initializationError = _initializationError;
      if (initializationError != null) {
        return widget.errorBuilder?.call(context, initializationError) ??
            const SizedBox.shrink();
      }

      final dpr = MediaQuery.devicePixelRatioOf(context);
      _scheduleViewportUpdate(logicalSize, dpr);
      _scheduleMacosTrackpadTiltRegionUpdate();

      return ClipRect(
        child: Stack(
          fit: .expand,
          clipBehavior: .hardEdge,
          children: [
            const SizedBox.expand(),
            _MapGestureRegion(
              regionKey: _gestureRegionKey,
              gestures: _gestures,
              settings: gestureSettings,
              onTap: widget.onMapClick == null
                  ? null
                  : (position) => _emitMapClick(position, widget.onMapClick),
              onLongPress: widget.onMapLongClick == null
                  ? null
                  : (position) =>
                        _emitMapClick(position, widget.onMapLongClick),
              child: ValueListenableBuilder(
                valueListenable: _symbolVersion,
                builder: (context, _, _) => _buildRenderedMap(logicalSize),
              ),
            ),
            if (!_style.isLoaded && widget.loadingBuilder != null)
              IgnorePointer(
                child: widget.loadingBuilder!(
                  context,
                  widget.foregroundLoadColor,
                ),
              ),
            ValueListenableBuilder(
              valueListenable: _controlsVersion,
              builder: (context, _, _) => MapLibreMapControls(
                mapSize: logicalSize,
                controller: _controller,
                compassEnabled: widget.compassEnabled,
                logoEnabled: widget.logoEnabled,
                logoViewPosition: widget.logoViewPosition,
                logoViewMargins: widget.logoViewMargins,
                compassViewPosition: widget.compassViewPosition,
                compassViewMargins: widget.compassViewMargins,
                attributionButtonEnabled: widget.attributionButtonEnabled,
                attributionButtonPosition: widget.attributionButtonPosition,
                attributionButtonMargins: widget.attributionButtonMargins,
                onAttributionLinkTap: widget.onAttributionLinkTap,
                scaleControlEnabled: widget.scaleControlEnabled,
                scaleControlPosition: widget.scaleControlPosition,
                scaleControlUnit: widget.scaleControlUnit,
                scaleControlMargins: widget.scaleControlMargins,
                scaleControlMaxWidth: widget.scaleControlMaxWidth,
                scaleControlAvoidLogo: widget.scaleControlAvoidLogo,
                scaleControlLogoOffset: widget.scaleControlLogoOffset,
                compassBuilder: widget.compassBuilder,
                logoBuilder: widget.logoBuilder,
                attributionButtonBuilder: widget.attributionButtonBuilder,
                attributionDialogBuilder: widget.attributionDialogBuilder,
                scaleControlBuilder: widget.scaleControlBuilder,
              ),
            ),
          ],
        ),
      );
    },
  );

  void _scheduleMacosTrackpadTiltRegionUpdate() {
    final registration = _macosTrackpadTilt;
    if (registration == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box =
          _gestureRegionKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero);
      registration.updateRegion(
        origin & box.size,
        enabled: widget.tiltGesturesEnabled,
      );
    });
  }
}

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
  Completer<void>? _mutationBarrier;

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

  Future<void> _releaseFrameSnapshotBeforeMutation() {
    if (_applyingFrameSnapshot) {
      _releaseSnapshotAfterApply = true;

      return (_mutationBarrier ??= .new()).future;
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
    final barrier = _mutationBarrier;
    _mutationBarrier = null;
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

  void _updateMapState(VoidCallback update) => setState(update);

  @override
  void scheduleRepaint() => _scheduleRepaint();

  @override
  void renderGesture() => _renderFrame();

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

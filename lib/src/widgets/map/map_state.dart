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
  final _frameState = ValueNotifier<MapFrameState?>(null);
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
  late final ExternalCamera _externalCamera;
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
    _externalCamera = .new(
      canApply: () => mounted && _initialized && _renders.isAppActive,
      beforeApply: _releaseFrameSnapshotBeforeMutation,
      apply: (camera) {
        _bridge.setCameraFull(
          camera.target.latitude,
          camera.target.longitude,
          camera.zoom,
          camera.bearing,
          camera.tilt,
        );
        _onProgrammaticCameraChange();
      },
      schedule: (callback) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback());
        WidgetsBinding.instance.scheduleFrame();
      },
      onError: (error, stackTrace) => FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'maplibre_flutter_gpu',
          context: ErrorDescription('while applying an external camera'),
        ),
      ),
    );
    _externalCamera.update(widget.cameraPosition);
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
    _externalCamera.reapply();
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

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_initialized) _ensureFrameMetadataSupport();
    final cameraControlled = widget.cameraPosition != null;
    final wasCameraControlled = oldWidget.cameraPosition != null;
    _externalCamera.update(widget.cameraPosition);
    if (cameraControlled && !wasCameraControlled) {
      _gestures.stopFling();
      _gestures.cancelScaleGestureAndEndGesture();
      _controller?.cancelCameraUpdates();
    }
    final scaleGesturesDisabled =
        cameraControlled ||
        (!widget.scrollGesturesEnabled &&
            !widget.zoomGesturesEnabled &&
            !widget.rotateGesturesEnabled &&
            !widget.tiltGesturesEnabled);
    final scaleGesturesWereEnabled =
        !wasCameraControlled &&
        (oldWidget.scrollGesturesEnabled ||
            oldWidget.zoomGesturesEnabled ||
            oldWidget.rotateGesturesEnabled ||
            oldWidget.tiltGesturesEnabled);
    final flingDisabled =
        cameraControlled ||
        !widget.scrollGesturesEnabled ||
        !widget.gestureOptions.flingEnabled;
    if ((scaleGesturesWereEnabled && scaleGesturesDisabled) ||
        (flingDisabled && _gestures.isFlinging)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scaleGesturesStillDisabled =
            widget.cameraPosition != null ||
            (!widget.scrollGesturesEnabled &&
                !widget.zoomGesturesEnabled &&
                !widget.rotateGesturesEnabled &&
                !widget.tiltGesturesEnabled);
        if (scaleGesturesStillDisabled) {
          _gestures.cancelScaleGestureAndEndGesture();
        }
        if (widget.cameraPosition != null ||
            !widget.scrollGesturesEnabled ||
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
        oldWidget.cameraConstrainMode == widget.cameraConstrainMode &&
        oldWidget.minMaxZoomPreference == widget.minMaxZoomPreference &&
        oldWidget.minMaxTiltPreference == widget.minMaxTiltPreference) {
      return;
    }
    _applyCameraConstraints();
    _externalCamera.reapply();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_initialized) return;
      renderGesture();
      scheduleRepaint();
    });
  }

  void _ensureFrameMetadataSupport() {
    if (widget.onFrame != null || widget.overlayBuilder != null) {
      _bridge.requireFrameCameraSupport();
    }
  }

  @override
  void dispose() {
    _initialized = false;
    WidgetsBinding.instance.removeObserver(this);
    _macosTrackpadTilt?.dispose();
    _renders.dispose();
    _gestures.dispose();
    _externalCamera.dispose();
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
    _frameState.dispose();
    _symbolVersion.dispose();
    _symbolLayoutVersion.dispose();
    _controlsVersion.dispose();
    _labels.reset();
    _style.dispose();
    _viewport.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_renders.setAppActive(state == .resumed) && state == .resumed) {
      _externalCamera.reapply();
    }
  }

  @override
  MaplibreBridge? get gestureBridge =>
      mounted && _initialized && _rendered && widget.cameraPosition == null
      ? _bridge
      : null;

  @override
  MapGestureSettings get gestureSettings => (
    scrollEnabled:
        widget.cameraPosition == null && widget.scrollGesturesEnabled,
    zoomEnabled: widget.cameraPosition == null && widget.zoomGesturesEnabled,
    rotateEnabled:
        widget.cameraPosition == null && widget.rotateGesturesEnabled,
    tiltEnabled: widget.cameraPosition == null && widget.tiltGesturesEnabled,
    doubleClickZoomEnabled: widget.cameraPosition == null
        ? widget.doubleClickZoomEnabled
        : false,
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
  Widget build(BuildContext context) => _buildMap(context);
}

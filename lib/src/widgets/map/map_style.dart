part of '../maplibre_map.dart';

extension _MapStyle on _MapLibreMapState {
  void _applyCameraConstraints() {
    final bounds = widget.cameraTargetBounds.bounds;
    final zoom = widget.minMaxZoomPreference;
    final tilt = widget.minMaxTiltPreference;
    _bridge.setCameraConstrainMode(widget.cameraConstrainMode);
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

  // Native keeps the previous values across style loads, so the widget's
  // current options or MapLibre's defaults are applied every time.
  void _applyTileOptions() {
    _bridge.setTileLod(widget.tileLodOptions ?? TileLodOptions.defaults);
    _bridge.setPrefetchZoomDelta(widget.prefetchZoomDelta ?? 4);
  }

  void _updateStyleLoadedState() {
    if (_style.isLoaded || !_bridge.isStyleLoaded()) return;
    _style.markLoaded();
    _prewarmStylePipelines();
    _applyCameraConstraints();
    _applyTileOptions();
    _externalCamera.reapply();
    widget.onStyleLoadedCallback?.call();
  }

  // The style's remaining pipelines are created one per idle event-loop turn
  // instead of during the first frame that draws each layer type. Cold shader
  // compilation can take tens of milliseconds per pipeline, so a gesture that
  // starts meanwhile pauses the warmup until the map is idle again. Older
  // native libraries without the style query keep creating pipelines on first
  // use.
  void _prewarmStylePipelines() {
    final renderer = _gpuRenderer;
    if (renderer == null) return;
    final String? styleJson;
    try {
      styleJson = _bridge.getStyle();
    } on StateError {
      return;
    }
    if (styleJson == null) return;
    final pending = renderer.missingStylePipelines(styleJson);
    _pipelineWarmup = pending;
    if (pending.isNotEmpty) _scheduleIdlePipelineWarmup(pending);
  }

  void _scheduleIdlePipelineWarmup(List<RenderPipelineKey> pending) {
    SchedulerBinding.instance.scheduleTask(() {
      final renderer = _gpuRenderer;
      if (!mounted ||
          !_initialized ||
          renderer == null ||
          !identical(_pipelineWarmup, pending) ||
          pending.isEmpty) {
        return;
      }
      renderer.createPipeline(pending.removeLast());
      if (pending.isEmpty) {
        _pipelineWarmup = null;

        return;
      }
      _scheduleIdlePipelineWarmup(pending);
    }, Priority.idle);
  }

  void _loadSpriteAtlas(String styleSource, {String? baseStyleUrl}) =>
      unawaited(
        _style
            .loadSpriteAtlas(
              styleSource,
              baseStyleUrl: baseStyleUrl,
              isAlive: () => mounted && _initialized,
            )
            .then((adopted) {
              if (!adopted) return;
              if (_renders.isRenderingPaused) {
                _renders.scheduleNativeRender(force: true);

                return;
              }
              _updateMapState(
                () => _labels.cacheScreenPositions(_bridge, _style.spriteAtlas),
              );
            }),
      );

  Future<void> _onProgrammaticStyleChange(
    String styleString,
    String resolvedStyle,
  ) async {
    if (!mounted || !_initialized) {
      throw StateError('MapLibreMap is not available for a style change');
    }
    _updateMapState(() {
      _style.beginStyleChange();
      _labels.reset();
    });
    _pipelineWarmup = null;
    _gpuRenderer?.fillExtrusions.styleChanged();
    _programmaticCameraIdlePending = false;
    _bridge.setStyle(resolvedStyle);
    _loadSpriteAtlas(resolvedStyle, baseStyleUrl: styleString);
    renderGesture();
    scheduleRepaint();
  }

  void _onProgrammaticStyleMutation() {
    if (!mounted || !_initialized) return;
    _gpuRenderer?.fillExtrusions.layersChanged();
    renderGesture();
    scheduleRepaint();
  }
}

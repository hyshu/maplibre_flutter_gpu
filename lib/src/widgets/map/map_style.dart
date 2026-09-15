part of '../maplibre_map.dart';

extension _MapStyle on _MapLibreMapState {
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
            _updateMapState(() {
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
    _updateMapState(() {
      _style.beginStyleChange();
      _labels.reset();
    });
    _programmaticCameraIdlePending = false;
    _bridge.setStyle(resolvedStyle);
    _loadSpriteAtlas(resolvedStyle, baseStyleUrl: styleString);
    renderGesture();
    scheduleRepaint();
  }

  void _onProgrammaticStyleMutation() {
    if (!mounted || !_initialized) return;
    renderGesture();
    scheduleRepaint();
  }
}

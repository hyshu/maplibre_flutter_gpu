part of '../maplibre_map.dart';

extension _MapView on _MapLibreMapState {
  Widget _buildMap(BuildContext context) => LayoutBuilder(
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

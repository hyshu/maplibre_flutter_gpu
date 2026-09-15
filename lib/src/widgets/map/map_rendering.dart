part of '../maplibre_map.dart';

extension _MapRendering on _MapLibreMapState {
  void _scheduleRepaint() {
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

  void _renderFrame() {
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
        _updateMapState(() {});
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
}

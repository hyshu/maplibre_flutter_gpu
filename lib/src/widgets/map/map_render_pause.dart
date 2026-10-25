part of '../maplibre_map.dart';

extension _MapRenderPause on _MapLibreMapState {
  Future<void> _onRenderingPausedChanged(bool paused) {
    if (_gpuPaintingDepth != 0) {
      throw StateError(
        'setRenderingPaused cannot change state inside a GPU render callback. '
        'Schedule the change with addPostFrameCallback instead.',
      );
    }
    if (!_bridge.supportsAsyncRenderingPause) {
      throw UnsupportedError(
        'The native library does not support asynchronous rendering pause. '
        'Rebuild the native library to use setRenderingPaused.',
      );
    }

    return _renderPause.setPaused(paused);
  }

  void _onGpuPaintingChanged(bool painting) {
    _gpuPaintingDepth += painting ? 1 : -1;
    assert(_gpuPaintingDepth >= 0);
  }

  void _prepareRenderingResume() {
    final camera = widget.cameraPosition;
    if (camera == null) return;
    _bridge.setCameraFull(
      camera.target.latitude,
      camera.target.longitude,
      camera.zoom,
      camera.bearing,
      camera.tilt,
    );
    _externalCamera.markApplied(camera);
    _programmaticCameraIdlePending = true;
  }

  void _onGpuFramePainted() {
    final sequence = _gpuRenderer?.frameSeq;
    if (sequence == null ||
        !_renders.isRenderingAllowed ||
        sequence <= _frozenFrameSequence ||
        !_gpuStratumResources.hasPaintedFrame(sequence)) {
      return;
    }
    _renderFreeze.reveal();
  }
}

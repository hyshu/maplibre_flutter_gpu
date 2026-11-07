part of '../maplibre_map.dart';

extension _MapMemory on _MapLibreMapState {
  void _configureMemoryManagement() {
    _memory?.dispose();
    final snapshot = _bridge.readMemorySnapshot();
    final mobile =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    final policy = MapMemoryPolicy(
      MapMemoryBudget.forDevice(
        physicalBytes: snapshot.physicalBytes,
        mobile: mobile,
      ),
    );
    if (!_bridge.supportsMemoryManagement) {
      debugPrint(
        '[MapLibreMap] Native memory controls unavailable. '
        'Rebuild the native library to enable native cache limits.',
      );
    }
    _memory = MapMemoryController(
      policy: policy,
      readSnapshot: _bridge.readMemorySnapshot,
      onDiagnostics: const bool.fromEnvironment('MAPLIBRE_MEMORY_DIAGNOSTICS')
          ? debugPrint
          : null,
      beforeMutation: _releaseFrameSnapshotBeforeMutation,
      applyBudget: (budget) {
        final accepted = _bridge.setTileCacheSize(budget.nativeTileCount);
        if (_bridge.supportsMemoryManagement && !accepted) {
          throw StateError('Native map rejected the memory budget');
        }
        _gpuRenderer?.updateCacheBudget(budget.gpu);
        _gpuRenderer?.fillExtrusions.updateMemoryBudget(budget.customizerBytes);
        _renders.scheduleNativeRender(force: true);

        return accepted;
      },
      trimCaches: () {
        // A visible map keeps what its current frame replays, so a warning
        // costs an eviction pass instead of rebuilding the whole scene. A
        // hidden map releases everything but the image shown on return.
        final visible = mounted && _renders.isAppActive;
        _gpuRenderer?.reduceMemoryUse(retainCurrentFrame: visible);
        _gpuStratumResources.reduceMemoryUse(preserveLastImage: true);
        if (!visible) SymbolGlyphAtlas.clear();
        final accepted = _bridge.reduceMemoryUse();
        if (_bridge.supportsMemoryManagement && !accepted) {
          throw StateError('Native map rejected memory reclamation');
        }
        _renders.scheduleNativeRender(force: true);
        _gpuFrame.value++;
      },
      isActive: () => mounted && _initialized && _renders.isAppActive,
      onError: (error, stackTrace) => FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'maplibre_flutter_gpu',
          context: ErrorDescription('while reducing map memory use'),
        ),
      ),
    )..start();
  }
}

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
      readSnapshot: () {
        final memory = _bridge.readMemorySnapshot();
        if (const bool.fromEnvironment('MAPLIBRE_MEMORY_DIAGNOSTICS')) {
          debugPrint(
            '[MapMemory] physical=${memory.physicalBytes} '
            'available=${memory.availableBytes} usage=${memory.usageBytes} '
            'nativeTiles=${policy.budget.nativeTileCount} '
            'gpuBytes=${policy.budget.gpu.regularMaxBytes + policy.budget.gpu.fillExtrusionMaxBytes} '
            'customizerBytes=${policy.budget.customizerBytes}',
          );
        }

        return memory;
      },
      beforeMutation: _releaseFrameSnapshotBeforeMutation,
      applyBudget: (budget) {
        final accepted = _bridge.setTileCacheSize(budget.nativeTileCount);
        if (_bridge.supportsMemoryManagement && !accepted) {
          throw StateError('Native map rejected the memory budget');
        }
        _gpuRenderer?.updateCacheBudget(budget.gpu);
        _gpuRenderer?.fillExtrusions.updateMemoryBudget(budget.customizerBytes);
        _renders.scheduleNativeRender(force: true);
      },
      trimCaches: () {
        _gpuRenderer?.reduceMemoryUse();
        _gpuStratumResources.reduceMemoryUse();
        SymbolGlyphAtlas.clear();
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

part of '../maplibre_ffi.dart';

/// Optional native memory measurements and cache reclamation.
mixin MaplibreBridgeMemoryBindings {
  BridgeSessionLifecycle get _lifecycle;
  NativeSymbolTable get _symbols;

  Uint64VoidD? _getPhysicalMemory;
  Uint64VoidD? _getAvailableMemory;
  Uint64VoidD? _getMemoryUsage;
  Int32Uint32D? _setTileCacheSize;
  Int32VoidD? _reduceMemoryUse;

  /// Whether all memory operations are provided by the loaded native library.
  bool get supportsMemoryManagement => _symbols.provides('memory management');

  /// Returns byte measurements, using zero for unavailable measurements.
  ///
  /// Apple usage includes the physical footprint. Other platforms report RSS.
  /// Available memory is advisory and may change immediately after this call.
  MapMemorySnapshot readMemorySnapshot() {
    if (!supportsMemoryManagement) return const MapMemorySnapshot();

    return MapMemorySnapshot(
      physicalBytes: _getPhysicalMemory!(),
      availableBytes: _getAvailableMemory!(),
      usageBytes: _getMemoryUsage!(),
    );
  }

  /// Caps unused native tiles per source. Zero disables their retention.
  ///
  /// Returns false when unsupported or the active session rejects the change.
  bool setTileCacheSize(int tiles) {
    RangeError.checkValueInInterval(tiles, 0, 0xffffffff, 'tiles');
    _lifecycle.ensureActive();
    if (!supportsMemoryManagement) return false;

    return _setTileCacheSize!(tiles) != 0;
  }

  /// Requests reclamation without releasing tiles needed by the current frame.
  ///
  /// Returns true when accepted. A leased frame may delay native reclamation.
  bool reduceMemoryUse() {
    _lifecycle.ensureActive();
    if (!supportsMemoryManagement) return false;

    return _reduceMemoryUse!() != 0;
  }
}

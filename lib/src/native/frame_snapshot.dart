part of 'maplibre_ffi.dart';

/// Pins one native command-export snapshot until Flutter GPU records it.
///
/// Sharing the lease across frame consumers keeps labels, camera state, and
/// command pointers on one native generation.
final class NativeFrameSnapshotLease {
  new _(MaplibreBridgeFrameBindings bridge, this.generation) : _bridge = bridge;

  MaplibreBridgeFrameBindings? _bridge;

  /// Monotonic native identity. Zero is reserved for "no snapshot".
  final int generation;

  /// Whether this lease has not been released.
  bool get isActive => _bridge != null;

  /// Forwards at most one release to native.
  void release() {
    final bridge = _bridge;
    if (bridge == null) return;
    _bridge = null;
    bridge.frameRelease(generation);
  }
}

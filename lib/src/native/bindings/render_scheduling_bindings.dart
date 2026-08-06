part of '../maplibre_ffi.dart';

/// Event-driven wake-ups from the native renderer.
///
/// The bridge owns the registered [NativeCallable] and keeps its lifetime
/// within that of the native session.
mixin MaplibreBridgeRenderSchedulingBindings {
  BridgeSessionLifecycle get _lifecycle;

  // The bridge resolves these optional native callbacks and separately owns
  // the NativeCallable registered through them.
  SetRenderRequestCallbackD? _setRenderRequestCallback;
  Int32VoidD? _processEvents;
  Int32VoidD? _frameNeedsRepaint;

  /// Unregisters and closes the native render request handler.
  void clearRenderRequestHandler();

  /// Whether native can notify Dart when rendering work becomes available.
  bool get supportsEventDrivenRendering =>
      _setRenderRequestCallback != null &&
      _processEvents != null &&
      _frameNeedsRepaint != null;

  /// Checks for pending MapLibre work without producing a GPU frame.
  ///
  /// Returns true when rendering work is pending. Also returns true when the
  /// native check is unavailable so the caller renders conservatively.
  bool processEvents() {
    _lifecycle.ensureActive();
    final process = _processEvents;

    return process == null || process() != 0;
  }

  /// Whether the current native frame contains a time-dependent transition.
  ///
  /// Returns false when the native check is unavailable.
  bool get frameNeedsRepaint {
    _lifecycle.ensureActive();
    final callback = _frameNeedsRepaint;

    return callback != null && callback() != 0;
  }
}

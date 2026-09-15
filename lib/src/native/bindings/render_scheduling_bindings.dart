part of '../maplibre_ffi.dart';

/// Event-driven wake-ups from the native renderer.
///
/// The bridge owns the registered [NativeCallable] and keeps its lifetime
/// within that of the native session.
mixin MaplibreBridgeRenderSchedulingBindings {
  BridgeSessionLifecycle get _lifecycle;

  // The callback must close only after native stops invoking it.
  SetRenderRequestCallbackD? _setRenderRequestCallback;
  Int32VoidD? _processEvents;
  Int32VoidD? _frameNeedsRepaint;

  NativeCallable<RenderRequestN>? _renderRequestCallable;

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

  /// Whether the map is fully rendered and settled.
  ///
  /// A settled map has no pending tiles or transitions after its latest frame.
  bool isMapIdle() {
    _lifecycle.ensureActive();

    return _isIdle() != 0;
  }

  late final Int32VoidD _isIdle;

  /// Installs an isolate-safe native wake handler.
  ///
  /// Native may invoke the function pointer from any thread. [NativeCallable]
  /// posts the callback to the owning isolate. Does nothing when native render
  /// notifications are unavailable.
  void setRenderRequestHandler(VoidCallback handler) {
    _lifecycle.ensureActive();
    final register = _setRenderRequestCallback;
    if (register == null) return;
    clearRenderRequestHandler();
    final callable = NativeCallable<RenderRequestN>.listener(handler);
    _renderRequestCallable = callable;
    register(callable.nativeFunction);
  }

  /// Unregisters and closes the native render request handler.
  void clearRenderRequestHandler() {
    final callable = _renderRequestCallable;
    if (callable == null) return;
    _setRenderRequestCallback?.call(
      nullptr.cast<NativeFunction<RenderRequestN>>(),
    );
    _renderRequestCallable = null;
    callable.close();
  }
}

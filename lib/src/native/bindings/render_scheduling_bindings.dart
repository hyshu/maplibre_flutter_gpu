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
  Int32Int32D? _setRenderingPaused;
  SetRenderingPausedAsyncD? _setRenderingPausedAsync;

  NativeCallable<RenderRequestN>? _renderRequestCallable;

  /// Whether native supports per-session rendering suspension.
  bool get supportsRenderingPause => _setRenderingPaused != null;

  /// Whether render gate barriers can complete without blocking the isolate.
  bool get supportsAsyncRenderingPause => _setRenderingPausedAsync != null;

  /// Changes rendering state without waiting synchronously on the owner queue.
  ///
  /// Pausing immediately rejects new native frames, then cancels camera motion
  /// on the owner thread. Release any borrowed frame lease before awaiting this
  /// future. Resuming opens the native gate only after earlier owner work ends.
  /// Returns false if rejected, superseded, or disposed before completion.
  /// Throws [UnsupportedError] when the native library lacks this operation.
  Future<bool> setRenderingPausedAsync(bool paused) {
    _lifecycle.ensureActive();
    final update = _setRenderingPausedAsync;
    if (update == null) {
      throw UnsupportedError(
        'Asynchronous native rendering pause is unavailable',
      );
    }
    final result = Completer<bool>();
    late final NativeCallable<RenderingPauseCompletionN> callback;
    callback = NativeCallable<RenderingPauseCompletionN>.listener((int value) {
      callback.close();
      result.complete(value != 0);
    });
    try {
      update(paused ? 1 : 0, callback.nativeFunction);
    } catch (_) {
      callback.close();
      rethrow;
    }

    return result.future;
  }

  /// Sets the native render gate.
  ///
  /// A successful pause prevents new native frames, including queued async
  /// renders, and waits for earlier owner-thread work. Existing snapshot leases
  /// remain valid until explicitly released. Data mutations continue while
  /// paused. Resuming does not wait for owner work or request a frame.
  /// Throws [UnsupportedError] when the native library lacks this operation.
  bool setRenderingPaused(bool paused) {
    _lifecycle.ensureActive();
    final update = _setRenderingPaused;
    if (update == null) {
      throw UnsupportedError('Native rendering pause is unavailable');
    }

    return update(paused ? 1 : 0) != 0;
  }

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

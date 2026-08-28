/// Native status code for a successful session initialization.
const nativeInitSuccess = 0;

/// Native status code for a failed session initialization.
const nativeInitFailure = -1;

/// Native status code indicating that another session is active.
const nativeInitBusy = -2;

/// Tracks ownership of one native MapLibre session.
///
/// Only a successful initializer grants ownership. Disposal destroys the
/// native session only for its owner and always releases local resources.
class BridgeSessionLifecycle {
  /// Called after an operation verifies that the session is active.
  void Function()? onActivate;

  var _ownsNativeSession = false;
  var _disposed = false;

  /// Whether this instance owns the native session.
  bool get ownsNativeSession => _ownsNativeSession;

  /// Whether disposal has started.
  bool get disposed => _disposed;

  /// Runs [initializeNativeSession] and returns its native status code.
  ///
  /// Takes ownership only when the result is [nativeInitSuccess]. Throws a
  /// [StateError] after disposal or when this instance already owns a session.
  int initialize(int Function() initializeNativeSession) {
    if (_disposed) {
      throw StateError('MaplibreBridge initialized after dispose');
    }
    if (_ownsNativeSession) {
      throw StateError('MaplibreBridge is already initialized');
    }

    final result = initializeNativeSession();
    if (result == nativeInitSuccess) _ownsNativeSession = true;
    return result;
  }

  /// Verifies ownership of a session that has not been disposed.
  ///
  /// Calls [onActivate] after validation. Throws a [StateError] when the
  /// session is unavailable.
  void ensureActive() {
    if (_disposed) {
      throw StateError('MaplibreBridge used after dispose');
    }
    if (!_ownsNativeSession) {
      throw StateError('MaplibreBridge does not own the native map session');
    }
    onActivate?.call();
  }

  /// Disposes this lifecycle once.
  ///
  /// Calls [destroyNativeSession] only when this instance owns the session.
  /// [releaseLocalResources] runs even when native destruction throws.
  void dispose({
    required void Function() destroyNativeSession,
    required void Function() releaseLocalResources,
  }) {
    if (_disposed) return;
    _disposed = true;

    final shouldDestroyNativeSession = _ownsNativeSession;
    _ownsNativeSession = false;
    try {
      if (shouldDestroyNativeSession) destroyNativeSession();
    } finally {
      releaseLocalResources();
    }
  }
}

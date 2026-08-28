import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Routes native macOS three-finger trackpad swipes to one map region.
class MacosTrackpadTiltRegistration._({
  required final VoidCallback onStart,
  required final ValueChanged<double> onUpdate,
  required final VoidCallback onEnd,
}) {
  this {
    _registrations[id] = this;
    _installHandler();
  }

  static const _channel = MethodChannel(
    'dev.maplibre.flutter_gpu/macos_trackpad_tilt',
  );
  static final Map<int, MacosTrackpadTiltRegistration> _registrations = {};
  static var _nextId = 1;
  static var _handlerInstalled = false;

  /// Creates a registration on macOS and returns null on other platforms.
  static MacosTrackpadTiltRegistration? register({
    required VoidCallback onStart,
    required ValueChanged<double> onUpdate,
    required VoidCallback onEnd,
  }) {
    if (kIsWeb || defaultTargetPlatform != .macOS) return null;

    return ._(onStart: onStart, onUpdate: onUpdate, onEnd: onEnd);
  }

  final id = _nextId++;
  var _disposed = false;

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'trackpadTilt') return;
      final arguments = Map<Object?, Object?>.from(call.arguments as Map);
      final registration = _registrations[arguments['id'] as int?];
      if (registration == null) return;
      switch (arguments['phase']) {
        case 'start':
          registration.onStart();
        case 'update':
          final delta = arguments['deltaY'];
          if (delta is num) registration.onUpdate(delta.toDouble());
        case 'end':
          registration.onEnd();
      }
    });
  }

  /// Updates map bounds in logical coordinates relative to Flutter view.
  void updateRegion(Rect region, {required bool enabled}) {
    if (_disposed) return;
    unawaited(
      _channel
          .invokeMethod<void>('setTiltRegion', <String, Object>{
            'id': id,
            'x': region.left,
            'y': region.top,
            'width': region.width,
            'height': region.height,
            'enabled': enabled,
          })
          .catchError((_) {}),
    );
  }

  /// Stops native event routing for this map.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _registrations.remove(id);
    unawaited(
      _channel
          .invokeMethod<void>('removeTiltRegion', <String, Object>{'id': id})
          .catchError((_) {}),
    );
  }
}

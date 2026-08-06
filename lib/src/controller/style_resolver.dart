import 'dart:io';

import 'package:flutter/services.dart';

typedef MapStyleLoader = Future<String> Function(String path);

/// Resolves a style input to a URL or raw JSON accepted by MapLibre Native.
///
/// URLs and raw JSON pass through unchanged. Absolute paths become `file:`
/// URLs. Relative paths are loaded from the Flutter asset bundle.
Future<String> resolveMapStyleString(
  String styleString, {
  MapStyleLoader? assetLoader,
}) async {
  final trimmed = styleString.trimLeft();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(styleString, 'styleString', 'must not be empty');
  }
  if (trimmed.startsWith('{')) return styleString;

  final uri = Uri.tryParse(styleString);
  if (uri != null && uri.scheme == 'file') return styleString;
  if (uri != null && uri.hasScheme) return styleString;
  if (File(styleString).isAbsolute) return Uri.file(styleString).toString();

  return (assetLoader ?? rootBundle.loadString)(styleString);
}

/// Resolves the current style request, restarting if it changes while loading.
///
/// [requestedStyle] is checked again after each asynchronous load.
/// If it changed while loading, the stale result is discarded and
/// the new style is resolved instead.
///
/// Returns `null` if [isAlive] is `false`. Resolution errors are rethrown only
/// when the failed style is still current. Otherwise, the new style is tried.
Future<({String requested, String resolved})?> resolveRequestedStyle({
  required String Function() requestedStyle,
  required bool Function() isAlive,
  MapStyleLoader? assetLoader,
}) async {
  while (true) {
    final requested = requestedStyle();
    final String resolved;
    try {
      resolved = await resolveMapStyleString(
        requested,
        assetLoader: assetLoader,
      );
    } catch (_) {
      if (isAlive() && requested != requestedStyle()) continue;
      rethrow;
    }
    if (!isAlive()) return null;
    if (requested == requestedStyle()) {
      return (requested: requested, resolved: resolved);
    }
  }
}

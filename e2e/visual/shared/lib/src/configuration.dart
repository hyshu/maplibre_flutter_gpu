part of '../visual_e2e_shared.dart';

const String _visualE2eConfiguredSceneId = String.fromEnvironment(
  'VISUAL_E2E_SCENE',
  defaultValue: 'geometry',
);

const String _visualE2eConfiguredSceneIds = String.fromEnvironment(
  'VISUAL_E2E_SCENES',
);

const String visualE2eRunToken = String.fromEnvironment(
  'VISUAL_E2E_RUN_TOKEN',
  defaultValue: 'local',
);

/// Scenes compared between maplibre_gl and maplibre_flutter_gpu on mobile.
const List<String> visualE2eParitySceneIds = [
  'geometry',
  'text-symbol',
  'symbol-data-driven-paint',
  'symbol-paint-update',
  'symbol-line-pitch',
  'symbol-icon-effects',
  'symbol-layer-order',
  'symbol-z-order',
  'symbol-text-shaping',
  '3d-buildings',
  'mvt',
  'tilejson-mvt',
  'image-source',
  'geojson-url',
  'raster-jpeg',
  'raster-webp',
  'raster-tms',
  'wmts',
];

/// Offline scenes supported by the maplibre_flutter_gpu desktop fixture.
const List<String> visualE2eDesktopSceneIds = [
  'geometry',
  'text-symbol',
  '3d-buildings',
  'line-variants',
  'raster-pattern',
  'mvt',
  'mlt',
  'tilejson-mvt',
  'pmtiles-raster',
  'mbtiles-raster',
  'image-source',
  'geojson-url',
  'raster-jpeg',
  'raster-webp',
  'raster-tms',
  'wmts',
  'pmtiles-vector',
  'pmtiles-mlt',
  'mbtiles-vector',
  'mbtiles-mlt',
];

/// Desktop scenes that require an exact image baseline and command coverage.
const List<String> visualE2eStrictDesktopSceneIds = [
  'geometry',
  'text-symbol',
  '3d-buildings',
  'line-variants',
  'raster-pattern',
];

final _visualE2eSceneIds = <String>{
  ...visualE2eParitySceneIds,
  ...visualE2eDesktopSceneIds,
  'flutter-markers',
};

String? _visualE2eRuntimeSceneId;

/// Active scene selected by an explicit override, launch route, or Dart define.
String get visualE2eSceneId {
  final runtimeSceneId = _visualE2eRuntimeSceneId;
  if (runtimeSceneId != null) return runtimeSceneId;

  final routeSceneId = visualE2eSceneIdFromRoute(
    ui.PlatformDispatcher.instance.defaultRouteName,
  );

  return routeSceneId ?? _visualE2eConfiguredSceneId;
}

/// Ordered scenes configured for the current integration-test process.
///
/// Invalid or duplicate identifiers throw [ArgumentError].
List<String> get visualE2eSuiteSceneIds {
  if (_visualE2eConfiguredSceneIds.trim().isEmpty) {
    return [visualE2eSceneId];
  }

  return parseVisualE2eSceneIds(_visualE2eConfiguredSceneIds);
}

/// Sets the active scene for a test iteration. Passing null clears the override.
///
/// An unsupported identifier throws [ArgumentError].
void setVisualE2eRuntimeSceneId(String? sceneId) {
  if (sceneId != null && !_visualE2eSceneIds.contains(sceneId)) {
    throw ArgumentError.value(sceneId, 'sceneId', 'unknown visual E2E scene');
  }
  _visualE2eRuntimeSceneId = sceneId;
}

/// Parses a comma-separated, unique list of supported scene identifiers.
///
/// Empty, unsupported, or duplicate identifiers throw [ArgumentError].
List<String> parseVisualE2eSceneIds(String value) {
  final sceneIds = value
      .split(',')
      .map((sceneId) => sceneId.trim())
      .toList(growable: false);
  if (sceneIds.isEmpty || sceneIds.any((sceneId) => sceneId.isEmpty)) {
    throw ArgumentError.value(value, 'value', 'visual E2E scene list is empty');
  }
  final seen = <String>{};
  for (final sceneId in sceneIds) {
    if (!_visualE2eSceneIds.contains(sceneId)) {
      throw ArgumentError.value(sceneId, 'value', 'unknown visual E2E scene');
    }
    if (!seen.add(sceneId)) {
      throw ArgumentError.value(sceneId, 'value', 'duplicate visual E2E scene');
    }
  }

  return sceneIds;
}

/// Extracts a supported scene from a platform launch route.
///
/// Both `/visual-e2e/geometry` and `?scene=geometry` forms are accepted.
/// Unsupported or empty routes return null.
String? visualE2eSceneIdFromRoute(String route) {
  final trimmed = route.trim();
  if (trimmed.isEmpty || trimmed == '/') return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  final querySceneId = uri.queryParameters['scene'];
  if (querySceneId != null && _visualE2eSceneIds.contains(querySceneId)) {
    return querySceneId;
  }

  final segments = uri.pathSegments.where((value) => value.isNotEmpty).toList();
  final pathSceneId = segments.isEmpty ? uri.host : segments.last;
  if (_visualE2eSceneIds.contains(pathSceneId)) return pathSceneId;

  if (_visualE2eSceneIds.contains(trimmed)) return trimmed;

  return null;
}

const String _visualE2eZoomValue = String.fromEnvironment('VISUAL_E2E_ZOOM');

double? get visualE2eZoom => double.tryParse(_visualE2eZoomValue);

const String visualE2eReadyPrefix = 'VISUAL_E2E_READY';

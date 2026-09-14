part of '../visual_e2e_shared.dart';

typedef VisualMapBuilder = Widget Function(
  VisualScene scene,
  VoidCallback onMapIdle,
);

@immutable
class VisualCamera {
  const new({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    required this.bearing,
    required this.tilt,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final double bearing;
  final double tilt;
}

@immutable
class VisualScene {
  const new({
    required this.id,
    required this.styleJson,
    required this.camera,
    required this.backgroundColor,
  });

  final String id;
  final String styleJson;
  final VisualCamera camera;
  final Color backgroundColor;
}

Future<VisualScene> loadVisualScene() async {
  const cameras = <String, VisualCamera>{
    'geometry': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13.25,
      bearing: 17,
      tilt: 28,
    ),
    'text-symbol': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-data-driven-paint': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-paint-update': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-line-pitch': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13.9,
      bearing: 32,
      tilt: 45,
    ),
    'symbol-icon-effects': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 18,
      tilt: 28,
    ),
    'symbol-layer-order': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-z-order': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    'symbol-text-shaping': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 14.1,
      bearing: 0,
      tilt: 0,
    ),
    '3d-buildings': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 15.15,
      bearing: 28,
      tilt: 20,
    ),
    'line-variants': .new(
      latitude: 35.6832,
      longitude: 139.7671,
      zoom: 13.6,
      bearing: 0,
      tilt: 0,
    ),
    'raster-pattern': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13.2,
      bearing: 0,
      tilt: 0,
    ),
    'mvt': .new(latitude: 0, longitude: 0, zoom: 0, bearing: 0, tilt: 0),
    'tilejson-mvt': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'mlt': .new(latitude: 0, longitude: 0, zoom: 0, bearing: 0, tilt: 0),
    'pmtiles-raster': .new(
      latitude: 20,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'mbtiles-raster': .new(
      latitude: 20,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'image-source': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'geojson-url': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'raster-jpeg': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'raster-webp': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'raster-tms': .new(latitude: 0, longitude: 0, zoom: 1, bearing: 0, tilt: 0),
    'wmts': .new(latitude: 0, longitude: 0, zoom: 0, bearing: 0, tilt: 0),
    'pmtiles-vector': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'pmtiles-mlt': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'mbtiles-vector': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'mbtiles-mlt': .new(
      latitude: 0,
      longitude: 0,
      zoom: 0,
      bearing: 0,
      tilt: 0,
    ),
    'flutter-markers': .new(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13,
      bearing: 0,
      tilt: 0,
    ),
  };
  final defaultCamera = cameras[visualE2eSceneId];
  if (defaultCamera == null) {
    throw ArgumentError.value(
      visualE2eSceneId,
      'VISUAL_E2E_SCENE',
      'unknown visual E2E scene',
    );
  }
  final zoom = visualE2eZoom;
  final camera = zoom == null
      ? defaultCamera
      : VisualCamera(
          latitude: defaultCamera.latitude,
          longitude: defaultCamera.longitude,
          zoom: zoom,
          bearing: defaultCamera.bearing,
          tilt: defaultCamera.tilt,
        );

  var styleJson = await _loadStyleJson(visualE2eSceneId);
  if (styleJson.contains(_assetBasePlaceholder)) {
    final assetServer = await _VisualAssetServer.start();
    styleJson = styleJson.replaceAll(
      _assetBasePlaceholder,
      assetServer.baseUri.toString().replaceFirst(RegExp(r'/$'), ''),
    );
  }
  for (final entry in _mbtilesPlaceholders.entries) {
    if (styleJson.contains(entry.key)) {
      final url = await _VisualAssetServer.materializeMbtiles(entry.value);
      styleJson = replaceJsonStringPlaceholder(styleJson, entry.key, url);
    }
  }
  return .new(
    id: visualE2eSceneId,
    styleJson: styleJson,
    camera: camera,
    backgroundColor: const Color(0xffe7edf3),
  );
}

@visibleForTesting
String replaceJsonStringPlaceholder(
  String json,
  String placeholder,
  String value,
) {
  final encodedValue = jsonEncode(value);

  return json.replaceAll(
    placeholder,
    encodedValue.substring(1, encodedValue.length - 1),
  );
}

const _openFreeMapLibertyStyle = 'https://tiles.openfreemap.org/styles/liberty';

Future<String> _loadStyleJson(String sceneId) async {
  if (sceneId == 'flutter-markers') {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_openFreeMapLibertyStyle));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'OpenFreeMap Liberty returned HTTP ${response.statusCode}',
          uri: Uri.parse(_openFreeMapLibertyStyle),
        );
      }
      final styleJson = await response.transform(utf8.decoder).join();

      return configureFlutterMarkersSystemFonts(
        styleJson,
        platform: defaultTargetPlatform,
      );
    } finally {
      client.close(force: true);
    }
  }
  return rootBundle.loadString(
    'packages/visual_e2e_shared/assets/scenes/$sceneId.json',
  );
}

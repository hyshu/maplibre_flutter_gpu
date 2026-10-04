import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

const elevationSourceId = 'sample-elevation';
const hillshadeLayerId = 'sample-hillshade';
const elevationDataUrl =
    'https://demotiles.maplibre.org/terrain-tiles/tiles.json';

/// Shading and lighting controls for the elevation sample.
class const HillshadeSettings({
  final double exaggeration = 0.5,
  final double direction = 315,
  final double altitude = 45,
  final String method = 'standard',
  final bool anchoredToMap = true,
  final bool visible = true,
}) {
  HillshadeSettings copyWith({
    double? exaggeration,
    double? direction,
    double? altitude,
    String? method,
    bool? anchoredToMap,
    bool? visible,
  }) => .new(
    exaggeration: exaggeration ?? this.exaggeration,
    direction: direction ?? this.direction,
    altitude: altitude ?? this.altitude,
    method: method ?? this.method,
    anchoredToMap: anchoredToMap ?? this.anchoredToMap,
    visible: visible ?? this.visible,
  );

  HillshadeLayerProperties get properties => .new(
    hillshadeExaggeration: exaggeration,
    hillshadeIlluminationDirection: method == 'multidirectional'
        ? [direction, (direction + 120) % 360, (direction + 240) % 360]
        : direction,
    hillshadeIlluminationAltitude: altitude,
    hillshadeIlluminationAnchor: anchoredToMap ? 'map' : 'viewport',
    hillshadeMethod: method,
    hillshadeAccentColor: '#000000',
    hillshadeShadowColor: '#000000',
    hillshadeHighlightColor: '#ffffff',
    visibility: visible ? 'visible' : 'none',
  );
}

/// Adds flat shaded relief below labels without modifying the basemap.
Map<String, dynamic> buildHillshadeStyle(
  Map<String, dynamic> basemap, {
  bool visible = true,
}) {
  final layers = List<Map<String, dynamic>>.from(basemap['layers'] as List);
  final firstSymbol = layers.indexWhere((layer) => layer['type'] == 'symbol');
  final properties = const HillshadeSettings().properties.toJson()
    ..remove('visibility');
  layers.insert(firstSymbol < 0 ? layers.length : firstSymbol, {
    'id': hillshadeLayerId,
    'type': 'hillshade',
    'source': elevationSourceId,
    'layout': {'visibility': visible ? 'visible' : 'none'},
    'paint': properties,
  });

  return {
    ...basemap,
    'sources': {
      ...basemap['sources'] as Map<String, dynamic>,
      elevationSourceId: {
        'type': 'raster-dem',
        'url': elevationDataUrl,
        'tileSize': 256,
        'encoding': 'mapbox',
        'attribution':
            '<a href="https://earth.jaxa.jp/en/data/policy/">AW3D30 (JAXA)</a>',
      },
    },
    'layers': layers,
  };
}

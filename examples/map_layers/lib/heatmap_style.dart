import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

const earthquakeSourceId = 'sample-earthquakes';
const heatmapLayerId = 'sample-heatmap';
const pointLayerId = 'sample-points';
const earthquakeDataUrl =
    'https://maplibre.org/maplibre-gl-js/docs/assets/earthquakes.geojson';
const basemapStyleUrl = 'https://tiles.openfreemap.org/styles/positron';

/// Shared by the map's density ramp and the legend.
const densityColors = [
  0x002166ac,
  0xff67a9cf,
  0xffd1e5f0,
  0xfffddbc7,
  0xffef8a62,
  0xffb2182b,
];

/// Heatmap paint values and visibility controls shown by the sample.
class const HeatmapSettings({
  final double radius = 24,
  final double intensity = 1,
  final double opacity = 0.8,
  final bool weighted = true,
  final bool visible = true,
  final bool pointsVisible = false,
}) {
  HeatmapSettings copyWith({
    double? radius,
    double? intensity,
    double? opacity,
    bool? weighted,
    bool? visible,
    bool? pointsVisible,
  }) => .new(
    radius: radius ?? this.radius,
    intensity: intensity ?? this.intensity,
    opacity: opacity ?? this.opacity,
    weighted: weighted ?? this.weighted,
    visible: visible ?? this.visible,
    pointsVisible: pointsVisible ?? this.pointsVisible,
  );

  HeatmapLayerProperties get properties => .new(
    heatmapRadius: radius,
    heatmapIntensity: intensity,
    heatmapOpacity: opacity,
    heatmapWeight: weighted
        ? [
            'interpolate',
            ['linear'],
            ['get', 'mag'],
            0,
            0,
            6,
            1,
          ]
        : 1,
    heatmapColor: [
      'interpolate',
      ['linear'],
      ['heatmap-density'],
      for (var i = 0; i < densityColors.length; i++) ...[
        i / (densityColors.length - 1),
        _rgba(densityColors[i]),
      ],
    ],
    visibility: visible ? 'visible' : 'none',
  );
}

String _rgba(int color) =>
    'rgba(${(color >> 16) & 255},${(color >> 8) & 255},${color & 255},'
    '${((color >> 24) & 255) / 255})';

/// Adds earthquake layers below labels without changing the supplied basemap.
Map<String, dynamic> buildHeatmapStyle(
  Map<String, dynamic> basemap,
  Map<String, dynamic> earthquakes,
) {
  final layers = List<Map<String, dynamic>>.from(basemap['layers'] as List);
  final firstSymbol = layers.indexWhere((layer) => layer['type'] == 'symbol');
  final properties = const HeatmapSettings().properties.toJson()
    ..remove('visibility');
  layers.insertAll(firstSymbol < 0 ? layers.length : firstSymbol, [
    {
      'id': heatmapLayerId,
      'type': 'heatmap',
      'source': earthquakeSourceId,
      'paint': properties,
    },
    {
      'id': pointLayerId,
      'type': 'circle',
      'source': earthquakeSourceId,
      'layout': {'visibility': 'none'},
      'paint': {
        'circle-radius': 3,
        'circle-color': '#253746',
        'circle-stroke-color': '#ffffff',
        'circle-stroke-width': 1,
      },
    },
  ]);

  return {
    ...basemap,
    'sources': {
      ...basemap['sources'] as Map<String, dynamic>,
      earthquakeSourceId: {
        'type': 'geojson',
        'data': earthquakes,
        'attribution':
            '<a href="https://earthquake.usgs.gov/">USGS</a> '
            'earthquakes · <a href="https://maplibre.org/">MapLibre</a> sample',
      },
    },
    'layers': layers,
  };
}

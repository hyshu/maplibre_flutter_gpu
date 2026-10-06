import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/controller_fixtures.dart';

void main() {
  test('heatmap properties retain expressions through JSON and copyWith', () {
    final original = HeatmapLayerProperties.fromJson(const {
      'heatmap-radius': [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        4,
        15,
        40,
      ],
      'heatmap-weight': ['get', 'weight'],
      'heatmap-intensity': 2,
      'heatmap-color': [
        'interpolate',
        ['linear'],
        ['heatmap-density'],
        0,
        'transparent',
        1,
        'red',
      ],
      'heatmap-opacity': 0.8,
      'visibility': 'visible',
    });
    final changed = original.copyWith(
      const HeatmapLayerProperties(heatmapIntensity: 0, heatmapOpacity: 0),
    );

    expect(changed.toJson(), {
      ...original.toJson(),
      'heatmap-intensity': 0,
      'heatmap-opacity': 0,
    });
    expect(const HeatmapLayerProperties().toJson(), isEmpty);
    expect(const HeatmapLayerProperties().toJson(skipNulls: false), {
      'heatmap-radius': null,
      'heatmap-weight': null,
      'heatmap-intensity': null,
      'heatmap-color': null,
      'heatmap-opacity': null,
      'visibility': null,
    });
  });

  test(
    'addHeatmapLayer passes placement, layout, and paint after barrier',
    () async {
      final bridge = _LayerBridge();
      final barrier = Completer<void>();
      final events = <String>[];
      bridge.events = events;
      final controller = MapLibreMapController.bind(
        bridge,
        beforeStyleMutation: () async {
          events.add('before');
          await barrier.future;
        },
        onStyleMutationRequested: () => events.add('after'),
      );
      addTearDown(controller.dispose);
      final mutation = controller.addHeatmapLayer(
        'observations',
        'density',
        const HeatmapLayerProperties(
          heatmapRadius: ['get', 'radius'],
          heatmapWeight: ['get', 'weight'],
          heatmapIntensity: 1.5,
          heatmapOpacity: 0.5,
          visibility: 'none',
        ),
        belowLayerId: 'labels',
        sourceLayer: 'points',
        minzoom: 2,
        maxzoom: 15,
        filter: const [
          '>',
          ['get', 'weight'],
          0,
        ],
        enableInteraction: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, ['before']);
      expect(bridge.layer, isNull);

      barrier.complete();
      await mutation;
      expect(events, ['before', 'add', 'after']);
      expect(bridge.belowLayerId, 'labels');
      expect(bridge.layer, {
        'id': 'density',
        'type': 'heatmap',
        'source': 'observations',
        'source-layer': 'points',
        'minzoom': 2,
        'maxzoom': 15,
        'filter': [
          '>',
          ['get', 'weight'],
          0,
        ],
        'layout': {'visibility': 'none'},
        'paint': {
          'heatmap-radius': ['get', 'radius'],
          'heatmap-weight': ['get', 'weight'],
          'heatmap-intensity': 1.5,
          'heatmap-opacity': 0.5,
        },
      });
    },
  );

  test(
    'addLayer supports each property type and omits absent options',
    () async {
      final bridge = _LayerBridge();
      final controller = MapLibreMapController.bind(bridge);
      addTearDown(controller.dispose);

      for (final (properties, type, paint) in const [
        (
          HeatmapLayerProperties(heatmapRadius: 30),
          'heatmap',
          {'heatmap-radius': 30},
        ),
        (
          FillExtrusionLayerProperties(fillExtrusionHeight: 30),
          'fill-extrusion',
          {'fill-extrusion-height': 30},
        ),
        (
          HillshadeLayerProperties(hillshadeExaggeration: 0.7),
          'hillshade',
          {'hillshade-exaggeration': 0.7},
        ),
      ]) {
        await controller.addLayer('source', 'layer', properties);
        expect(bridge.layer, {
          'id': 'layer',
          'type': type,
          'source': 'source',
          'paint': paint,
        });
        expect(bridge.belowLayerId, isNull);
      }
    },
  );

  test('unsupported property types never reach native mutation', () async {
    final bridge = _LayerBridge();
    var barrierCalls = 0;
    var mutationCalls = 0;
    final controller = MapLibreMapController.bind(
      bridge,
      beforeStyleMutation: () async => barrierCalls++,
      onStyleMutationRequested: () => mutationCalls++,
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.addLayer('source', 'layer', _UnsupportedProperties()),
      throwsUnsupportedError,
    );
    expect(bridge.layer, isNull);
    expect(barrierCalls, 0);
    expect(mutationCalls, 0);
  });

  test('heatmap property updates retain null reset values', () async {
    final bridge = _LayerBridge();
    var mutationCalls = 0;
    final controller = MapLibreMapController.bind(
      bridge,
      onStyleMutationRequested: () => mutationCalls++,
    );
    addTearDown(controller.dispose);

    await controller.setLayerProperties(
      'density',
      const HeatmapLayerProperties(heatmapOpacity: 0),
    );
    expect(bridge.updatedLayerId, 'density');
    expect(bridge.properties, {
      'heatmap-radius': null,
      'heatmap-weight': null,
      'heatmap-intensity': null,
      'heatmap-color': null,
      'heatmap-opacity': 0,
      'visibility': null,
    });
    expect(mutationCalls, 1);
  });

  test(
    'native layer rejection propagates without requesting a repaint',
    () async {
      final bridge = _LayerBridge()..rejectLayer = true;
      var mutationCalls = 0;
      final controller = MapLibreMapController.bind(
        bridge,
        onStyleMutationRequested: () => mutationCalls++,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.addHeatmapLayer(
          'missing-source',
          'density',
          const HeatmapLayerProperties(),
        ),
        throwsStateError,
      );
      expect(mutationCalls, 0);
    },
  );
}

class _LayerBridge extends FakeControllerBridge {
  Map<String, dynamic>? layer;
  String? belowLayerId;
  String? updatedLayerId;
  Map<String, dynamic>? properties;
  List<String>? events;
  var rejectLayer = false;

  @override
  void addStyleLayerJson(String layerJson, {String? belowLayerId}) {
    events?.add('add');
    if (rejectLayer) throw StateError('Source does not exist');
    layer = jsonDecode(layerJson) as Map<String, dynamic>;
    this.belowLayerId = belowLayerId;
  }

  @override
  void setStyleLayerPropertiesJson(String layerId, String propertiesJson) {
    updatedLayerId = layerId;
    properties = jsonDecode(propertiesJson) as Map<String, dynamic>;
  }
}

class _UnsupportedProperties implements LayerProperties {
  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) => {};
}

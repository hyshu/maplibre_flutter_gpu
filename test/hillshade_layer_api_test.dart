import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'support/controller_fixtures.dart';

void main() {
  test('hillshade properties retain light arrays and camera expressions', () {
    const json = {
      'hillshade-accent-color': '#112233',
      'hillshade-exaggeration': [
        'interpolate',
        ['linear'],
        ['zoom'],
        0,
        0.2,
        12,
        0.7,
      ],
      'hillshade-highlight-color': ['white', '#ffeecc'],
      'hillshade-illumination-altitude': [30, 60],
      'hillshade-illumination-anchor': 'map',
      'hillshade-illumination-direction': [225, 315],
      'hillshade-method': 'multidirectional',
      'hillshade-shadow-color': ['#111111', '#334455'],
      'visibility': 'visible',
    };
    final original = HillshadeLayerProperties.fromJson(json);

    expect(original.toJson(), json);
    expect(
      original
          .copyWith(const HillshadeLayerProperties(hillshadeExaggeration: 0))
          .toJson(),
      {...json, 'hillshade-exaggeration': 0},
    );
    expect(const HillshadeLayerProperties().toJson(), isEmpty);
    expect(const HillshadeLayerProperties().toJson(skipNulls: false), {
      for (final key in json.keys) key: null,
    });
    expect(const HillshadeLayerProperties().copyWith(original).toJson(), json);
  });

  test(
    'hillshade creation respects the mutation barrier and placement',
    () async {
      final bridge = _HillshadeBridge();
      final barrier = Completer<void>();
      var repaints = 0;
      final controller = MapLibreMapController.bind(
        bridge,
        beforeStyleMutation: () => barrier.future,
        onStyleMutationRequested: () => repaints++,
      );
      addTearDown(controller.dispose);
      final mutation = controller.addHillshadeLayer(
        'elevation',
        'relief',
        const HillshadeLayerProperties(
          hillshadeExaggeration: 0.7,
          hillshadeIlluminationDirection: 315,
          hillshadeMethod: 'standard',
          visibility: 'none',
        ),
        belowLayerId: 'labels',
        minzoom: 4,
        maxzoom: 16,
      );
      await Future<void>.delayed(Duration.zero);
      expect(bridge.layer, isNull);
      expect(repaints, 0);

      barrier.complete();
      await mutation;
      expect(bridge.belowLayerId, 'labels');
      expect(bridge.layer, {
        'id': 'relief',
        'type': 'hillshade',
        'source': 'elevation',
        'minzoom': 4,
        'maxzoom': 16,
        'layout': {'visibility': 'none'},
        'paint': {
          'hillshade-exaggeration': 0.7,
          'hillshade-illumination-direction': 315,
          'hillshade-method': 'standard',
        },
      });
      expect(repaints, 1);
    },
  );

  test('hillshade updates preserve zero and null reset values', () async {
    final bridge = _HillshadeBridge();
    final controller = MapLibreMapController.bind(bridge);
    addTearDown(controller.dispose);

    await controller.setLayerProperties(
      'relief',
      const HillshadeLayerProperties(hillshadeExaggeration: 0),
    );
    expect(bridge.updatedLayerId, 'relief');
    expect(bridge.properties, {
      'hillshade-accent-color': null,
      'hillshade-exaggeration': 0,
      'hillshade-highlight-color': null,
      'hillshade-illumination-altitude': null,
      'hillshade-illumination-anchor': null,
      'hillshade-illumination-direction': null,
      'hillshade-method': null,
      'hillshade-shadow-color': null,
      'visibility': null,
    });
  });

  test('a rejected hillshade layer does not request a repaint', () async {
    final bridge = _HillshadeBridge()..rejectLayer = true;
    var repaints = 0;
    final controller = MapLibreMapController.bind(
      bridge,
      onStyleMutationRequested: () => repaints++,
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.addHillshadeLayer(
        'missing',
        'relief',
        const HillshadeLayerProperties(),
      ),
      throwsStateError,
    );
    expect(repaints, 0);
  });
}

class _HillshadeBridge extends FakeControllerBridge {
  Map<String, dynamic>? layer;
  String? belowLayerId;
  String? updatedLayerId;
  Map<String, dynamic>? properties;
  var rejectLayer = false;

  @override
  void addStyleLayerJson(String layerJson, {String? belowLayerId}) {
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

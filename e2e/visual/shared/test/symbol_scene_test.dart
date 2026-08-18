import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sceneIds = <String>[
  'symbol-data-driven-paint',
  'symbol-paint-update',
  'symbol-line-pitch',
  'symbol-icon-effects',
  'symbol-layer-order',
  'symbol-z-order',
  'symbol-text-shaping',
];

void main() {
  test('symbol parity scenes are valid style JSON', () async {
    for (final sceneId in _sceneIds) {
      final scene = await _scene(sceneId);
      expect(scene['version'], 8, reason: sceneId);
      expect(scene['sources'], isA<Map<String, Object?>>(), reason: sceneId);
      expect(scene['layers'], isA<List<Object?>>(), reason: sceneId);
    }
  });

  test(
    'data-driven scene evaluates symbol paint from feature properties',
    () async {
      final scene = await _scene('symbol-data-driven-paint');
      final layer = _layer(scene, 'data-driven-symbols');
      final paint = layer['paint']! as Map<String, Object?>;

      expect(paint['text-color'], <Object?>['get', 'textColor']);
      expect(paint['text-opacity'], <Object?>['get', 'textOpacity']);
      expect(paint['text-halo-width'], <Object?>['get', 'haloWidth']);
      expect(paint['icon-color'], <Object?>['get', 'iconColor']);
    },
  );

  test('paint-update scene keeps placement inputs constant', () async {
    final scene = await _scene('symbol-paint-update');
    final layer = _layer(scene, 'paint-update-symbols');
    final layout = layer['layout']! as Map<String, Object?>;
    final paint = layer['paint']! as Map<String, Object?>;

    expect(layout, containsPair('icon-image', 'circle_15'));
    expect(layout, containsPair('text-size', 28));
    expect(paint, containsPair('text-opacity', 0.25));
    expect(paint, containsPair('icon-opacity', 0.25));
  });

  test(
    'line scene exercises map-aligned rotation and pitched camera',
    () async {
      final scene = await _scene('symbol-line-pitch');
      final layer = _layer(scene, 'curved-route-labels');
      final layout = layer['layout']! as Map<String, Object?>;
      final shortTextLayer = _layer(scene, 'short-line-text-angle');
      final shortTextLayout = shortTextLayer['layout']! as Map<String, Object?>;

      expect(scene['bearing'], 32);
      expect(scene['pitch'], 45);
      expect(layout['symbol-placement'], 'line-center');
      expect(layout['text-rotation-alignment'], 'map');
      expect(layout['text-pitch-alignment'], 'map');
      expect(layout['text-rotate'], <Object?>['get', 'rotation']);
      final features = _sourceFeatures(scene, 'curved-routes');
      final iconOnly = features.singleWhere(
        (feature) =>
            (feature['properties']! as Map<String, Object?>)['kind'] ==
            'icon-only',
      );
      final iconOnlyProperties =
          iconOnly['properties']! as Map<String, Object?>;

      expect(iconOnlyProperties, isNot(contains('label')));
      expect(iconOnlyProperties['icon'], 'marker_15');
      expect(iconOnlyProperties['rotation'], 34);
      final shortText = features.singleWhere(
        (feature) =>
            (feature['properties']! as Map<String, Object?>)['kind'] ==
            'short-text',
      );
      final shortTextProperties =
          shortText['properties']! as Map<String, Object?>;
      final shortTextGeometry = shortText['geometry']! as Map<String, Object?>;
      final shortTextCoordinates =
          shortTextGeometry['coordinates']! as List<Object?>;

      expect(shortTextProperties, isNot(contains('icon')));
      expect(
        (shortTextProperties['label']! as String).length,
        lessThanOrEqualTo(2),
      );
      expect(shortTextCoordinates, hasLength(2));
      expect(shortTextLayout['symbol-placement'], 'line-center');
      expect(shortTextLayout['text-rotation-alignment'], 'map');
      expect(shortTextLayout['text-pitch-alignment'], 'map');
      expect(shortTextLayout['text-rotate'], <Object?>['get', 'rotation']);
      expect(shortTextLayout['text-size'], 58);
    },
  );

  test('icon scene covers SDF, halo, fit, rotation, and translation', () async {
    final scene = await _scene('symbol-icon-effects');
    final sdf = _layer(scene, 'sdf-icon-effects');
    final sdfPaint = sdf['paint']! as Map<String, Object?>;
    final fit = _layer(scene, 'icon-text-fit');
    final fitLayout = fit['layout']! as Map<String, Object?>;
    final natural = _layer(scene, 'nine-patch-natural-size');
    final naturalLayout = natural['layout']! as Map<String, Object?>;
    final smallFit = _layer(scene, 'nine-patch-small-proportional-fit');
    final smallFitLayout = smallFit['layout']! as Map<String, Object?>;
    final scaledNoFit = _layer(scene, 'nine-patch-uniform-scale-no-fit');
    final scaledNoFitLayout = scaledNoFit['layout']! as Map<String, Object?>;
    final translated = _layer(scene, 'translated-text');
    final translatedLayout = translated['layout']! as Map<String, Object?>;
    final translatedPaint = translated['paint']! as Map<String, Object?>;
    final sprites = (scene['sprite']! as List<Object?>)
        .cast<Map<String, Object?>>();

    expect(sprites.map((sprite) => sprite['id']), <Object?>['base', 'alt']);
    expect(sdfPaint, containsPair('icon-halo-width', 3));
    expect(sdfPaint, contains('icon-translate'));
    expect(fitLayout['icon-image'], 'base:visual-e2e-nine-patch-panel');
    expect(fitLayout, containsPair('icon-text-fit', 'both'));
    expect(fitLayout['icon-text-fit-padding'], <Object?>[6, 18, 12, 10]);
    expect(fitLayout['icon-padding'], 9);
    expect(naturalLayout['icon-image'], 'base:visual-e2e-nine-patch-panel');
    expect(naturalLayout['icon-text-fit'], 'none');
    expect(naturalLayout['icon-size'], 1);
    expect(smallFitLayout['icon-text-fit'], 'both');
    expect(smallFitLayout['icon-size'], 1.35);
    expect(smallFitLayout['text-size'], 12);
    expect(smallFitLayout['icon-text-fit-padding'], <Object?>[2, 9, 7, 4]);
    expect(scaledNoFitLayout['icon-text-fit'], 'none');
    expect(scaledNoFitLayout['icon-size'], 2.25);
    expect(translatedPaint['icon-translate-anchor'], 'map');
    expect(translatedPaint, contains('text-translate'));
    expect(translatedPaint['text-translate-anchor'], 'map');
    expect(translatedLayout['icon-pitch-alignment'], isNull);
  });

  test(
    'layer-order scene isolates six widget strata with native layers',
    () async {
      final scene = await _scene('symbol-layer-order');
      final layers = (scene['layers']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final ids = layers.map((layer) => layer['id']).toList();
      final symbolLayerIndices = <int>[
        for (var index = 0; index < layers.length; index++)
          if (layers[index]['type'] == 'symbol') index,
      ];
      final features = _sourceFeatures(scene, 'ordered-symbols');
      final visibility = <int, Object?>{
        for (final feature in features)
          (feature['properties']! as Map<String, Object?>)['slot']! as int:
              (feature['properties']! as Map<String, Object?>)['visibility'],
      };

      expect(symbolLayerIndices, hasLength(6));
      for (var index = 1; index < symbolLayerIndices.length; index++) {
        expect(
          symbolLayerIndices[index] - symbolLayerIndices[index - 1],
          greaterThan(1),
        );
      }
      expect(
        ids,
        containsAllInOrder(<String>[
          'symbol-behind-cover',
          'background-colored-cover',
          'symbol-above-cover',
        ]),
      );
      expect(layers.where((layer) => layer['type'] == 'circle'), hasLength(7));
      expect(layers.where((layer) => layer['type'] == 'fill'), hasLength(1));
      expect(visibility, <int, Object?>{
        1: 'hidden',
        2: 'shown',
        3: 'hidden',
        4: 'shown',
        5: 'hidden',
        6: 'shown',
      });
    },
  );

  test('z-order scene isolates viewport-y and sort-key ordering', () async {
    final scene = await _scene('symbol-z-order');
    final symbolLayers = (scene['layers']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((layer) => layer['type'] == 'symbol')
        .toList();
    final viewportLayout =
        _layer(scene, 'viewport-y-overlap')['layout']! as Map<String, Object?>;
    final sortKeyLayout =
        _layer(scene, 'sort-key-overlap')['layout']! as Map<String, Object?>;
    final viewportFeatures = _sourceFeatures(scene, 'viewport-y-symbols');
    final sortKeyFeatures = _sourceFeatures(scene, 'sort-key-symbols');
    final viewportFront = viewportFeatures.first;
    final viewportBack = viewportFeatures.last;
    final sortKeyFront = sortKeyFeatures.first;
    final sortKeyBack = sortKeyFeatures.last;
    final viewportFrontCoordinates =
        (viewportFront['geometry']! as Map<String, Object?>)['coordinates']!
            as List<Object?>;
    final viewportBackCoordinates =
        (viewportBack['geometry']! as Map<String, Object?>)['coordinates']!
            as List<Object?>;
    final sortKeyFrontCoordinates =
        (sortKeyFront['geometry']! as Map<String, Object?>)['coordinates']!
            as List<Object?>;
    final sortKeyBackCoordinates =
        (sortKeyBack['geometry']! as Map<String, Object?>)['coordinates']!
            as List<Object?>;
    final sortKeyFrontProperties =
        sortKeyFront['properties']! as Map<String, Object?>;
    final sortKeyBackProperties =
        sortKeyBack['properties']! as Map<String, Object?>;

    expect(symbolLayers, hasLength(2));
    expect(viewportLayout['symbol-z-order'], 'viewport-y');
    expect(viewportLayout, isNot(contains('symbol-sort-key')));
    expect(viewportLayout['icon-allow-overlap'], isTrue);
    expect(viewportLayout['text-allow-overlap'], isTrue);
    expect(
      viewportFrontCoordinates[1]! as num,
      lessThan(viewportBackCoordinates[1]! as num),
    );
    expect(
      ((viewportFrontCoordinates[0]! as num) -
              (viewportBackCoordinates[0]! as num))
          .abs(),
      lessThan(0.001),
    );

    expect(sortKeyLayout['symbol-z-order'], 'source');
    expect(sortKeyLayout['symbol-sort-key'], <Object?>['get', 'sortKey']);
    expect(sortKeyLayout['icon-allow-overlap'], isTrue);
    expect(sortKeyLayout['text-allow-overlap'], isTrue);
    expect(
      sortKeyFrontProperties['sortKey']! as num,
      greaterThan(sortKeyBackProperties['sortKey']! as num),
    );
    expect(sortKeyFrontCoordinates[1], sortKeyBackCoordinates[1]);
    expect(
      ((sortKeyFrontCoordinates[0]! as num) -
              (sortKeyBackCoordinates[0]! as num))
          .abs(),
      lessThan(0.001),
    );
  });

  test(
    'text scene covers formatted, vertical, RTL, BMP emoji, and long text',
    () async {
      final scene = await _scene('symbol-text-shaping');
      final formatted = _layer(scene, 'formatted-text-runs');
      final formattedLayout = formatted['layout']! as Map<String, Object?>;
      final paddedRight = _layer(scene, 'padded-right-justified-text');
      final paddedRightLayout = paddedRight['layout']! as Map<String, Object?>;
      final inline = _layer(scene, 'formatted-inline-image');
      final inlineLayout = inline['layout']! as Map<String, Object?>;
      final inlineSdf = _layer(scene, 'formatted-inline-sdf');
      final inlineSdfLayout = inlineSdf['layout']! as Map<String, Object?>;
      final inlineSdfPaint = inlineSdf['paint']! as Map<String, Object?>;
      final variableAnchor = _layer(scene, 'asymmetric-variable-anchor-text');
      final variableAnchorLayout =
          variableAnchor['layout']! as Map<String, Object?>;
      final vertical = _layer(scene, 'vertical-cjk-text');
      final verticalLayout = vertical['layout']! as Map<String, Object?>;
      final rtl = _layer(scene, 'rtl-fallback-stack');
      final rtlLayout = rtl['layout']! as Map<String, Object?>;
      final lineRtl = _layer(scene, 'formatted-rtl-line-text');
      final lineRtlLayout = lineRtl['layout']! as Map<String, Object?>;
      final source =
          (scene['sources']! as Map<String, Object?>)['shaped-text']!
              as Map<String, Object?>;
      final data = source['data']! as Map<String, Object?>;
      final features = (data['features']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final longFeature = features.singleWhere(
        (feature) =>
            (feature['properties']! as Map<String, Object?>)['kind'] == 'long',
      );
      final longLabel =
          (longFeature['properties']! as Map<String, Object?>)['label']!
              as String;

      expect((formattedLayout['text-field']! as List<Object?>).first, 'format');
      expect(formattedLayout['text-justify'], 'left');
      expect(formattedLayout['text-padding'], 24);
      expect(paddedRightLayout['text-justify'], 'right');
      expect(paddedRightLayout['text-padding'], 30);
      expect(paddedRightLayout['text-field'], contains('\n'));
      expect((inlineLayout['text-field']! as List<Object?>).first, 'format');
      expect(jsonEncode(inlineLayout['text-field']), contains('cafe_15'));
      expect(jsonEncode(inlineSdfLayout['text-field']), contains('circle_15'));
      expect(inlineSdfPaint['text-halo-width'], 3);
      expect(variableAnchorLayout['text-variable-anchor'], <Object?>[
        'top-right',
        'bottom-left',
      ]);
      expect(variableAnchorLayout['text-variable-anchor-offset'], <Object?>[
        'top-right',
        <Object?>[2.8, -1.6],
        'bottom-left',
        <Object?>[-3.2, 1.4],
      ]);
      expect(verticalLayout['text-writing-mode'], <Object?>['vertical']);
      expect((rtlLayout['text-field']! as List<Object?>).first, 'format');
      expect(rtlLayout['text-font'], <Object?>[
        'Noto Sans Regular',
        'Noto Sans Hebrew Regular',
      ]);
      expect(rtlLayout['text-size'], 36);
      expect(jsonEncode(rtlLayout['text-field']), contains('(שלום 123)'));
      expect(jsonEncode(rtlLayout['text-field']), contains('(אבג 456)'));
      expect(jsonEncode(rtlLayout['text-field']), contains('#0369a1'));
      expect(jsonEncode(rtlLayout['text-field']), contains('#7c3aed'));
      expect(jsonEncode(rtlLayout['text-field']), contains('#be123c'));
      expect(lineRtlLayout['symbol-placement'], 'line-center');
      expect((lineRtlLayout['text-field']! as List<Object?>).first, 'format');
      expect(jsonEncode(lineRtlLayout['text-field']), contains('(שלום 789)'));
      expect(jsonEncode(lineRtlLayout['text-field']), contains('font-scale'));
      expect(jsonEncode(lineRtlLayout['text-field']), contains('#0369a1'));
      expect(jsonEncode(lineRtlLayout['text-field']), contains('#7c3aed'));
      expect(jsonEncode(scene), contains('CAFE ☕'));
      expect(utf8.encode(longLabel).length, greaterThan(127));
    },
  );

  test(
    'glyph fixture contains every non-Latin range requested by the scene',
    () {
      for (final range in <String>[
        '19968-20223',
        '26368-26623',
        '39168-39423',
        '9728-9983',
      ]) {
        final file = File('assets/resources/glyphs/NotoCJK/$range.pbf');
        expect(file.existsSync(), isTrue, reason: range);
        expect(file.lengthSync(), greaterThan(1000), reason: range);
      }
      for (final range in <String>['0-255', '1280-1535']) {
        final file = File('assets/resources/glyphs/NotoSansHebrew/$range.pbf');
        expect(file.existsSync(), isTrue, reason: range);
        expect(file.lengthSync(), greaterThan(1000), reason: range);
      }
    },
  );

  test('sprite fixture exposes an SDF and a long identifier', () async {
    final sprites = jsonDecode(
      await File('assets/resources/sprite.json').readAsString(),
    ) as Map<String, Object?>;
    final sdf = sprites['circle_15']! as Map<String, Object?>;
    final ninePatch =
        sprites['visual-e2e-nine-patch-panel']! as Map<String, Object?>;

    expect(sdf['sdf'], isTrue);
    expect(ninePatch['stretchX'], <Object?>[
      <Object?>[16, 48],
    ]);
    expect(ninePatch['stretchY'], <Object?>[
      <Object?>[12, 36],
    ]);
    expect(ninePatch['content'], <Object?>[7, 10, 55, 39]);
    expect(ninePatch['textFitWidth'], 'stretchOnly');
    expect(ninePatch['textFitHeight'], 'proportional');
    expect(
      sprites,
      contains(
        'visual-e2e-icon-name-that-is-deliberately-longer-than-sixty-three-utf8-bytes',
      ),
    );
  });
}

Future<Map<String, Object?>> _scene(String id) async {
  return (jsonDecode(await File('assets/scenes/$id.json').readAsString())
      as Map<String, Object?>);
}

Map<String, Object?> _layer(Map<String, Object?> scene, String id) {
  return (scene['layers']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((layer) => layer['id'] == id);
}

List<Map<String, Object?>> _sourceFeatures(
  Map<String, Object?> scene,
  String sourceId,
) {
  final source =
      (scene['sources']! as Map<String, Object?>)[sourceId]!
          as Map<String, Object?>;
  final data = source['data']! as Map<String, Object?>;

  return (data['features']! as List<Object?>).cast<Map<String, Object?>>();
}

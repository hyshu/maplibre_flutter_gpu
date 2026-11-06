import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/pipeline_key.dart';
import 'package:maplibre_flutter_gpu/src/frame/style_pipeline_keys.dart';

String _style(List<Map<String, Object?>> layers) =>
    jsonEncode({'version': 8, 'sources': {}, 'layers': layers});

void main() {
  test('malformed or layerless styles contribute no pipelines', () {
    expect(pipelineKeysForStyle('not json'), isEmpty);
    expect(pipelineKeysForStyle('[]'), isEmpty);
    expect(pipelineKeysForStyle(jsonEncode({'version': 8})), isEmpty);
    expect(pipelineKeysForStyle(_style([])), isEmpty);
  });

  test('symbol layers draw as widgets and contribute nothing', () {
    expect(
      pipelineKeysForStyle(
        _style([
          {'id': 'labels', 'type': 'symbol', 'source': 'a'},
        ]),
      ),
      isEmpty,
    );
  });

  test('background selects the pattern pipeline only with a pattern', () {
    expect(
      pipelineKeysForStyle(
        _style([
          {'id': 'bg', 'type': 'background'},
        ]),
      ),
      {RenderPipelineKey.fill},
    );
    expect(
      pipelineKeysForStyle(
        _style([
          {
            'id': 'bg',
            'type': 'background',
            'paint': {'background-pattern': 'dots'},
          },
        ]),
      ),
      {RenderPipelineKey.backgroundPattern},
    );
  });

  test('vector layers add their constant and data-driven pipelines', () {
    final keys = pipelineKeysForStyle(
      _style([
        {'id': 'water', 'type': 'fill', 'source': 'a'},
        {
          'id': 'roads',
          'type': 'line',
          'source': 'a',
          'paint': {
            'line-dasharray': [2, 1],
          },
        },
        {'id': 'buildings', 'type': 'fill-extrusion', 'source': 'a'},
        {'id': 'points', 'type': 'circle', 'source': 'a'},
      ]),
    );
    expect(
      keys,
      containsAll([
        RenderPipelineKey.fill,
        RenderPipelineKey.fillDataDriven,
        RenderPipelineKey.fillOutline,
        RenderPipelineKey.fillOutlineTriangulatedDataDriven,
        RenderPipelineKey.lineSdfDataDriven,
        RenderPipelineKey.fillExtrusion,
        RenderPipelineKey.fillExtrusionDepth,
        RenderPipelineKey.fillExtrusionDataDriven,
        RenderPipelineKey.fillExtrusionDataDrivenDepth,
        RenderPipelineKey.circle,
        RenderPipelineKey.circleDataDriven,
        RenderPipelineKey.clippingMask,
      ]),
    );
    expect(
      keys,
      anyOf(
        contains(RenderPipelineKey.lineSdf),
        contains(RenderPipelineKey.lineSdfPacked),
      ),
    );
    expect(keys, isNot(contains(RenderPipelineKey.line)));
    expect(keys, isNot(contains(RenderPipelineKey.linePattern)));
    expect(keys, isNot(contains(RenderPipelineKey.raster)));
  });

  test('line paint selects the pattern, gradient, or dash family', () {
    Set<RenderPipelineKey> lineKeys(Map<String, Object?> paint) =>
        pipelineKeysForStyle(
          _style([
            {'id': 'l', 'type': 'line', 'source': 'a', 'paint': paint},
          ]),
        );
    expect(
      lineKeys({'line-pattern': 'p'}),
      contains(RenderPipelineKey.linePatternDataDriven),
    );
    expect(
      lineKeys({'line-gradient': 'red'}),
      contains(RenderPipelineKey.lineGradientDataDriven),
    );
    expect(lineKeys({}), contains(RenderPipelineKey.lineDataDriven));
  });

  test('raster and terrain layers add their own pipelines', () {
    expect(
      pipelineKeysForStyle(
        _style([
          {'id': 'tiles', 'type': 'raster', 'source': 'r'},
          {'id': 'relief', 'type': 'hillshade', 'source': 'd'},
          {'id': 'heat', 'type': 'heatmap', 'source': 'h'},
        ]),
      ),
      {
        RenderPipelineKey.raster,
        RenderPipelineKey.hillshadePrepare,
        RenderPipelineKey.hillshade,
        RenderPipelineKey.heatmap,
        RenderPipelineKey.heatmapDataDriven,
        RenderPipelineKey.heatmapTexture,
        RenderPipelineKey.clippingMask,
      },
    );
  });
}

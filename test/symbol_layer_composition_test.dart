import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/labels/symbol_layer_composition.dart';

void main() {
  test('empty symbol list renders one unbounded GPU stratum', () {
    final composition = composeSymbolLayers<int>(
      const [],
      layerIndexOf: (value) => value,
    );

    expect(composition.widgetStrata, isEmpty);
    expect(composition.gpuStrata, hasLength(1));
    expect(composition.gpuStrata.single.minimumLayerIndex, isNull);
    expect(composition.gpuStrata.single.maximumLayerIndex, isNull);
    expect(composition.gpuStrata.single.clearToTransparent, isFalse);
  });

  test('symbol layers split GPU ranges and preserve per-layer order', () {
    final composition = composeSymbolLayers<String>(const [
      'five-a',
      'two',
      'five-b',
    ], layerIndexOf: (value) => value.startsWith('five') ? 5 : 2);

    expect(composition.widgetStrata.map((stratum) => stratum.layerIndex), [
      2,
      5,
    ]);
    expect(composition.widgetStrata[1].symbols, ['five-a', 'five-b']);
    expect(
      composition.gpuStrata
          .map(
            (stratum) => (
              stratum.minimumLayerIndex,
              stratum.maximumLayerIndex,
              stratum.clearToTransparent,
            ),
          )
          .toList(),
      [(null, 2, false), (3, 5, true), (6, null, true)],
    );
  });

  test('GPU callbacks preserve one unbounded native surface', () {
    final composition = composeSymbolLayers<int>(
      const [2, 5],
      layerIndexOf: (value) => value,
      singleGpuSurface: true,
    );

    expect(composition.gpuStrata, hasLength(1));
    expect(composition.gpuStrata.single.minimumLayerIndex, isNull);
    expect(composition.gpuStrata.single.maximumLayerIndex, isNull);
    expect(composition.gpuStrata.single.clearToTransparent, isFalse);
    expect(composition.widgetStrata.map((stratum) => stratum.layerIndex), [
      2,
      5,
    ]);
  });
}

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
    expect(composition.gpuStrata.single.widgetStrataBefore, 0);
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
              stratum.widgetStrataBefore,
              stratum.minimumLayerIndex,
              stratum.maximumLayerIndex,
              stratum.clearToTransparent,
            ),
          )
          .toList(),
      [(0, null, 2, false), (1, 3, 5, true), (2, 6, null, true)],
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

  test('omits transparent ranges without native commands', () {
    final composition = composeSymbolLayers<int>(
      const [2, 5, 9],
      layerIndexOf: (value) => value,
      nativeCommandLayerIndices: const {0, 1, 6, 7},
    );

    expect(
      composition.gpuStrata
          .map(
            (stratum) => (
              stratum.widgetStrataBefore,
              stratum.minimumLayerIndex,
              stratum.maximumLayerIndex,
            ),
          )
          .toList(),
      [(0, null, 2), (2, 6, 9)],
    );
  });

  test('commands on Widget layers do not create transparent surfaces', () {
    final composition = composeSymbolLayers<int>(
      const [2, 5],
      layerIndexOf: (value) => value,
      nativeCommandLayerIndices: const {2, 5},
    );

    expect(composition.gpuStrata, hasLength(1));
    expect(composition.gpuStrata.single.widgetStrataBefore, 0);
    expect(composition.gpuStrata.single.clearToTransparent, isFalse);
  });

  test('adjacent Widget layers need no empty GPU range', () {
    final composition = composeSymbolLayers<int>(const [
      2,
      3,
    ], layerIndexOf: (value) => value);

    expect(composition.gpuStrata.map((stratum) => stratum.widgetStrataBefore), [
      0,
      2,
    ]);
  });

  test('GPU topology changes only when gap occupancy changes', () {
    expect(
      symbolGpuStratumSlots(
        const [2, 5, 9],
        nativeCommandLayerIndices: const {0, 3, 7, 12},
      ),
      [0, 1, 2, 3],
    );
    expect(
      symbolGpuStratumSlots(
        const [2, 5, 9],
        nativeCommandLayerIndices: const {1, 4, 8, 10},
      ),
      [0, 1, 2, 3],
    );
    expect(
      symbolGpuStratumSlots(
        const [2, 5, 9],
        nativeCommandLayerIndices: const {1, 8, 10},
      ),
      [0, 2, 3],
    );
  });
}

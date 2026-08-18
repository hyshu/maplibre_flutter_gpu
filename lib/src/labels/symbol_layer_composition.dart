/// One native GPU layer range rendered around Flutter symbol widgets.
///
/// [minimumLayerIndex] is inclusive. [maximumLayerIndex] is exclusive. Null
/// leaves that side unbounded.
final class SymbolGpuStratum {
  final int? minimumLayerIndex;
  final int? maximumLayerIndex;
  final bool clearToTransparent;

  const SymbolGpuStratum({
    required this.minimumLayerIndex,
    required this.maximumLayerIndex,
    required this.clearToTransparent,
  });
}

/// Symbols sharing one MapLibre style layer.
final class SymbolWidgetStratum<T> {
  final int layerIndex;
  final List<T> symbols;

  const SymbolWidgetStratum({required this.layerIndex, required this.symbols});
}

/// Alternating native GPU and Flutter Widget strata in style layer order.
typedef SymbolLayerComposition<T> = ({
  List<SymbolGpuStratum> gpuStrata,
  List<SymbolWidgetStratum<T>> widgetStrata,
});

/// Splits map rendering around the style layers containing [symbols].
///
/// Symbol layers themselves have no native draw commands. Each Widget stratum
/// is therefore inserted after commands below its layer and before commands
/// above it. Input order remains stable within one layer. When
/// [singleGpuSurface] is true, the native map stays in one surface and every
/// Widget stratum follows it.
SymbolLayerComposition<T> composeSymbolLayers<T>(
  Iterable<T> symbols, {
  required int Function(T symbol) layerIndexOf,
  bool singleGpuSurface = false,
}) {
  final byLayer = <int, List<T>>{};
  for (final symbol in symbols) {
    byLayer.putIfAbsent(layerIndexOf(symbol), () => <T>[]).add(symbol);
  }
  final layerIndices = byLayer.keys.toList()..sort();
  final widgetStrata = <SymbolWidgetStratum<T>>[
    for (final layerIndex in layerIndices)
      SymbolWidgetStratum<T>(
        layerIndex: layerIndex,
        symbols: List<T>.unmodifiable(byLayer[layerIndex]!),
      ),
  ];
  if (layerIndices.isEmpty || singleGpuSurface) {
    return (
      gpuStrata: const [
        SymbolGpuStratum(
          minimumLayerIndex: null,
          maximumLayerIndex: null,
          clearToTransparent: false,
        ),
      ],
      widgetStrata: widgetStrata,
    );
  }

  final gpuStrata = <SymbolGpuStratum>[
    SymbolGpuStratum(
      minimumLayerIndex: null,
      maximumLayerIndex: layerIndices.first,
      clearToTransparent: false,
    ),
  ];
  for (var index = 0; index < layerIndices.length; index += 1) {
    gpuStrata.add(
      SymbolGpuStratum(
        minimumLayerIndex: layerIndices[index] + 1,
        maximumLayerIndex: index + 1 < layerIndices.length
            ? layerIndices[index + 1]
            : null,
        clearToTransparent: true,
      ),
    );
  }

  return (
    gpuStrata: List<SymbolGpuStratum>.unmodifiable(gpuStrata),
    widgetStrata: List<SymbolWidgetStratum<T>>.unmodifiable(widgetStrata),
  );
}

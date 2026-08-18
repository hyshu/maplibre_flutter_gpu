/// One native GPU layer range rendered around Flutter symbol widgets.
///
/// [minimumLayerIndex] is inclusive. [maximumLayerIndex] is exclusive. Null
/// leaves that side unbounded.
final class SymbolGpuStratum {
  /// Number of Widget strata painted below this GPU surface.
  final int widgetStrataBefore;

  final int? minimumLayerIndex;
  final int? maximumLayerIndex;
  final bool clearToTransparent;

  const SymbolGpuStratum({
    required this.widgetStrataBefore,
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
/// above it. Input order remains stable within one layer. Transparent ranges
/// without a layer in [nativeCommandLayerIndices] are omitted. A null command
/// set retains every non-empty range for callers without frame metadata. When
/// [singleGpuSurface] is true, the native map stays in one surface and every
/// Widget stratum follows it.
SymbolLayerComposition<T> composeSymbolLayers<T>(
  Iterable<T> symbols, {
  required int Function(T symbol) layerIndexOf,
  Set<int>? nativeCommandLayerIndices,
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
          widgetStrataBefore: 0,
          minimumLayerIndex: null,
          maximumLayerIndex: null,
          clearToTransparent: false,
        ),
      ],
      widgetStrata: widgetStrata,
    );
  }

  final gpuStrata = <SymbolGpuStratum>[];
  for (final slot in symbolGpuStratumSlots(
    layerIndices,
    nativeCommandLayerIndices: nativeCommandLayerIndices,
  )) {
    final minimumLayerIndex = slot == 0 ? null : layerIndices[slot - 1] + 1;
    final maximumLayerIndex = slot == layerIndices.length
        ? null
        : layerIndices[slot];
    gpuStrata.add(
      SymbolGpuStratum(
        widgetStrataBefore: slot,
        minimumLayerIndex: minimumLayerIndex,
        maximumLayerIndex: maximumLayerIndex,
        clearToTransparent: slot != 0,
      ),
    );
  }

  return (
    gpuStrata: List<SymbolGpuStratum>.unmodifiable(gpuStrata),
    widgetStrata: List<SymbolWidgetStratum<T>>.unmodifiable(widgetStrata),
  );
}

/// Returns GPU surface slots required around sorted Widget style layers.
///
/// Slot zero carries the map clear color and is always retained. Later slots
/// are transparent and exist only when their layer range is non-empty and
/// contains a native command layer.
List<int> symbolGpuStratumSlots(
  Iterable<int> widgetLayerIndices, {
  Set<int>? nativeCommandLayerIndices,
}) {
  final layers = widgetLayerIndices.toSet().toList()..sort();
  if (layers.isEmpty) return const <int>[0];

  final slots = <int>[0];
  for (var slot = 1; slot <= layers.length; slot += 1) {
    final minimumLayerIndex = layers[slot - 1] + 1;
    final maximumLayerIndex = slot == layers.length ? null : layers[slot];
    if (maximumLayerIndex == minimumLayerIndex) continue;
    if (nativeCommandLayerIndices != null &&
        !_containsLayerInRange(
          nativeCommandLayerIndices,
          minimumLayerIndex,
          maximumLayerIndex,
        )) {
      continue;
    }
    slots.add(slot);
  }

  return List<int>.unmodifiable(slots);
}

bool _containsLayerInRange(
  Set<int> layerIndices,
  int minimumLayerIndex,
  int? maximumLayerIndex,
) {
  for (final layerIndex in layerIndices) {
    if (layerIndex >= minimumLayerIndex &&
        (maximumLayerIndex == null || layerIndex < maximumLayerIndex)) {
      return true;
    }
  }

  return false;
}

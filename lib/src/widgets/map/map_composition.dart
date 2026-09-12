part of '../maplibre_map.dart';

class const _MapLayerComposition({
  required final MapLibreMap options,
  required final Size screenSize,
  required final MaplibreBridge bridge,
  required final GpuFrameRenderer gpuRenderer,
  required final MapGpuResourcePool resources,
  required final MapViewport viewport,
  required final MapLabelSource labels,
  required final Listenable symbolLayoutVersion,
  required final Listenable gpuFrame,
  required final Set<int> nativeCommandLayerIndices,
  required final bool Function() gpuRenderingAllowed,
  required final NativeFrameSnapshotLease? Function() frameSnapshotProvider,
  required final ValueChanged<NativeFrameSnapshotLease> onFrameSnapshotReleased,
}) extends StatelessWidget {
  Widget _buildSymbolOverlay(
    Size screenSize,
    SymbolWidgetStratum<MapSymbol> stratum,
  ) {
    List<MapSymbol> currentSymbols() =>
        labels.liveSymbolsForLayer(stratum.layerIndex);

    return MapSymbolOverlay(
      key: ValueKey('symbols:${stratum.layerIndex}'),
      symbols: stratum.symbols,
      symbolsProvider: currentSymbols,
      relayout: symbolLayoutVersion,
      screenSize: screenSize,
      iconBuilder: options.symbolIconBuilder,
      textBuilder: options.symbolTextBuilder,
      fadeDuration: options.symbolFadeDuration,
      cullingPadding: options.symbolCullingPadding,
      onFadedOut: labels.onFadedOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preservesGpuCallbackOrder =
        options.gpuMapRenderCallback != null ||
        options.gpuRenderCallback != null;
    final usesSingleGpuSurface =
        preservesGpuCallbackOrder ||
        options.symbolCompositingMode == .fastOverlay;
    final composition = composeSymbolLayers(
      labels.symbols,
      layerIndexOf: (symbol) => symbol.data.layerIndex,
      nativeCommandLayerIndices: nativeCommandLayerIndices,
      singleGpuSurface: usesSingleGpuSurface,
    );
    final List<({int? maximumLayerIndex, int? minimumLayerIndex})>
    gpuLayerRanges = .unmodifiable([
      for (final stratum in composition.gpuStrata)
        (
          minimumLayerIndex: stratum.minimumLayerIndex,
          maximumLayerIndex: stratum.maximumLayerIndex,
        ),
    ]);
    final lastGpuIndex = composition.gpuStrata.length - 1;
    final repaint = Listenable.merge([
      gpuFrame,
      if (options.gpuRepaint != null) options.gpuRepaint!,
    ]);
    final children = <Widget>[];
    void addGpuStratum(int index) {
      final stratum = composition.gpuStrata[index];
      final isFirst = index == 0;
      final isLast = index == lastGpuIndex;
      children.add(
        IgnorePointer(
          child: RepaintBoundary(
            key: preservesGpuCallbackOrder
                ? const ValueKey<String>('gpu:callbacks')
                : ValueKey('gpu:$index'),
            child: CustomPaint(
              size: Size.infinite,
              painter: MapGpuPainter(
                bridge: bridge,
                gpuRenderer: gpuRenderer,
                resources: resources.acquire(
                  index,
                  minimumLayerIndex: stratum.minimumLayerIndex,
                  maximumLayerIndex: stratum.maximumLayerIndex,
                  clearToTransparent: stratum.clearToTransparent,
                ),
                width: viewport.physicalWidth,
                height: viewport.physicalHeight,
                logicalWidth: viewport.logicalWidth,
                logicalHeight: viewport.logicalHeight,
                devicePixelRatio: viewport.devicePixelRatio,
                frameSeq: gpuRenderer.frameSeq,
                gpuMapRenderCallback: options.gpuMapRenderCallback,
                gpuRenderCallback: options.gpuRenderCallback,
                gpuOverlayDepthMode: options.gpuOverlayDepthMode,
                gpuRenderingAllowed: gpuRenderingAllowed,
                frameSnapshotProvider: frameSnapshotProvider,
                onFrameSnapshotReleased: onFrameSnapshotReleased,
                stratumIndex: index,
                layerRanges: gpuLayerRanges,
                minimumLayerIndex: stratum.minimumLayerIndex,
                maximumLayerIndex: stratum.maximumLayerIndex,
                clearToTransparent: stratum.clearToTransparent,
                releaseFrameSnapshot: isLast,
                advanceResourceFrame: isFirst,
                evictResourceCaches: isLast,
                repaint: repaint,
              ),
            ),
          ),
        ),
      );
    }

    var nextGpuIndex = 0;
    void addGpuStrataAfter(int widgetStrataCount) {
      while (nextGpuIndex < composition.gpuStrata.length &&
          composition.gpuStrata[nextGpuIndex].widgetStrataBefore ==
              widgetStrataCount) {
        addGpuStratum(nextGpuIndex++);
      }
    }

    addGpuStrataAfter(0);
    for (var index = 0; index < composition.widgetStrata.length; index += 1) {
      children.add(
        _buildSymbolOverlay(screenSize, composition.widgetStrata[index]),
      );
      addGpuStrataAfter(index + 1);
    }
    assert(nextGpuIndex == composition.gpuStrata.length);
    resources.trimToActiveSlotCount(gpuLayerRanges.length);

    return Stack(fit: .expand, clipBehavior: .hardEdge, children: children);
  }
}

part of '../renderer.dart';

/// Owns decoded topology and partition storage across native frame generations.
final class _GpuFrameGraphPreparer {
  _GpuFrameGraphPreparer(GpuResourceCache resources)
    : _decoder = GpuCommandDecoder(resources);

  final GpuCommandDecoder _decoder;
  List<DrawEntry> get _drawEntries => _decoder.entries;
  final List<_PreparedDrawPartition> _preparedPartitions = [];
  final List<List<DrawEntry>> _preparedPartitionEntries = [];
  final List<bool> _preparedPartitionNeedsClippingMasks = [];
  final List<bool> _preparedPartitionNeedsStencilClear = [];
  final _preparedGraphTiming = PreparedGraphDetailedTimingMetrics();
  final _preparedGraphTemplates = PreparedGraphTemplateCache<Object?>(
    capacity: 4,
  );
  _PreparedGraphState? _preparedGraph;

  ({_PreparedGraphState state, GpuFrameDecode? decoded, bool reused}) prepare(
    FrameCommandMetadata frameMetadata, {
    required bool shouldLog,
  }) {
    final stopwatch = Stopwatch()..start();
    var graphState = _preparedGraph;
    var reusedGraph = false;
    var rebuildReason = PreparedGraphRebuildReason.noGraph;
    int? validationMicros;
    int? refreshMicros;
    var decodeMicros = 0;
    var captureMicros = 0;
    GpuFrameDecode? decoded;
    if (graphState != null) {
      final validationStart = stopwatch.elapsedMicroseconds;
      final view = _decoder.commandView(frameMetadata, shouldLog: shouldLog);
      final graph = graphState.graph;
      final topologyMatches =
          view != null &&
          graph.key.matches(
            commandBytes: view.commandBytes,
            commandCount: view.commandCount,
            commandStride: view.commandStride,
          );
      PreparedGraphKey? cachedTopology;
      if (!topologyMatches && view != null) {
        _preparedGraphTemplates.remember(key: graph.key, value: null);
        cachedTopology = _preparedGraphTemplates
            .takeMatching(
              commandBytes: view.commandBytes,
              commandCount: view.commandCount,
              commandStride: view.commandStride,
            )
            ?.key;
      }
      validationMicros = stopwatch.elapsedMicroseconds - validationStart;
      if (topologyMatches) {
        final activeView = view;
        final refreshStart = stopwatch.elapsedMicroseconds;
        final refreshed = _decoder.refreshEntries(
          graph.entries,
          activeView.commandData,
          shouldLog: shouldLog,
        );
        refreshMicros = stopwatch.elapsedMicroseconds - refreshStart;
        if (refreshed) {
          reusedGraph = true;
          decoded = (
            commandBytes: activeView.commandBytes,
            commandData: activeView.commandData,
            commandCount: graph.commandCount,
            uniformAlignment: graph.uniformAlignment,
            uniformCursor: graph.uniformCursor,
            hasMapGlobalUniform: graph.hasMapGlobalUniform,
            lastFillExtrusionLayerIndex: graph.lastFillExtrusionLayerIndex,
          );
        } else {
          rebuildReason = .refreshFailed;
        }
      } else if (cachedTopology != null) {
        final activeView = view!;
        final refreshStart = stopwatch.elapsedMicroseconds;
        final restored = _restorePreparedGraphTemplate(
          cachedTopology,
          activeView.commandData,
          shouldLog: shouldLog,
        );
        refreshMicros = stopwatch.elapsedMicroseconds - refreshStart;
        if (restored != null) {
          graphState = restored;
          reusedGraph = true;
          final restoredGraph = restored.graph;
          decoded = (
            commandBytes: activeView.commandBytes,
            commandData: activeView.commandData,
            commandCount: restoredGraph.commandCount,
            uniformAlignment: restoredGraph.uniformAlignment,
            uniformCursor: restoredGraph.uniformCursor,
            hasMapGlobalUniform: restoredGraph.hasMapGlobalUniform,
            lastFillExtrusionLayerIndex:
                restoredGraph.lastFillExtrusionLayerIndex,
          );
        } else {
          rebuildReason = .refreshFailed;
        }
      } else {
        rebuildReason = .topologyMismatch;
      }
    }
    if (!reusedGraph) {
      final decodeStart = stopwatch.elapsedMicroseconds;
      _resetPreparedGraphStorage();
      decoded = _decoder.decodeCommands(frameMetadata, shouldLog: shouldLog);
      decodeMicros = stopwatch.elapsedMicroseconds - decodeStart;
      final captureStart = stopwatch.elapsedMicroseconds;
      final graphKey = decoded == null
          ? PreparedGraphKey.nonReusable(
              commandCount: frameMetadata.commandCount,
              commandStride: frameMetadata.commandStride,
            )
          : PreparedGraphKey.capture(
              commandBytes: decoded.commandBytes,
              commandCount: decoded.commandCount,
              commandStride: frameMetadata.commandStride,
              activeCommandOffsets: _drawEntries.map(
                (entry) => entry.commandOffset,
              ),
            );
      final graph = PreparedGraph<DrawEntry, _PreparedDrawPartition>(
        key: graphKey,
        entries: _drawEntries,
        partitions: _preparedPartitions,
        uniformAlignment:
            decoded?.uniformAlignment ??
            RendererUboAbi.minimumUniformByteAlignment,
        uniformCursor: decoded?.uniformCursor ?? 0,
        hasMapGlobalUniform: decoded?.hasMapGlobalUniform ?? false,
        commandCount: decoded?.commandCount ?? frameMetadata.commandCount,
        lastFillExtrusionLayerIndex: decoded?.lastFillExtrusionLayerIndex,
      );
      graphState = _PreparedGraphState(graph);
      _preparedGraph = graphState;
      captureMicros = stopwatch.elapsedMicroseconds - captureStart;
    }
    final graphPrepareMicros = stopwatch.elapsedMicroseconds;
    if (reusedGraph) {
      _preparedGraphTiming.recordHit(
        totalMicros: graphPrepareMicros,
        validationMicros: validationMicros!,
        refreshMicros: refreshMicros!,
      );
    } else {
      _preparedGraphTiming.recordRebuild(
        totalMicros: graphPrepareMicros,
        reason: rebuildReason,
        validationMicros: validationMicros,
        refreshMicros: refreshMicros,
        decodeMicros: decodeMicros,
        captureMicros: captureMicros,
      );
    }
    return (state: graphState!, decoded: decoded, reused: reusedGraph);
  }

  /// Clears topology-owned storage before decoding a different graph.
  void _resetPreparedGraphStorage() {
    _preparedGraph = null;
    for (final partition in _preparedPartitions) {
      partition.entries.clear();
      partition.needsMainDepthStencil = false;
    }
    _decoder.resetEntries();
  }

  _PreparedGraphState? _restorePreparedGraphTemplate(
    PreparedGraphKey key,
    ByteData commandData, {
    required bool shouldLog,
  }) {
    if (!key.reusable) return null;
    _resetPreparedGraphStorage();
    final backendAlignment = gpu.gpuContext.minimumUniformByteAlignment;
    final uniformAlignment =
        backendAlignment < RendererUboAbi.minimumUniformByteAlignment
        ? RendererUboAbi.minimumUniformByteAlignment
        : backendAlignment;
    var uniformCursor = 0;
    var lineCommandCount = 0;
    var hasTriangulatedOutline = false;
    int? lastFillExtrusionLayerIndex;
    for (var index = 0; index < key.commands.length; index += 1) {
      final topology = key.commands[index];
      if (topology.shader == ShaderType.fillExtrusion) {
        lastFillExtrusionLayerIndex = topology.layer;
      }
      if (!topology.active) continue;
      final entry = _decoder.acquireDrawEntry(
        index * key.commandStride,
        topology.shader,
        topology.drawMode,
        topology.flags,
        topology.layer,
        0,
        0,
        null,
        null,
        null,
        TextureFilterType.linear,
        0,
        topology.stencilMode,
        topology.subLayerIndex,
      );
      entry.pipelineKey = topology.stencilMode == StencilModeType.clear
          ? null
          : pipelineKeyFor(shader: topology.shader, flags: topology.flags);
      entry.depthPipelineKey = depthPipelineKeyFor(
        shader: topology.shader,
        flags: topology.flags,
      );
      _drawEntries.add(entry);
      if (topology.stencilMode == StencilModeType.clear) continue;
      if (isLineShader(topology.shader)) lineCommandCount += 1;
      if (topology.shader == ShaderType.fillOutlineTriangulated) {
        hasTriangulatedOutline = true;
      }
      uniformCursor = assignUniformRanges(
        entry,
        uniformCursor,
        uniformAlignment,
      );
    }
    _decoder.releaseUnusedDrawEntries();
    if (!_decoder.refreshEntries(
      _drawEntries,
      commandData,
      shouldLog: shouldLog,
    )) {
      _resetPreparedGraphStorage();

      return null;
    }
    final graph = PreparedGraph<DrawEntry, _PreparedDrawPartition>(
      key: key,
      entries: _drawEntries,
      partitions: _preparedPartitions,
      uniformAlignment: uniformAlignment,
      uniformCursor: uniformCursor,
      hasMapGlobalUniform: frameNeedsMapGlobalUniform(
        lineCommandCount: lineCommandCount,
        hasTriangulatedOutline: hasTriangulatedOutline,
      ),
      commandCount: key.commandCount,
      lastFillExtrusionLayerIndex: lastFillExtrusionLayerIndex,
    );
    final state = _PreparedGraphState(graph);
    _preparedGraph = state;

    return state;
  }

  static bool _sameLayerRanges(
    List<GpuStyleLayerRange> left,
    List<GpuStyleLayerRange> right,
  ) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _partitionPreparedEntries(
    _PreparedGraphState preparedGraph,
    List<GpuStyleLayerRange> layerRanges,
  ) {
    if (!gpuStyleLayerRangesAreOrdered(layerRanges)) {
      throw ArgumentError.value(
        layerRanges,
        'layerRanges',
        'must be sorted and non-overlapping',
      );
    }
    while (_preparedPartitions.length < layerRanges.length) {
      final partition = _PreparedDrawPartition();
      _preparedPartitions.add(partition);
      _preparedPartitionEntries.add(partition.entries);
      _preparedPartitionNeedsClippingMasks.add(false);
      _preparedPartitionNeedsStencilClear.add(false);
    }
    for (final partition in _preparedPartitions) {
      partition.needsMainDepthStencil = false;
    }
    for (var index = 0; index < layerRanges.length; index += 1) {
      _preparedPartitions[index].range = layerRanges[index];
    }
    partitionDrawEntriesByStyleLayerRanges(
      entries: preparedGraph.graph.entries,
      ranges: layerRanges,
      partitions: _preparedPartitionEntries,
      clippingMaskPartitions: _preparedPartitionNeedsClippingMasks,
      stencilClearPartitions: _preparedPartitionNeedsStencilClear,
    );
    for (var index = 0; index < layerRanges.length; index += 1) {
      final partition = _preparedPartitions[index];
      sortClippingRunsBySubLayer(partition.entries);
      for (final entry in partition.entries) {
        if (entry.stencilMode == StencilModeType.clear ||
            commandNeedsDepthStencil(
              shader: entry.shader,
              flags: entry.flags,
              stencilMode: entry.stencilMode,
            )) {
          partition.needsMainDepthStencil = true;
          break;
        }
      }
    }
    preparedGraph.layerRanges = .unmodifiable(layerRanges);
  }

  void _prepareEntryPipelineState(
    ByteData uniformData, {
    required bool initializePipelines,
  }) {
    for (final entry in _drawEntries) {
      if (initializePipelines) {
        entry.pipelineKey = entry.stencilMode == StencilModeType.clear
            ? null
            : pipelineKeyFor(shader: entry.shader, flags: entry.flags);
        entry.depthPipelineKey = depthPipelineKeyFor(
          shader: entry.shader,
          flags: entry.flags,
        );
      }
      entry.fillExtrusionOpacity =
          entry.shader == ShaderType.fillExtrusion &&
              entry.stencilMode != StencilModeType.clear
          ? uniformData.getFloat32(
              entry.propsUniformOffset +
                  RendererUboAbi.fillExtrusionOpacityOffset,
              Endian.little,
            )
          : 1.0;
    }
  }

  void dispose() {
    _preparedGraph = null;
    _preparedGraphTemplates.clear();
    for (final partition in _preparedPartitions) {
      partition.entries.clear();
    }
    _preparedPartitions.clear();
    _preparedPartitionEntries.clear();
    _preparedPartitionNeedsClippingMasks.clear();
    _preparedPartitionNeedsStencilClear.clear();
    _decoder.dispose();
  }
}

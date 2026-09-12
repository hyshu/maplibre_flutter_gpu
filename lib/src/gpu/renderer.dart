import 'dart:ffi' hide Size;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vector_math;

import '../frame/command_layout.dart';
import '../frame/draw_flags.dart';
import '../frame/frame_command_summary.dart';
import '../frame/pipeline_key.dart';
import '../frame/render_pass_plan.dart';
import '../frame/ubo_abi.dart';
import '../native/abi_generated.dart';
import '../native/draw_command.dart';
import '../native/maplibre_ffi.dart';
import 'command_decoder.dart';
import 'draw_entry.dart';
import 'frame_binder.dart';
import 'frame_uniforms.dart';
import 'pass_executor.dart';
import 'pipeline_registry.dart';
import 'prepared_graph.dart';
import 'prepared_graph_metrics.dart';
import 'render_context.dart';
import 'renderer_diagnostics.dart';
import 'resource_cache.dart';
import 'style_layer_partition.dart';

export 'frame_uniforms.dart' show mapGlobalUniformValues;
export 'style_layer_partition.dart';

typedef _FrameDrawResult = ({int drawCount, int renderPassCount});

typedef _PreparedFrameKey = ({
  int frameSequence,
  int commandsAddress,
  int commandCount,
  int commandStride,
  int physicalWidth,
  int physicalHeight,
  double logicalWidth,
  double logicalHeight,
  double devicePixelRatio,
});

final class _PreparedDrawPartition {
  final List<DrawEntry> entries = [];
  GpuStyleLayerRange range = (minimumLayerIndex: null, maximumLayerIndex: null);
  bool needsMainDepthStencil = false;
}

final class _PreparedGraphState {
  new(this.graph);

  final PreparedGraph<DrawEntry, _PreparedDrawPartition> graph;
  List<GpuStyleLayerRange> layerRanges = const [];
}

/// Per-frame bindings that replay one persistent decoded GPU graph.
///
/// The graph survives native frame generations while its structural command
/// topology remains unchanged. Uniforms and frame-owned resources are refreshed
/// before this value is created.
final class GpuPreparedFrame {
  new _({
    required this._key,
    required this._graphState,
    required this.binder,
    required this.uniformData,
    required this.shouldLog,
    required this.uboMicros,
  });

  final _PreparedFrameKey _key;
  final _PreparedGraphState _graphState;
  List<GpuStyleLayerRange> get layerRanges => _graphState.layerRanges;
  final FrameBinder? binder;
  final ByteData uniformData;
  int get commandCount => _graphState.graph.commandCount;
  int? get lastFillExtrusionLayerIndex =>
      _graphState.graph.lastFillExtrusionLayerIndex;
  bool shouldLog;
  final int uboMicros;
  int drawCount = 0;
  int renderPassCount = 0;

  /// Whether [stratumIndex] contains at least one admitted native command.
  bool hasCommandsInStratum(int stratumIndex) =>
      stratumIndex >= 0 &&
      stratumIndex < layerRanges.length &&
      _graphState.graph.partitions[stratumIndex].entries.isNotEmpty;
}

/// Decodes native draw commands and records them as Flutter GPU render passes.
class GpuFrameRenderer {
  final MaplibreBridge bridge;
  final MapPipelineRegistry _pipelines;
  final _resourceCache = GpuResourceCache();
  final _passes = FramePassExecutor();
  final _uniforms = GpuFrameUniforms();
  gpu.Texture? _mainDepthStencilTexture;
  var _mainDepthStencilWidth = 0;
  var _mainDepthStencilHeight = 0;
  var _sharedDepthStencilInitialized = false;
  var _commandLayerSummaryFrameSeq = -1;
  var _commandLayerSummaryAddress = 0;
  var _commandLayerSummaryCount = 0;
  var _commandLayerSummaryStride = 0;
  Set<int> _commandLayerIndices = const {};
  late final _decoder = GpuCommandDecoder(_resourceCache);
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
  GpuPreparedFrame? _preparedFrame;
  var _resourceFrameNeedsFinalization = false;
  var _resourceCacheNeedsEviction = false;
  final List<RenderPassPlan> _renderPassPlans = [];
  final List<RenderPassPlan> _renderPassPlanPool = [];
  double zoom = 0;
  int frameSeq = 0;
  final _logSw = Stopwatch()..start();

  /// Creates a renderer backed by [bridge].
  new({required this.bridge, required gpu.ShaderLibrary shaders})
    : _pipelines = MapPipelineRegistry(shaders) {
    _passes.initialize(shaders);
    _pipelines.prewarmFillExtrusionPipelines();
  }

  /// Creates an overlay pass with the same attachment semantics as map passes.
  gpu.RenderPass createOverlayRenderPass(
    gpu.CommandBuffer commandBuffer,
    gpu.RenderTarget target,
  ) => _passes.createRenderPass(
    commandBuffer,
    target,
    hasDepthStencilAttachment: target.depthStencilAttachment != null,
  );

  /// Returns style layers represented in [metadata] for the current frame.
  ///
  /// The native bytes are scanned once per renderer frame and shared by all
  /// compositing strata.
  Set<int> commandLayerIndices(FrameCommandMetadata metadata) {
    final address = metadata.commands.address;
    if (_commandLayerSummaryFrameSeq == frameSeq &&
        _commandLayerSummaryAddress == address &&
        _commandLayerSummaryCount == metadata.commandCount &&
        _commandLayerSummaryStride == metadata.commandStride) {
      return _commandLayerIndices;
    }
    _commandLayerSummaryFrameSeq = frameSeq;
    _commandLayerSummaryAddress = address;
    _commandLayerSummaryCount = metadata.commandCount;
    _commandLayerSummaryStride = metadata.commandStride;
    if (address == 0 ||
        metadata.commandCount <= 0 ||
        metadata.commandStride != DrawCommandAbi.size) {
      _commandLayerIndices = const {};

      return _commandLayerIndices;
    }
    _commandLayerIndices = frameCommandLayerIndices(
      commands: metadata.commands.cast<Uint8>().asTypedList(
        metadata.commandCount * metadata.commandStride,
      ),
      commandCount: metadata.commandCount,
      commandStride: metadata.commandStride,
      layerIndexOffset: DrawCommandAbi.layerIndex,
      expectedStride: DrawCommandAbi.size,
    );

    return _commandLayerIndices;
  }

  /// Whether the backend has rejected depth and stencil attachments.
  ///
  /// Once rejected, later frames use the fallback without attempting another
  /// attachment.
  static var _depthStencilUnsupported = false;

  /// Selects the process-wide fallback after the backend rejects a render pass
  /// that uses the prepared depth and stencil texture.
  void disableDepthStencil(Object error) {
    _depthStencilUnsupported = true;
    _mainDepthStencilTexture = null;
    _mainDepthStencilWidth = 0;
    _mainDepthStencilHeight = 0;
    _sharedDepthStencilInitialized = false;
    debugPrint(
      '[GpuRenderer] depth/stencil attachment unavailable, '
      'falling back to unclipped depth-less rendering: $error',
    );
  }

  /// Returns the shared depth/stencil texture attached to the frame's first
  /// render pass.
  ///
  /// Attaching it from the first pass keeps the framebuffer complete on
  /// backends that reuse one framebuffer for the color texture.
  gpu.Texture? prepareDepthStencilTexture(gpu.Texture colorTexture) {
    if (_depthStencilUnsupported) return null;
    final cached = _mainDepthStencilTexture;
    if (cached != null &&
        _mainDepthStencilWidth == colorTexture.width &&
        _mainDepthStencilHeight == colorTexture.height) {
      return cached;
    }
    try {
      final depth = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        colorTexture.width,
        colorTexture.height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        enableRenderTargetUsage: true,
      );
      _mainDepthStencilTexture = depth;
      _mainDepthStencilWidth = colorTexture.width;
      _mainDepthStencilHeight = colorTexture.height;
      _sharedDepthStencilInitialized = false;

      return depth;
    } catch (e) {
      disableDepthStencil(e);

      return null;
    }
  }

  /// Refreshes one native frame and reuses its persistent graph when safe.
  GpuPreparedFrame prepareFrame({
    required FrameCommandMetadata frameMetadata,
    required int physicalWidth,
    required int physicalHeight,
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
    required List<GpuStyleLayerRange> layerRanges,
    bool advanceResourceFrame = true,
  }) {
    if (layerRanges.isEmpty) {
      throw ArgumentError.value(
        layerRanges,
        'layerRanges',
        'must not be empty',
      );
    }
    final safeDpr = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    final key = (
      frameSequence: frameSeq,
      commandsAddress: frameMetadata.commands.address,
      commandCount: frameMetadata.commandCount,
      commandStride: frameMetadata.commandStride,
      physicalWidth: physicalWidth,
      physicalHeight: physicalHeight,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      devicePixelRatio: safeDpr,
    );
    final current = _preparedFrame;
    if (current != null && current._key == key) {
      if (advanceResourceFrame) beginFrameReplay();
      if (!_sameLayerRanges(current.layerRanges, layerRanges)) {
        _partitionPreparedEntries(current._graphState, layerRanges);
      }
      return current;
    }

    finishFrame();
    _beginPreparedFrame(advanceResourceFrame: advanceResourceFrame);
    final shouldLog = _logSw.elapsedMilliseconds >= 1000;
    if (shouldLog) _logSw.reset();
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
    FrameBinder? binder;
    var uniformData = ByteData(0);
    var uboMicros = 0;
    if (decoded != null && graphState!.graph.entries.isNotEmpty) {
      final layout = layoutFrameUniforms(
        drawableCursor: decoded.uniformCursor,
        alignment: decoded.uniformAlignment,
        hasMapGlobal: decoded.hasMapGlobalUniform,
      );
      final uniformLength = layout.totalBytes;
      uniformData = _uniforms.pack(
        layout,
        entries: _drawEntries,
        commandBytes: decoded.commandBytes,
        commandData: decoded.commandData,
        devicePixelRatio: safeDpr,
        physicalWidth: physicalWidth,
        physicalHeight: physicalHeight,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        hasMapGlobal: decoded.hasMapGlobalUniform,
      );
      uboMicros = stopwatch.elapsedMicroseconds - graphPrepareMicros;
      final uniformBuffer = _uniforms.upload(uniformLength);
      binder = .new(
        pipelines: _pipelines,
        uniformBuffer: uniformBuffer,
        mapGlobalOffset: layout.mapGlobalOffset,
        // Oversize emplacements allocate one-shot DeviceBuffers outside the
        // HostBuffer ring. Never retain those through pooled draw entries.
        cacheUniformViews: _uniforms.canRetainViews(uniformLength),
      );
      _prepareEntryPipelineState(
        uniformData,
        initializePipelines: !reusedGraph,
      );
    }
    final prepared = GpuPreparedFrame._(
      key: key,
      graphState: graphState!,
      binder: binder,
      uniformData: uniformData,
      shouldLog: shouldLog,
      uboMicros: uboMicros,
    );
    _preparedFrame = prepared;
    if (!_sameLayerRanges(graphState.layerRanges, layerRanges)) {
      _partitionPreparedEntries(graphState, layerRanges);
    }
    return prepared;
  }

  /// Replays one prepared layer partition onto [texture].
  int renderPreparedFrame({
    required GpuPreparedFrame preparedFrame,
    required int stratumIndex,
    required gpu.CommandBuffer commandBuffer,
    required gpu.Texture texture,
    required vector_math.Vector4 frameClearColor,
    bool submitEachRenderPass = false,
    gpu.Texture? initialDepthStencilTexture,
    MapLibreGpuRenderCallback? gpuMapRenderCallback,
    MapLibreGpuMapTransform? mapTransform,
  }) {
    try {
      return _renderPreparedFrameImpl(
        preparedFrame: preparedFrame,
        stratumIndex: stratumIndex,
        commandBuffer: commandBuffer,
        texture: texture,
        frameClearColor: frameClearColor,
        submitEachRenderPass: submitEachRenderPass,
        initialDepthStencilTexture: initialDepthStencilTexture,
        gpuMapRenderCallback: gpuMapRenderCallback,
        mapTransform: mapTransform,
      );
    } on DepthStencilAttachmentError {
      rethrow;
    } catch (e, st) {
      debugPrint('[GpuRenderer] error: $e\n$st');

      return 0;
    }
  }

  int _renderPreparedFrameImpl({
    required GpuPreparedFrame preparedFrame,
    required int stratumIndex,
    required gpu.CommandBuffer commandBuffer,
    required gpu.Texture texture,
    required vector_math.Vector4 frameClearColor,
    required bool submitEachRenderPass,
    gpu.Texture? initialDepthStencilTexture,
    MapLibreGpuRenderCallback? gpuMapRenderCallback,
    MapLibreGpuMapTransform? mapTransform,
  }) {
    if (!identical(preparedFrame, _preparedFrame)) {
      throw StateError('The prepared GPU frame is no longer active');
    }
    if (stratumIndex < 0 || stratumIndex >= preparedFrame.layerRanges.length) {
      throw RangeError.index(
        stratumIndex,
        preparedFrame.layerRanges,
        'stratumIndex',
      );
    }
    final partition = preparedFrame._graphState.graph.partitions[stratumIndex];
    final range = partition.range;
    final effectiveMapCallback =
        gpuMapRenderCallback != null &&
            threeDimensionalCallbackInLayerRange(
              preparedFrame.lastFillExtrusionLayerIndex,
              minimumLayerIndex: range.minimumLayerIndex,
              maximumLayerIndex: range.maximumLayerIndex,
            )
        ? gpuMapRenderCallback
        : null;
    final key = preparedFrame._key;
    final entries = partition.entries;
    if (entries.isEmpty) {
      final clearDepthStencil =
          initialDepthStencilTexture != null && !_sharedDepthStencilInitialized;
      _recordCustomMapPass(
        commandBuffer,
        texture,
        initialDepthStencilTexture,
        frameClearColor: frameClearColor,
        clearColor: true,
        clearDepthStencil: clearDepthStencil,
        callback: effectiveMapCallback,
        logicalWidth: key.logicalWidth,
        logicalHeight: key.logicalHeight,
        devicePixelRatio: key.devicePixelRatio,
        mapTransform: mapTransform,
      );
      if (effectiveMapCallback == null) {
        _passes.clearFramePass(
          commandBuffer,
          texture,
          frameClearColor,
          depthStencilTexture: initialDepthStencilTexture,
          clearDepthStencil: clearDepthStencil,
        );
      }
      if (initialDepthStencilTexture != null) {
        _sharedDepthStencilInitialized = true;
      }
      if (submitEachRenderPass) commandBuffer.submit();

      return 0;
    }
    final drawResult = _recordTexturePasses(
      commandBuffer,
      texture,
      preparedFrame.binder!,
      entries: entries,
      submitEachRenderPass: submitEachRenderPass,
      frameClearColor: frameClearColor,
      uniformData: preparedFrame.uniformData,
      initialDepthStencilTexture: initialDepthStencilTexture,
      needsMainDepthStencil: partition.needsMainDepthStencil,
      customMapCallback: effectiveMapCallback,
      logicalWidth: key.logicalWidth,
      logicalHeight: key.logicalHeight,
      devicePixelRatio: key.devicePixelRatio,
      mapTransform: mapTransform,
    );
    preparedFrame.drawCount += drawResult.drawCount;
    preparedFrame.renderPassCount += drawResult.renderPassCount;

    return drawResult.drawCount;
  }

  /// Renders one independently prepared range and optionally finalizes caches.
  int renderFrame({
    required gpu.CommandBuffer commandBuffer,
    required gpu.Texture texture,
    required vector_math.Vector4 frameClearColor,
    bool submitEachRenderPass = false,
    FrameCommandMetadata? frameMetadata,
    gpu.Texture? initialDepthStencilTexture,
    double? logicalWidth,
    double? logicalHeight,
    double devicePixelRatio = 1,
    MapLibreGpuRenderCallback? gpuMapRenderCallback,
    MapLibreGpuMapTransform? mapTransform,
    int? minimumLayerIndex,
    int? maximumLayerIndex,
    bool advanceResourceFrame = true,
    bool evictResourceCaches = true,
  }) {
    try {
      final safeDpr = devicePixelRatio.isFinite && devicePixelRatio > 0
          ? devicePixelRatio
          : 1.0;
      final prepared = prepareFrame(
        frameMetadata: frameMetadata ?? bridge.frameGetMetadata(),
        physicalWidth: texture.width,
        physicalHeight: texture.height,
        logicalWidth: logicalWidth ?? texture.width / safeDpr,
        logicalHeight: logicalHeight ?? texture.height / safeDpr,
        devicePixelRatio: safeDpr,
        layerRanges: [
          (
            minimumLayerIndex: minimumLayerIndex,
            maximumLayerIndex: maximumLayerIndex,
          ),
        ],
        advanceResourceFrame: advanceResourceFrame,
      );

      return renderPreparedFrame(
        preparedFrame: prepared,
        stratumIndex: 0,
        commandBuffer: commandBuffer,
        texture: texture,
        frameClearColor: frameClearColor,
        submitEachRenderPass: submitEachRenderPass,
        initialDepthStencilTexture: initialDepthStencilTexture,
        gpuMapRenderCallback: gpuMapRenderCallback,
        mapTransform: mapTransform,
      );
    } on DepthStencilAttachmentError {
      rethrow;
    } catch (e, st) {
      debugPrint('[GpuRenderer] error: $e\n$st');

      return 0;
    } finally {
      if (evictResourceCaches) finishFrame();
    }
  }

  /// Runs cache maintenance after the last stratum has handled the frame.
  void finishFrame() {
    if (!_resourceFrameNeedsFinalization) return;
    _resourceFrameNeedsFinalization = false;
    final evictResourceCaches = _resourceCacheNeedsEviction;
    _resourceCacheNeedsEviction = false;
    final prepared = _preparedFrame;
    if (prepared != null && prepared.shouldLog) {
      prepared.shouldLog = false;
      logGpuFrameSummary(
        zoom: zoom,
        entries: prepared._graphState.graph.entries,
        commandCount: prepared.commandCount,
        drawCount: prepared.drawCount,
        renderPassCount: prepared.renderPassCount,
        uboMicros: prepared.uboMicros,
        graphTiming: _preparedGraphTiming.takeSnapshotAndReset(),
      );
      logGpuResourceSummary(_resourceCache);
    }
    if (evictResourceCaches) _resourceCache.evictCaches();
  }

  /// Starts another replay of the current preparation without re-uploading it.
  void beginFrameReplay() {
    final prepared = _preparedFrame;
    if (prepared == null || _resourceFrameNeedsFinalization) return;
    _passes.beginFrame();
    _resourceFrameNeedsFinalization = true;
    _sharedDepthStencilInitialized = false;
    prepared.drawCount = 0;
    prepared.renderPassCount = 0;
  }

  /// Starts per-frame resources without discarding stable graph state.
  void _beginPreparedFrame({required bool advanceResourceFrame}) {
    _passes.beginFrame();
    if (advanceResourceFrame) _resourceCache.beginFrame();
    _resourceFrameNeedsFinalization = true;
    _resourceCacheNeedsEviction = true;
    _preparedFrame = null;
    _sharedDepthStencilInitialized = false;
    _uniforms.beginFrame();
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

  /// Replays the frame onto [texture] in logical render passes.
  ///
  /// Adjacent pipeline runs keep MapLibre's emission order, but compatible runs
  /// share a logical pass. Stencil clears, custom callbacks, and depth-write
  /// changes remain logical pass barriers. Android records these passes inside
  /// one native render pass.
  _FrameDrawResult _recordTexturePasses(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture texture,
    FrameBinder binder, {
    required List<DrawEntry> entries,
    required bool submitEachRenderPass,
    required vector_math.Vector4 frameClearColor,
    required ByteData uniformData,
    required gpu.Texture? initialDepthStencilTexture,
    required bool needsMainDepthStencil,
    required MapLibreGpuRenderCallback? customMapCallback,
    required double? logicalWidth,
    required double? logicalHeight,
    required double devicePixelRatio,
    required MapLibreGpuMapTransform? mapTransform,
  }) {
    var drawCount = 0;
    var renderPassCount = 0;

    // Keep the combined attachment even when a run does not use depth or
    // stencil. Android shares one framebuffer across the surface's passes.
    final mainDepthStencilTexture =
        initialDepthStencilTexture ??
        (needsMainDepthStencil || customMapCallback != null
            ? prepareDepthStencilTexture(texture)
            : null);

    var colorInitialized = false;
    var attachmentInitialized = _sharedDepthStencilInitialized;
    var currentCommandBuffer = commandBuffer;
    var hasRecordedPass = false;
    gpu.RenderPass? activePass;
    bool? activeDepthWrite;
    gpu.CommandBuffer nextPassCommandBuffer() {
      if (submitEachRenderPass && hasRecordedPass) {
        currentCommandBuffer.submit();
        currentCommandBuffer = gpu.gpuContext.createCommandBuffer();
      }
      hasRecordedPass = true;

      return currentCommandBuffer;
    }

    final passPlans = planRenderPasses(
      entries,
      hasDepthStencilAttachment: mainDepthStencilTexture != null,
      attachmentInitiallyInitialized: attachmentInitialized,
      output: _renderPassPlans,
      pool: _renderPassPlanPool,
    );
    final customMapInsertionIndex = threeDimensionalRenderInsertionIndex(
      passPlans,
      entries,
    );
    for (var planIndex = 0; planIndex < passPlans.length; planIndex++) {
      final plan = passPlans[planIndex];
      final first = entries[plan.start];
      if (plan.kind == .stencilClear) {
        activePass = null;
        activeDepthWrite = null;
        if (mainDepthStencilTexture != null) {
          _passes.clearStencilPass(
            nextPassCommandBuffer(),
            texture,
            frameClearColor,
            mainDepthStencilTexture,
            clearColor: !colorInitialized,
            attachmentInitialized: !plan.clearDepth,
            clearValue: first.stencilReference,
          );
          renderPassCount++;
          colorInitialized = true;
          attachmentInitialized = true;
        }
      } else {
        final isDepthPrepass = plan.kind == .fillExtrusionDepth;
        final pipeline = isDepthPrepass
            ? binder.depthPipelineFor(first)
            : binder.pipelineFor(first);
        if (activePass == null || activeDepthWrite != plan.depthWrite) {
          final initializeDepthStencil =
              mainDepthStencilTexture != null && !attachmentInitialized;
          activePass = _passes.beginOverlayPass(
            nextPassCommandBuffer(),
            texture,
            frameClearColor,
            clearColor: !colorInitialized,
            depthStencilTexture: mainDepthStencilTexture,
            clearDepth: initializeDepthStencil,
            clearStencil: initializeDepthStencil,
            depthWrite: plan.depthWrite,
          );
          activeDepthWrite = plan.depthWrite;
          renderPassCount++;
          colorInitialized = true;
          if (mainDepthStencilTexture != null) attachmentInitialized = true;
        }
        drawCount += _passes.drawRun(
          activePass,
          pipeline,
          entries,
          plan.start,
          plan.end,
          binder,
          hasDepthStencilAttachment: mainDepthStencilTexture != null,
          propsAreRunConstant: _runHasConstantProps(
            entries,
            plan.start,
            plan.end,
            uniformData,
          ),
          setPrimitive: plan.setPrimitive,
          depthTest: plan.depthTest,
          stencilMode: plan.stencilMode,
          cullBackFaces: plan.cullBackFaces,
        );
      }
      if (planIndex + 1 == customMapInsertionIndex &&
          customMapCallback != null) {
        _recordCustomMapPass(
          nextPassCommandBuffer(),
          texture,
          mainDepthStencilTexture,
          frameClearColor: frameClearColor,
          clearColor: !colorInitialized,
          clearDepthStencil:
              mainDepthStencilTexture != null && !attachmentInitialized,
          callback: customMapCallback,
          logicalWidth: logicalWidth,
          logicalHeight: logicalHeight,
          devicePixelRatio: devicePixelRatio,
          mapTransform: mapTransform,
        );
        renderPassCount++;
        colorInitialized = true;
        if (mainDepthStencilTexture != null) attachmentInitialized = true;
        activePass = null;
        activeDepthWrite = null;
      }
    }
    if (passPlans.isEmpty && customMapCallback != null) {
      _recordCustomMapPass(
        nextPassCommandBuffer(),
        texture,
        mainDepthStencilTexture,
        frameClearColor: frameClearColor,
        clearColor: true,
        clearDepthStencil: mainDepthStencilTexture != null,
        callback: customMapCallback,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        devicePixelRatio: devicePixelRatio,
        mapTransform: mapTransform,
      );
      renderPassCount++;
      colorInitialized = true;
      if (mainDepthStencilTexture != null) attachmentInitialized = true;
    }
    if (!colorInitialized) {
      _passes.clearFramePass(
        nextPassCommandBuffer(),
        texture,
        frameClearColor,
        depthStencilTexture: mainDepthStencilTexture,
        clearDepthStencil:
            mainDepthStencilTexture != null && !attachmentInitialized,
      );
      renderPassCount++;
      if (mainDepthStencilTexture != null) attachmentInitialized = true;
    }
    if (submitEachRenderPass && hasRecordedPass) currentCommandBuffer.submit();
    if (mainDepthStencilTexture != null && attachmentInitialized) {
      _sharedDepthStencilInitialized = true;
    }
    return (drawCount: drawCount, renderPassCount: renderPassCount);
  }

  static bool _runHasConstantProps(
    List<DrawEntry> entries,
    int start,
    int end,
    ByteData uniformData,
  ) {
    if (end - start < 2) return true;
    final first = entries[start];
    final length = first.propsUniformLength;
    if (length == 0) return true;
    final firstOffset = first.propsUniformOffset;
    for (var index = start + 1; index < end; index++) {
      final entry = entries[index];
      if (entry.propsUniformLength != length) return false;
      final offset = entry.propsUniformOffset;
      var byte = 0;
      for (; byte + 8 <= length; byte += 8) {
        if (uniformData.getUint64(firstOffset + byte) !=
            uniformData.getUint64(offset + byte)) {
          return false;
        }
      }
      for (; byte < length; byte++) {
        if (uniformData.getUint8(firstOffset + byte) !=
            uniformData.getUint8(offset + byte)) {
          return false;
        }
      }
    }
    return true;
  }

  void _recordCustomMapPass(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture texture,
    gpu.Texture? depthStencilTexture, {
    required vector_math.Vector4 frameClearColor,
    required bool clearColor,
    required bool clearDepthStencil,
    required MapLibreGpuRenderCallback? callback,
    required double? logicalWidth,
    required double? logicalHeight,
    required double devicePixelRatio,
    required MapLibreGpuMapTransform? mapTransform,
  }) {
    if (callback == null) return;
    final renderTarget = _passes.renderTarget(
      texture,
      frameClearColor,
      clearColor: clearColor,
      depthStencilTexture: depthStencilTexture,
      clearDepth: clearDepthStencil,
      clearStencil: clearDepthStencil,
    );
    final renderPass = _passes.createRenderPass(
      commandBuffer,
      renderTarget,
      hasDepthStencilAttachment: depthStencilTexture != null,
    );
    try {
      callback(
        .new(
          gpuContext: gpu.gpuContext,
          renderPass: renderPass,
          logicalSize: Size(
            logicalWidth ?? texture.width / devicePixelRatio,
            logicalHeight ?? texture.height / devicePixelRatio,
          ),
          physicalSize: Size(
            texture.width.toDouble(),
            texture.height.toDouble(),
          ),
          devicePixelRatio: devicePixelRatio,
          frameSequence: frameSeq,
          mapTransform: mapTransform,
          hasDepthStencilAttachment: depthStencilTexture != null,
          depthMode: .shared,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[GpuRenderer] gpuMapRenderCallback error: $error\n$stackTrace',
      );
    }
  }

  /// Releases resources owned by this renderer.
  void dispose() {
    _resourceCache.dispose();
    _preparedGraph = null;
    _preparedGraphTemplates.clear();
    _preparedFrame = null;
    _resourceFrameNeedsFinalization = false;
    _resourceCacheNeedsEviction = false;
    for (final partition in _preparedPartitions) {
      partition.entries.clear();
    }
    _preparedPartitions.clear();
    _preparedPartitionEntries.clear();
    _preparedPartitionNeedsClippingMasks.clear();
    _preparedPartitionNeedsStencilClear.clear();
    _mainDepthStencilTexture = null;
    _mainDepthStencilWidth = 0;
    _mainDepthStencilHeight = 0;
    _sharedDepthStencilInitialized = false;
    _uniforms.dispose();
    _decoder.dispose();
    _renderPassPlans.clear();
    _renderPassPlanPool.clear();
    _passes.releaseResources();
  }
}

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
import '../native/frame_metadata.dart';
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

part 'renderer/prepared_frame.dart';
part 'renderer/graph_preparer.dart';
part 'renderer/frame_replay.dart';

/// Decodes native draw commands and records them as Flutter GPU render passes.
class GpuFrameRenderer {
  final MapPipelineRegistry _pipelines;
  final _resourceCache = GpuResourceCache();
  final _GpuFrameReplay _replay;
  final _uniforms = GpuFrameUniforms();
  var _commandLayerSummaryFrameSeq = -1;
  var _commandLayerSummaryAddress = 0;
  var _commandLayerSummaryCount = 0;
  var _commandLayerSummaryStride = 0;
  Set<int> _commandLayerIndices = const {};
  late final _graphs = _GpuFrameGraphPreparer(_resourceCache);
  GpuPreparedFrame? _preparedFrame;
  var _resourceFrameNeedsFinalization = false;
  var _resourceCacheNeedsEviction = false;
  double zoom = 0;
  int frameSeq = 0;
  final _logSw = Stopwatch()..start();

  /// Creates a renderer with pipelines from [shaders].
  new({required gpu.ShaderLibrary shaders})
    : _pipelines = MapPipelineRegistry(shaders),
      _replay = _GpuFrameReplay(shaders) {
    _pipelines.prewarmFillExtrusionPipelines();
  }

  /// Creates an overlay pass with the same attachment semantics as map passes.
  gpu.RenderPass createOverlayRenderPass(
    gpu.CommandBuffer commandBuffer,
    gpu.RenderTarget target,
  ) => _replay.createOverlayRenderPass(commandBuffer, target);

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

  /// Selects the process-wide fallback after a rejected depth/stencil pass.
  void disableDepthStencil(Object error) => _replay.disableDepthStencil(error);

  /// Returns the shared attachment used from the frame's first render pass.
  gpu.Texture? prepareDepthStencilTexture(gpu.Texture colorTexture) =>
      _replay.prepareDepthStencilTexture(colorTexture);

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
      if (!_GpuFrameGraphPreparer._sameLayerRanges(
        current.layerRanges,
        layerRanges,
      )) {
        _graphs._partitionPreparedEntries(current._graphState, layerRanges);
      }
      return current;
    }

    finishFrame();
    _beginPreparedFrame(advanceResourceFrame: advanceResourceFrame);
    final shouldLog = _logSw.elapsedMilliseconds >= 1000;
    if (shouldLog) _logSw.reset();
    final stopwatch = Stopwatch()..start();
    final graphPreparation = _graphs.prepare(
      frameMetadata,
      shouldLog: shouldLog,
    );
    final graphState = graphPreparation.state;
    final decoded = graphPreparation.decoded;
    final reusedGraph = graphPreparation.reused;
    final graphPrepareMicros = stopwatch.elapsedMicroseconds;
    FrameBinder? binder;
    var uniformData = ByteData(0);
    var uboMicros = 0;
    if (decoded != null && graphState.graph.entries.isNotEmpty) {
      final layout = layoutFrameUniforms(
        drawableCursor: decoded.uniformCursor,
        alignment: decoded.uniformAlignment,
        hasMapGlobal: decoded.hasMapGlobalUniform,
      );
      final uniformLength = layout.totalBytes;
      uniformData = _uniforms.pack(
        layout,
        entries: _graphs._drawEntries,
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
      _graphs._prepareEntryPipelineState(
        uniformData,
        initializePipelines: !reusedGraph,
      );
    }
    final prepared = GpuPreparedFrame._(
      key: key,
      graphState: graphState,
      binder: binder,
      uniformData: uniformData,
      shouldLog: shouldLog,
      uboMicros: uboMicros,
    );
    _preparedFrame = prepared;
    if (!_GpuFrameGraphPreparer._sameLayerRanges(
      graphState.layerRanges,
      layerRanges,
    )) {
      _graphs._partitionPreparedEntries(graphState, layerRanges);
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
      if (!identical(preparedFrame, _preparedFrame)) {
        throw StateError('The prepared GPU frame is no longer active');
      }

      return _replay.render(
        frameSequence: frameSeq,
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
        graphTiming: _graphs._preparedGraphTiming.takeSnapshotAndReset(),
      );
      logGpuResourceSummary(_resourceCache);
    }
    if (evictResourceCaches) _resourceCache.evictCaches();
  }

  /// Starts another replay of the current preparation without re-uploading it.
  void beginFrameReplay() {
    final prepared = _preparedFrame;
    if (prepared == null || _resourceFrameNeedsFinalization) return;
    _replay.beginFrame();
    _resourceFrameNeedsFinalization = true;
    prepared.drawCount = 0;
    prepared.renderPassCount = 0;
  }

  /// Starts per-frame resources without discarding stable graph state.
  void _beginPreparedFrame({required bool advanceResourceFrame}) {
    _replay.beginFrame();
    if (advanceResourceFrame) _resourceCache.beginFrame();
    _resourceFrameNeedsFinalization = true;
    _resourceCacheNeedsEviction = true;
    _preparedFrame = null;
    _uniforms.beginFrame();
  }

  /// Releases resources owned by this renderer.
  void dispose() {
    _resourceCache.dispose();
    _graphs.dispose();
    _preparedFrame = null;
    _resourceFrameNeedsFinalization = false;
    _resourceCacheNeedsEviction = false;
    _uniforms.dispose();
    _replay.dispose();
  }
}

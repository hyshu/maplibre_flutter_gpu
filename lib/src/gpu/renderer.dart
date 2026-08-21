import 'dart:ffi' hide Size;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vector_math;

import 'draw_entry.dart';
import 'frame_binder.dart';
import 'pass_executor.dart';
import 'pipeline_registry.dart';
import 'prepared_graph.dart';
import 'prepared_graph_metrics.dart';
import 'render_context.dart';
import 'resource_cache.dart';
import '../native/abi_generated.dart';
import '../native/draw_command.dart';
import '../native/maplibre_ffi.dart';
import '../frame/command_layout.dart';
import '../frame/draw_command_admission.dart';
import '../frame/draw_flags.dart';
import '../frame/frame_command_summary.dart';
import '../frame/pipeline_key.dart';
import '../frame/render_pass_plan.dart';
import '../frame/ubo_abi.dart';
import '../frame/uniform_packer.dart';
import '../frame/vertex_repack.dart';

// DrawCommand fields use offsets generated in DrawCommandAbi from the native
// ABI. Do not duplicate those offsets locally because the copies can drift.

/// Values mirrored from MapLibre's `GlobalPaintParamsUBO` for shaders that
/// need viewport-space calculations.
///
/// `units_to_pixels` uses the logical map size. `world_size` uses the physical
/// render target size.
@visibleForTesting
({double unitsX, double unitsY, double worldWidth, double worldHeight})
mapGlobalUniformValues({
  required double logicalWidth,
  required double logicalHeight,
  required int physicalWidth,
  required int physicalHeight,
}) => (
  unitsX: logicalWidth / 2.0,
  unitsY: -logicalHeight / 2.0,
  worldWidth: physicalWidth.toDouble(),
  worldHeight: physicalHeight.toDouble(),
);

/// A view over the [byteLength] bytes native owns at [dataAddress].
///
/// The bytes are borrowed rather than copied and remain valid only until the
/// native frame that exported them ends. Callers must upload them before
/// returning.
Uint8List _nativeBytes(int dataAddress, int byteLength) =>
    Pointer<Uint8>.fromAddress(dataAddress).asTypedList(byteLength);

/// Copies [bytes] into a fresh device buffer.
GpuBufferEntry _uploadBuffer(Uint8List bytes, {bool isFillExtrusion = false}) =>
    GpuBufferEntry(
      gpu.gpuContext.createDeviceBufferWithCopy(ByteData.sublistView(bytes)),
      bytes.lengthInBytes,
      isFillExtrusion: isFillExtrusion,
    );

/// Reserves an entry's uniform ranges in the frame's uniform block and returns
/// the cursor past them.
///
/// Every range is aligned for binding, so the cursor advances by more than the
/// UBO sizes alone.
int _assignUniformRanges(DrawEntry entry, int cursor, int alignment) {
  final uboLayout = rendererUboLayoutForShader(entry.shader);
  entry.drawableUniformOffset = alignUniformOffset(cursor, alignment);
  entry.propsUniformOffset = alignUniformOffset(
    entry.drawableUniformOffset + uboLayout.drawableBytes,
    alignment,
  );
  entry.drawableUniformLength = uboLayout.drawableBytes;
  entry.propsUniformLength = uboLayout.propsBytes;
  var next = entry.propsUniformOffset + uboLayout.propsBytes;
  if (uboLayout.tilePropsBytes > 0) {
    entry.tilePropsUniformOffset = alignUniformOffset(next, alignment);
    entry.tilePropsUniformLength = uboLayout.tilePropsBytes;
    next = entry.tilePropsUniformOffset + uboLayout.tilePropsBytes;
  }
  return next;
}

/// Restores sublayer order within one layer while keeping stencil setup
/// barriers fixed in the native command stream.
///
/// Only contiguous clipping-test commands for the same layer are stably
/// sorted. This preserves established tile masks and command order outside
/// each run.
void sortClippingRunsBySubLayer(
  List<DrawEntry> entries, [
  ByteData? commandData,
]) {
  int subLayerOf(DrawEntry entry) => commandData == null
      ? entry.subLayerIndex
      : commandData.getInt32(
          entry.commandOffset + DrawCommandAbi.subLayerIndex,
          Endian.little,
        );

  var start = 0;
  while (start < entries.length) {
    final first = entries[start];
    if (first.stencilMode != StencilModeType.clippingTest) {
      start += 1;
      continue;
    }
    final layer = first.layer;
    var end = start + 1;
    while (end < entries.length &&
        entries[end].stencilMode == StencilModeType.clippingTest &&
        entries[end].layer == layer) {
      end += 1;
    }
    for (var index = start + 1; index < end; index += 1) {
      final entry = entries[index];
      final subLayer = subLayerOf(entry);
      var insertion = index;
      while (insertion > start) {
        final previous = entries[insertion - 1];
        final previousSubLayer = subLayerOf(previous);
        if (previousSubLayer <= subLayer) break;
        entries[insertion] = previous;
        insertion -= 1;
      }
      entries[insertion] = entry;
    }
    start = end;
  }
}

/// Frame-wide state produced after every command has been decoded.
typedef _FrameDecode = ({
  Uint8List commandBytes,
  ByteData commandData,
  int commandCount,
  int uniformAlignment,
  int uniformCursor,
  bool hasMapGlobalUniform,
  int? lastFillExtrusionLayerIndex,
});

typedef _CommandView = ({
  Uint8List commandBytes,
  ByteData commandData,
  int commandCount,
  int commandStride,
});

typedef _FrameDrawResult = ({int drawCount, int renderPassCount});

/// One native style layer interval assigned to a compositing stratum.
typedef GpuStyleLayerRange = ({int? minimumLayerIndex, int? maximumLayerIndex});

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
  final List<DrawEntry> entries = <DrawEntry>[];
  GpuStyleLayerRange range = (minimumLayerIndex: null, maximumLayerIndex: null);
  bool needsMainDepthStencil = false;
}

final class _PreparedGraphState {
  _PreparedGraphState(this.graph);

  final PreparedGraph<DrawEntry, _PreparedDrawPartition> graph;
  List<GpuStyleLayerRange> layerRanges = const <GpuStyleLayerRange>[];
}

/// Per-frame bindings that replay one persistent decoded GPU graph.
///
/// The graph survives native frame generations while its structural command
/// topology remains unchanged. Uniforms and frame-owned resources are refreshed
/// before this value is created.
final class GpuPreparedFrame {
  GpuPreparedFrame._({
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

/// Whether a native style layer belongs to one compositing stratum.
///
/// Bounds are inclusive at [minimumLayerIndex] and exclusive at
/// [maximumLayerIndex]. Null leaves that side unbounded.
@visibleForTesting
bool layerIndexInRange(
  int layerIndex, {
  int? minimumLayerIndex,
  int? maximumLayerIndex,
}) =>
    (minimumLayerIndex == null || layerIndex >= minimumLayerIndex) &&
    (maximumLayerIndex == null || layerIndex < maximumLayerIndex);

/// Returns the ordered compositing range containing [layerIndex].
///
/// The input ranges must be sorted and non-overlapping. Gaps are allowed.
@visibleForTesting
int? gpuStyleLayerRangeIndex(int layerIndex, List<GpuStyleLayerRange> ranges) {
  var low = 0;
  var high = ranges.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    final maximum = ranges[middle].maximumLayerIndex;
    if (maximum != null && layerIndex >= maximum) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  if (low >= ranges.length) return null;
  final range = ranges[low];
  if (!layerIndexInRange(
    layerIndex,
    minimumLayerIndex: range.minimumLayerIndex,
    maximumLayerIndex: range.maximumLayerIndex,
  )) {
    return null;
  }

  return low;
}

/// Partitions native entries without separating stencil consumers from setup.
///
/// Tile clipping state is shared across native style layers. Setup controls
/// are replayed only in partitions that contain stencil consumers.
/// Clipping masks feed clipping tests. Clears also feed fill extrusions because
/// native rendering can recycle a 3D stencil reference after clearing it.
@visibleForTesting
void partitionDrawEntriesByStyleLayerRanges({
  required List<DrawEntry> entries,
  required List<GpuStyleLayerRange> ranges,
  required List<List<DrawEntry>> partitions,
  required List<bool> clippingMaskPartitions,
  required List<bool> stencilClearPartitions,
}) {
  if (partitions.length < ranges.length) {
    throw ArgumentError.value(
      partitions.length,
      'partitions',
      'must contain storage for every style layer range',
    );
  }
  if (clippingMaskPartitions.length < ranges.length) {
    throw ArgumentError.value(
      clippingMaskPartitions.length,
      'clippingMaskPartitions',
      'must contain storage for every style layer range',
    );
  }
  if (stencilClearPartitions.length < ranges.length) {
    throw ArgumentError.value(
      stencilClearPartitions.length,
      'stencilClearPartitions',
      'must contain storage for every style layer range',
    );
  }
  for (final partition in partitions) {
    partition.clear();
  }
  for (var index = 0; index < clippingMaskPartitions.length; index += 1) {
    clippingMaskPartitions[index] = false;
  }
  for (var index = 0; index < stencilClearPartitions.length; index += 1) {
    stencilClearPartitions[index] = false;
  }
  for (final entry in entries) {
    if (entry.stencilMode != StencilModeType.clippingTest &&
        entry.stencilMode != StencilModeType.fillExtrusion) {
      continue;
    }
    final partitionIndex = gpuStyleLayerRangeIndex(entry.layer, ranges);
    if (partitionIndex != null) {
      stencilClearPartitions[partitionIndex] = true;
      if (entry.stencilMode == StencilModeType.clippingTest) {
        clippingMaskPartitions[partitionIndex] = true;
      }
    }
  }
  for (final entry in entries) {
    if (entry.stencilMode == StencilModeType.clippingMask) {
      for (var index = 0; index < ranges.length; index += 1) {
        if (clippingMaskPartitions[index]) {
          partitions[index].add(entry);
        }
      }
      continue;
    }
    if (entry.stencilMode == StencilModeType.clear) {
      for (var index = 0; index < ranges.length; index += 1) {
        if (stencilClearPartitions[index]) {
          partitions[index].add(entry);
        }
      }
      continue;
    }
    final partitionIndex = gpuStyleLayerRangeIndex(entry.layer, ranges);
    if (partitionIndex != null) {
      partitions[partitionIndex].add(entry);
    }
  }
}

/// Whether [ranges] satisfy the ordering required by binary range lookup.
@visibleForTesting
bool gpuStyleLayerRangesAreOrdered(List<GpuStyleLayerRange> ranges) {
  if (ranges.isEmpty) return false;
  int? previousMaximum;
  for (var index = 0; index < ranges.length; index += 1) {
    final range = ranges[index];
    final minimum = range.minimumLayerIndex;
    final maximum = range.maximumLayerIndex;
    if (index > 0 && minimum == null) return false;
    if (index + 1 < ranges.length && maximum == null) return false;
    if (minimum != null && maximum != null && minimum >= maximum) return false;
    if (index > 0 &&
        previousMaximum != null &&
        minimum != null &&
        minimum < previousMaximum) {
      return false;
    }
    previousMaximum = maximum;
  }

  return true;
}

/// Whether any native command belongs to one compositing stratum.
@visibleForTesting
bool commandLayersIntersectRange(
  Iterable<int> commandLayerIndices, {
  int? minimumLayerIndex,
  int? maximumLayerIndex,
}) {
  for (final layerIndex in commandLayerIndices) {
    if (layerIndexInRange(
      layerIndex,
      minimumLayerIndex: minimumLayerIndex,
      maximumLayerIndex: maximumLayerIndex,
    )) {
      return true;
    }
  }

  return false;
}

/// Whether one style range owns the geographic 3D callback boundary.
///
/// The boundary follows the last fill-extrusion layer. Styles without a
/// fill-extrusion place it after the final bounded range.
@visibleForTesting
bool threeDimensionalCallbackInLayerRange(
  int? lastFillExtrusionLayerIndex, {
  int? minimumLayerIndex,
  int? maximumLayerIndex,
}) {
  if (lastFillExtrusionLayerIndex == null) return maximumLayerIndex == null;

  return layerIndexInRange(
    lastFillExtrusionLayerIndex,
    minimumLayerIndex: minimumLayerIndex,
    maximumLayerIndex: maximumLayerIndex,
  );
}

/// Decodes native draw commands and records them as Flutter GPU render passes.
class GpuFrameRenderer {
  final MaplibreBridge bridge;
  final MapPipelineRegistry _pipelines;
  final GpuResourceCache _resourceCache = GpuResourceCache();
  final FramePassExecutor _passes = FramePassExecutor();
  gpu.HostBuffer? _uniformHost;
  gpu.Texture? _mainDepthStencilTexture;
  int _mainDepthStencilWidth = 0;
  int _mainDepthStencilHeight = 0;
  bool _sharedDepthStencilInitialized = false;
  Uint8List _uniformBytes = Uint8List(0);
  ByteData _uniformData = ByteData(0);
  ByteData _uniformUploadData = ByteData(0);
  int _uniformUploadLength = 0;
  int _commandViewAddress = 0;
  int _commandViewLength = 0;
  Uint8List _commandBytes = Uint8List(0);
  ByteData _commandData = ByteData(0);
  int _commandLayerSummaryFrameSeq = -1;
  int _commandLayerSummaryAddress = 0;
  int _commandLayerSummaryCount = 0;
  int _commandLayerSummaryStride = 0;
  Set<int> _commandLayerIndices = const <int>{};
  final List<DrawEntry> _drawEntries = [];
  final List<DrawEntry> _drawEntryPool = [];
  int _drawEntryPoolCursor = 0;
  final List<_PreparedDrawPartition> _preparedPartitions = [];
  final List<List<DrawEntry>> _preparedPartitionEntries = [];
  final List<bool> _preparedPartitionNeedsClippingMasks = [];
  final List<bool> _preparedPartitionNeedsStencilClear = [];
  final PreparedGraphDetailedTimingMetrics _preparedGraphTiming =
      PreparedGraphDetailedTimingMetrics();
  _PreparedGraphState? _preparedGraph;
  GpuPreparedFrame? _preparedFrame;
  bool _resourceFrameNeedsFinalization = false;
  bool _resourceCacheNeedsEviction = false;
  final List<RenderPassPlan> _renderPassPlans = [];
  final List<RenderPassPlan> _renderPassPlanPool = [];
  double zoom = 0;
  int frameSeq = 0;
  final _logSw = Stopwatch()..start();

  /// Creates a renderer backed by [bridge].
  GpuFrameRenderer({required this.bridge, required gpu.ShaderLibrary shaders})
    : _pipelines = MapPipelineRegistry(shaders) {
    _pipelines.prewarmFillExtrusionPipelines();
  }

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
      _commandLayerIndices = const <int>{};

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

  /// Whether [metadata] contains a command inside one style layer range.
  bool frameHasCommandsInLayerRange(
    FrameCommandMetadata metadata, {
    int? minimumLayerIndex,
    int? maximumLayerIndex,
  }) => commandLayersIntersectRange(
    commandLayerIndices(metadata),
    minimumLayerIndex: minimumLayerIndex,
    maximumLayerIndex: maximumLayerIndex,
  );

  DrawEntry _acquireDrawEntry(
    int commandOffset,
    int shader,
    int drawMode,
    int flags,
    int layer,
    int vertexCount,
    int indexCount,
    GpuBufferEntry? vertexBuffer,
    GpuBufferEntry? indexBuffer,
    gpu.Texture? texture,
    int textureFilter,
    int stencilReference,
    int stencilMode,
    int subLayerIndex,
  ) {
    if (_drawEntryPoolCursor == _drawEntryPool.length) {
      _drawEntryPool.add(
        DrawEntry(
          commandOffset,
          shader,
          drawMode,
          flags,
          layer,
          vertexCount,
          indexCount,
          vertexBuffer,
          indexBuffer,
          texture,
          textureFilter,
          stencilReference,
          stencilMode,
          subLayerIndex: subLayerIndex,
        ),
      );
    } else {
      _drawEntryPool[_drawEntryPoolCursor].reset(
        commandOffset,
        shader,
        drawMode,
        flags,
        layer,
        vertexCount,
        indexCount,
        vertexBuffer,
        indexBuffer,
        texture,
        textureFilter,
        stencilReference,
        stencilMode,
        nextSubLayerIndex: subLayerIndex,
      );
    }
    return _drawEntryPool[_drawEntryPoolCursor++];
  }

  void _releaseUnusedDrawEntries() {
    for (
      var index = _drawEntryPoolCursor;
      index < _drawEntryPool.length;
      index += 1
    ) {
      _drawEntryPool[index].releaseResources();
    }
  }

  GpuBufferEntry _cachedVertexBuffer(
    int bufferId,
    int bufferVersion,
    int dataAddress,
    int vertexCount,
    int sourceStride,
    int shader,
    int flags,
  ) {
    final cacheKey = (
      bufferId: bufferId,
      bufferVersion: bufferVersion,
      dataAddress: dataAddress,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      shader: shader,
      gpuStride: gpuVertexStride(shader, flags),
    );
    var cached = _resourceCache.vertexBuffer(cacheKey);
    if (cached != null) return cached;
    final source = _nativeBytes(dataAddress, vertexCount * sourceStride);
    final repackStopwatch = Stopwatch()..start();
    final vertices = repackVertexDataForGpu(
      source,
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      shader: shader,
      flags: flags,
    );
    _resourceCache.timingMetrics.recordRepack(
      micros: repackStopwatch.elapsedMicroseconds,
    );
    final uploadStopwatch = Stopwatch()..start();
    cached = _uploadBuffer(
      vertices,
      isFillExtrusion: shader == ShaderType.fillExtrusion,
    );
    _resourceCache.timingMetrics.recordVertexUpload(
      micros: uploadStopwatch.elapsedMicroseconds,
      bytes: vertices.lengthInBytes,
    );
    _resourceCache.storeVertexBuffer(cacheKey, cached);

    return cached;
  }

  GpuBufferEntry _cachedIndexBuffer(
    int bufferId,
    int bufferVersion,
    int dataAddress,
    int vertexCount,
    int shader,
  ) {
    final cacheKey = (
      bufferId: bufferId,
      bufferVersion: bufferVersion,
      dataAddress: dataAddress,
    );
    var cached = _resourceCache.indexBuffer(cacheKey);
    if (cached != null) return cached;
    final bytes = _nativeBytes(dataAddress, vertexCount * 2);
    final uploadStopwatch = Stopwatch()..start();
    cached = _uploadBuffer(
      bytes,
      isFillExtrusion: shader == ShaderType.fillExtrusion,
    );
    _resourceCache.timingMetrics.recordIndexUpload(
      micros: uploadStopwatch.elapsedMicroseconds,
      bytes: bytes.lengthInBytes,
    );
    _resourceCache.storeIndexBuffer(cacheKey, cached);

    return cached;
  }

  GpuBufferEntry _frameIndexBuffer(int dataAddress, int byteLength) {
    final bytes = _nativeBytes(dataAddress, byteLength);
    final uploadStopwatch = Stopwatch()..start();
    final uploaded = _uploadBuffer(bytes);
    _resourceCache.timingMetrics.recordIndexUpload(
      micros: uploadStopwatch.elapsedMicroseconds,
      bytes: bytes.lengthInBytes,
      frameOwned: true,
    );

    return uploaded;
  }

  GpuBufferEntry _frameVertexBuffer(
    int dataAddress,
    int vertexCount,
    int sourceStride,
    int shader,
    int flags,
  ) {
    final source = _nativeBytes(dataAddress, vertexCount * sourceStride);
    Uint8List vertices;
    if (sourceStride == gpuVertexStride(shader, flags)) {
      vertices = source;
    } else {
      final repackStopwatch = Stopwatch()..start();
      vertices = repackVertexDataForGpu(
        source,
        vertexCount: vertexCount,
        sourceStride: sourceStride,
        shader: shader,
        flags: flags,
      );
      _resourceCache.timingMetrics.recordRepack(
        micros: repackStopwatch.elapsedMicroseconds,
      );
    }
    final uploadStopwatch = Stopwatch()..start();
    final uploaded = _uploadBuffer(vertices);
    _resourceCache.timingMetrics.recordVertexUpload(
      micros: uploadStopwatch.elapsedMicroseconds,
      bytes: vertices.lengthInBytes,
      frameOwned: true,
    );

    return uploaded;
  }

  /// Gets or creates a GPU texture for exported native pixel data.
  ///
  /// One-channel data uploads as R8. Four-channel data uploads as RGBA8.
  gpu.Texture? _textureForCommand(
    int textureId,
    int textureVersion,
    int dataAddress,
    int width,
    int height,
    int channels,
  ) {
    if (dataAddress == 0 ||
        width <= 0 ||
        height <= 0 ||
        (channels != 1 && channels != 4)) {
      return null;
    }
    final cacheKey = (textureId: textureId, textureVersion: textureVersion);
    final cached = _resourceCache.texture(cacheKey);
    if (cached != null) return cached.texture;
    try {
      final uploadStopwatch = Stopwatch()..start();
      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        width,
        height,
        format: channels == 1
            ? gpu.PixelFormat.r8UNormInt
            : gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
      );
      final byteLength = width * height * channels;
      final bytes = Pointer<Uint8>.fromAddress(dataAddress).asTypedList(
        byteLength,
      );
      texture.overwrite(ByteData.sublistView(bytes));
      _resourceCache.timingMetrics.recordTextureUpload(
        micros: uploadStopwatch.elapsedMicroseconds,
        bytes: byteLength,
      );
      _resourceCache.storeTexture(
        cacheKey,
        GpuTextureEntry(texture, byteLength),
      );

      return texture;
    } catch (e) {
      debugPrint(
        '[GpuRenderer] texture upload failed '
        '($width x $height ch=$channels): $e',
      );

      return null;
    }
  }

  /// Whether the backend has rejected depth and stencil attachments.
  ///
  /// Once rejected, later frames use the fallback without attempting another
  /// attachment.
  static bool _depthStencilUnsupported = false;

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
    _FrameDecode? decoded;
    if (graphState != null) {
      final validationStart = stopwatch.elapsedMicroseconds;
      final view = _commandView(frameMetadata, shouldLog: shouldLog);
      final graph = graphState.graph;
      final topologyMatches =
          view != null &&
          graph.key.matches(
            commandBytes: view.commandBytes,
            commandCount: view.commandCount,
            commandStride: view.commandStride,
          );
      validationMicros = stopwatch.elapsedMicroseconds - validationStart;
      if (topologyMatches) {
        final activeView = view!;
        final refreshStart = stopwatch.elapsedMicroseconds;
        final refreshed = _refreshPreparedEntries(
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
          rebuildReason = PreparedGraphRebuildReason.refreshFailed;
        }
      } else {
        rebuildReason = PreparedGraphRebuildReason.topologyMismatch;
      }
    }
    if (!reusedGraph) {
      final decodeStart = stopwatch.elapsedMicroseconds;
      _resetPreparedGraphStorage();
      decoded = _decodeCommands(frameMetadata, shouldLog: shouldLog);
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
      uniformData = _packUniforms(
        layout,
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
      final uniformBuffer = _uploadUniforms(uniformLength);
      binder = FrameBinder(
        pipelines: _pipelines,
        uniformBuffer: uniformBuffer,
        mapGlobalOffset: layout.mapGlobalOffset,
        // Oversize emplacements allocate one-shot DeviceBuffers outside the
        // HostBuffer ring. Never retain those through pooled draw entries.
        cacheUniformViews: uniformLength <= _uniformHost!.blockLengthInBytes,
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
        layerRanges: <GpuStyleLayerRange>[
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
      _logFrameSummary(
        entries: prepared._graphState.graph.entries,
        commandCount: prepared.commandCount,
        drawCount: prepared.drawCount,
        renderPassCount: prepared.renderPassCount,
        uboMicros: prepared.uboMicros,
        graphTiming: _preparedGraphTiming.takeSnapshotAndReset(),
      );
      _logResourceSummary();
    }
    if (evictResourceCaches) _resourceCache.evictCaches();
  }

  /// Starts another replay of the current preparation without re-uploading it.
  void beginFrameReplay() {
    final prepared = _preparedFrame;
    if (prepared == null || _resourceFrameNeedsFinalization) return;
    _resourceFrameNeedsFinalization = true;
    _sharedDepthStencilInitialized = false;
    prepared.drawCount = 0;
    prepared.renderPassCount = 0;
  }

  /// Starts per-frame resources without discarding stable graph state.
  void _beginPreparedFrame({required bool advanceResourceFrame}) {
    if (advanceResourceFrame) _resourceCache.beginFrame();
    _resourceFrameNeedsFinalization = true;
    _resourceCacheNeedsEviction = true;
    _preparedFrame = null;
    _sharedDepthStencilInitialized = false;
    final uniformHost = _uniformHost;
    if (uniformHost == null) {
      _uniformHost = gpu.gpuContext.createHostBuffer();
    } else {
      uniformHost.reset();
    }
  }

  /// Clears topology-owned storage before decoding a different graph.
  void _resetPreparedGraphStorage() {
    _preparedGraph = null;
    for (final partition in _preparedPartitions) {
      partition.entries.clear();
      partition.needsMainDepthStencil = false;
    }
    _drawEntries.clear();
    _drawEntryPoolCursor = 0;
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
    preparedGraph.layerRanges = List<GpuStyleLayerRange>.unmodifiable(
      layerRanges,
    );
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

  _CommandView? _commandView(
    FrameCommandMetadata metadata, {
    required bool shouldLog,
  }) {
    final commandCount = metadata.commandCount;
    if (commandCount <= 0) {
      _clearCommandViews();

      return null;
    }
    final commandsPointer = metadata.commands;
    if (commandsPointer == nullptr) {
      _clearCommandViews();

      return null;
    }
    final stride = metadata.commandStride;
    if (stride != DrawCommandAbi.size) {
      if (shouldLog) {
        debugPrint(
          '[GpuRenderer] ABI mismatch: stride=$stride expected=${DrawCommandAbi.size}',
        );
      }
      _clearCommandViews();

      return null;
    }
    final commandViewAddress = commandsPointer.address;
    final commandViewLength = commandCount * stride;
    if (_commandViewAddress != commandViewAddress ||
        _commandViewLength != commandViewLength) {
      _commandViewAddress = commandViewAddress;
      _commandViewLength = commandViewLength;
      _commandBytes = commandsPointer.cast<Uint8>().asTypedList(
        commandViewLength,
      );
      _commandData = ByteData.sublistView(_commandBytes);
    }

    return (
      commandBytes: _commandBytes,
      commandData: _commandData,
      commandCount: commandCount,
      commandStride: stride,
    );
  }

  bool _refreshPreparedEntries(
    List<DrawEntry> entries,
    ByteData commandData, {
    required bool shouldLog,
  }) {
    for (final entry in entries) {
      final offset = entry.commandOffset;
      entry.stencilReference = commandData.getUint32(
        offset + DrawCommandAbi.stencilReference,
        Endian.little,
      );
      if (entry.stencilMode == StencilModeType.clear) continue;

      final vertexCount = commandData.getUint32(
        offset + DrawCommandAbi.vertexCount,
        Endian.little,
      );
      final indexCount = commandData.getUint32(
        offset + DrawCommandAbi.indexCount,
        Endian.little,
      );
      final vertexStride = commandData.getUint32(
        offset + DrawCommandAbi.vertexStride,
        Endian.little,
      );
      final isMerged = drawCommandIsCrossTileMerged(entry.flags);
      final expectedStride = nativeVertexStride(
        shader: entry.shader,
        flags: entry.flags,
        merged: isMerged,
      );
      if (vertexStride != expectedStride) {
        if (shouldLog) {
          debugPrint(
            '[GpuRenderer] prepared graph vertex stride mismatch: '
            'shader=${entry.shader} flags=${entry.flags} '
            'exported=$vertexStride expected=$expectedStride',
          );
        }

        return false;
      }
      final vertexDataAddress = commandData.getUint64(
        offset + DrawCommandAbi.vertexData,
        Endian.little,
      );
      final indexDataAddress = commandData.getUint64(
        offset + DrawCommandAbi.indexData,
        Endian.little,
      );
      entry
        ..vertexCount = vertexCount
        ..indexCount = indexCount
        ..vertexBuffer = isMerged
            ? _frameVertexBuffer(
                vertexDataAddress,
                vertexCount,
                vertexStride,
                entry.shader,
                entry.flags,
              )
            : _cachedVertexBuffer(
                commandData.getUint32(
                  offset + DrawCommandAbi.bufferId,
                  Endian.little,
                ),
                commandData.getUint32(
                  offset + DrawCommandAbi.bufferVersion,
                  Endian.little,
                ),
                vertexDataAddress,
                vertexCount,
                vertexStride,
                entry.shader,
                entry.flags,
              )
        ..indexBuffer = isMerged
            ? _frameIndexBuffer(indexDataAddress, indexCount * 2)
            : _cachedIndexBuffer(
                commandData.getUint32(
                  offset + DrawCommandAbi.bufferId,
                  Endian.little,
                ),
                commandData.getUint32(
                  offset + DrawCommandAbi.bufferVersion,
                  Endian.little,
                ),
                indexDataAddress,
                indexCount,
                entry.shader,
              );

      gpu.Texture? commandTexture;
      final textureChannels = commandData.getUint32(
        offset + DrawCommandAbi.texChannels,
        Endian.little,
      );
      if (textureChannels > 0) {
        commandTexture = _textureForCommand(
          commandData.getUint32(offset + DrawCommandAbi.texId, Endian.little),
          commandData.getUint32(
            offset + DrawCommandAbi.texVersion,
            Endian.little,
          ),
          commandData.getUint64(offset + DrawCommandAbi.texData, Endian.little),
          commandData.getUint32(
            offset + DrawCommandAbi.texWidth,
            Endian.little,
          ),
          commandData.getUint32(
            offset + DrawCommandAbi.texHeight,
            Endian.little,
          ),
          textureChannels,
        );
        if (commandTexture == null &&
            shaderRequiresUploadedTexture(entry.shader)) {
          if (shouldLog) {
            debugPrint(
              '[GpuRenderer] prepared graph texture refresh failed: '
              'shader=${entry.shader}',
            );
          }

          return false;
        }
      } else if (shaderRequiresTextureData(entry.shader)) {
        return false;
      }
      entry
        ..texture = commandTexture
        ..textureFilter = commandData.getUint32(
          offset + DrawCommandAbi.texFilter,
          Endian.little,
        );
    }

    return true;
  }

  /// Reads the native command buffer into pooled [DrawEntry] values.
  ///
  /// Returns null when the native command block is unavailable or invalid.
  ///
  /// Also assigns each entry its uniform ranges, since their offsets run
  /// consecutively in decode order.
  _FrameDecode? _decodeCommands(
    FrameCommandMetadata frameMetadata, {
    required bool shouldLog,
  }) {
    final entries = _drawEntries;
    final view = _commandView(frameMetadata, shouldLog: shouldLog);
    if (view == null) {
      _releaseUnusedDrawEntries();

      return null;
    }
    final commandBytes = view.commandBytes;
    final commandData = view.commandData;
    final commandCount = view.commandCount;
    final stride = view.commandStride;
    final backendAlignment = gpu.gpuContext.minimumUniformByteAlignment;
    final uniformAlignment =
        backendAlignment < RendererUboAbi.minimumUniformByteAlignment
        ? RendererUboAbi.minimumUniformByteAlignment
        : backendAlignment;

    int uniformCursor = 0;
    int lineCommandCount = 0;
    var hasTriangulatedOutline = false;
    int? lastFillExtrusionLayerIndex;
    for (var index = 0; index < commandCount; index += 1) {
      final commandOffset = index * stride;
      final layerIndex = commandData.getUint32(
        commandOffset + DrawCommandAbi.layerIndex,
        Endian.little,
      );
      if (commandData.getUint32(
            commandOffset + DrawCommandAbi.shaderType,
            Endian.little,
          ) ==
          ShaderType.fillExtrusion) {
        lastFillExtrusionLayerIndex = layerIndex;
      }
      final entry = _decodeCommand(
        commandData,
        commandOffset,
        shouldLog: shouldLog,
      );
      if (entry == null) continue;
      entries.add(entry);
      if (entry.stencilMode == StencilModeType.clear) continue;
      if (isLineShader(entry.shader)) lineCommandCount++;
      if (entry.shader == ShaderType.fillOutlineTriangulated) {
        hasTriangulatedOutline = true;
      }
      uniformCursor = _assignUniformRanges(
        entry,
        uniformCursor,
        uniformAlignment,
      );
    }
    _releaseUnusedDrawEntries();

    return (
      commandBytes: commandBytes,
      commandData: commandData,
      commandCount: commandCount,
      uniformAlignment: uniformAlignment,
      uniformCursor: uniformCursor,
      hasMapGlobalUniform: frameNeedsMapGlobalUniform(
        lineCommandCount: lineCommandCount,
        hasTriangulatedOutline: hasTriangulatedOutline,
      ),
      lastFillExtrusionLayerIndex: lastFillExtrusionLayerIndex,
    );
  }

  void _clearCommandViews() {
    if (_commandViewLength == 0) return;
    _commandViewAddress = 0;
    _commandViewLength = 0;
    _commandBytes = Uint8List(0);
    _commandData = ByteData(0);
  }

  /// Decodes one DrawCommand record, resolving its buffers and texture.
  ///
  /// Returns null when the command cannot or need not be rendered.
  ///
  /// The returned entry has no uniform ranges yet. Those are assigned by the
  /// caller, which knows where the frame's uniform cursor stands.
  DrawEntry? _decodeCommand(
    ByteData commandData,
    int offset, {
    required bool shouldLog,
  }) {
    final shader = commandData.getUint32(
      offset + DrawCommandAbi.shaderType,
      Endian.little,
    );
    final stencilMode = commandData.getUint32(
      offset + DrawCommandAbi.stencilMode,
      Endian.little,
    );
    final vertexCount = commandData.getUint32(
      offset + DrawCommandAbi.vertexCount,
      Endian.little,
    );
    final indexCount = commandData.getUint32(
      offset + DrawCommandAbi.indexCount,
      Endian.little,
    );
    final vertexDataAddress = commandData.getUint64(
      offset + DrawCommandAbi.vertexData,
      Endian.little,
    );
    final indexDataAddress = commandData.getUint64(
      offset + DrawCommandAbi.indexData,
      Endian.little,
    );

    final admission = admitDrawCommand(
      shader: shader,
      stencilMode: stencilMode,
      vertexCount: vertexCount,
      indexCount: indexCount,
      vertexDataAddress: vertexDataAddress,
      indexDataAddress: indexDataAddress,
      drawableMatrixM00: commandData.getFloat32(
        offset + DrawCommandAbi.drawableUBO,
        Endian.little,
      ),
      drawableMatrixM11: commandData.getFloat32(
        offset +
            DrawCommandAbi.drawableUBO +
            RendererUboAbi.drawableMatrixM11Offset,
        Endian.little,
      ),
    );
    if (admission == DrawCommandAdmission.drop) return null;

    final flags = commandData.getUint32(
      offset + DrawCommandAbi.flags,
      Endian.little,
    );
    final isMerged = drawCommandIsCrossTileMerged(flags);
    final drawMode = commandData.getUint32(
      offset + DrawCommandAbi.drawMode,
      Endian.little,
    );
    final layer = commandData.getUint32(
      offset + DrawCommandAbi.layerIndex,
      Endian.little,
    );
    final stencilReference = commandData.getUint32(
      offset + DrawCommandAbi.stencilReference,
      Endian.little,
    );
    final subLayerIndex = commandData.getInt32(
      offset + DrawCommandAbi.subLayerIndex,
      Endian.little,
    );

    // Control commands bind no geometry but must retain their command order.
    if (admission == DrawCommandAdmission.controlCommand) {
      return _acquireDrawEntry(
        offset,
        shader,
        drawMode,
        flags,
        layer,
        0,
        0,
        null,
        null,
        null,
        TextureFilterType.linear,
        stencilReference,
        stencilMode,
        subLayerIndex,
      );
    }

    final vertexStride = nativeVertexStride(
      shader: shader,
      flags: flags,
      merged: isMerged,
    );
    final exportedVertexStride = commandData.getUint32(
      offset + DrawCommandAbi.vertexStride,
      Endian.little,
    );
    if (exportedVertexStride != vertexStride) {
      if (shouldLog) {
        debugPrint(
          '[GpuRenderer] vertex stride mismatch: shader=$shader flags=$flags '
          'exported=$exportedVertexStride expected=$vertexStride',
        );
      }
      return null;
    }
    final bufferId = commandData.getUint32(
      offset + DrawCommandAbi.bufferId,
      Endian.little,
    );
    final bufferVersion = commandData.getUint32(
      offset + DrawCommandAbi.bufferVersion,
      Endian.little,
    );
    // Cross-tile merged buffers are frame-owned. Other buffers are cached by
    // the native drawable generation.
    final vertexBuffer = isMerged
        ? _frameVertexBuffer(
            vertexDataAddress,
            vertexCount,
            vertexStride,
            shader,
            flags,
          )
        : _cachedVertexBuffer(
            bufferId,
            bufferVersion,
            vertexDataAddress,
            vertexCount,
            vertexStride,
            shader,
            flags,
          );
    final indexBuffer = isMerged
        ? _frameIndexBuffer(indexDataAddress, indexCount * 2)
        : _cachedIndexBuffer(
            bufferId,
            bufferVersion,
            indexDataAddress,
            indexCount,
            shader,
          );
    // Resolve the command texture.
    gpu.Texture? commandTexture;
    final textureChannels = commandData.getUint32(
      offset + DrawCommandAbi.texChannels,
      Endian.little,
    );
    if (textureChannels > 0) {
      commandTexture = _textureForCommand(
        commandData.getUint32(offset + DrawCommandAbi.texId, Endian.little),
        commandData.getUint32(
          offset + DrawCommandAbi.texVersion,
          Endian.little,
        ),
        commandData.getUint64(offset + DrawCommandAbi.texData, Endian.little),
        commandData.getUint32(offset + DrawCommandAbi.texWidth, Endian.little),
        commandData.getUint32(offset + DrawCommandAbi.texHeight, Endian.little),
        textureChannels,
      );
      // Texture-backed variants cannot render without their image.
      if (commandTexture == null && shaderRequiresUploadedTexture(shader)) {
        return null;
      }
    } else if (shaderRequiresTextureData(shader)) {
      return null;
    }
    return _acquireDrawEntry(
      offset,
      shader,
      drawMode,
      flags,
      layer,
      vertexCount,
      indexCount,
      vertexBuffer,
      indexBuffer,
      commandTexture,
      commandData.getUint32(offset + DrawCommandAbi.texFilter, Endian.little),
      stencilReference,
      stencilMode,
      subLayerIndex,
    );
  }

  /// Writes every UBO the frame binds into the staging buffer.
  ///
  /// Returns a view of the packed data.
  ByteData _packUniforms(
    FrameUniformLayout layout, {
    required Uint8List commandBytes,
    required ByteData commandData,
    required double devicePixelRatio,
    required int physicalWidth,
    required int physicalHeight,
    required double logicalWidth,
    required double logicalHeight,
    required bool hasMapGlobal,
  }) {
    final entries = _drawEntries;
    final mapGlobalOffset = layout.mapGlobalOffset;
    final uniformLength = layout.totalBytes;
    final dpr = devicePixelRatio;
    if (_uniformBytes.length < uniformLength) {
      _uniformBytes = Uint8List((uniformLength * 1.5).toInt());
      _uniformData = ByteData.sublistView(_uniformBytes);
      _uniformUploadLength = 0;
    }
    final uniformData = _uniformData;
    if (hasMapGlobal) {
      final global = mapGlobalUniformValues(
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        physicalWidth: physicalWidth,
        physicalHeight: physicalHeight,
      );
      uniformData.setFloat32(
        mapGlobalOffset + RendererUboAbi.mapGlobalUnitsXOffset,
        global.unitsX,
        Endian.little,
      );
      uniformData.setFloat32(
        mapGlobalOffset + RendererUboAbi.mapGlobalUnitsYOffset,
        global.unitsY,
        Endian.little,
      );
      uniformData.setFloat32(
        mapGlobalOffset + RendererUboAbi.mapGlobalWorldWidthOffset,
        global.worldWidth,
        Endian.little,
      );
      uniformData.setFloat32(
        mapGlobalOffset + RendererUboAbi.mapGlobalWorldHeightOffset,
        global.worldHeight,
        Endian.little,
      );
    }
    for (final entry in entries) {
      if (entry.stencilMode == StencilModeType.clear) continue;
      final commandTexture = entry.texture;
      packCommandUniforms(
        source: commandBytes,
        sourceData: commandData,
        commandOffset: entry.commandOffset,
        destination: _uniformBytes,
        destinationData: uniformData,
        shader: entry.shader,
        flags: entry.flags,
        drawableOffset: entry.drawableUniformOffset,
        drawableLength: entry.drawableUniformLength,
        propsOffset: entry.propsUniformOffset,
        propsLength: entry.propsUniformLength,
        tilePropsOffset: entry.tilePropsUniformOffset,
        tilePropsLength: entry.tilePropsUniformLength,
        devicePixelRatio: dpr,
        textureWidth: commandTexture?.width ?? 0,
        textureHeight: commandTexture?.height ?? 0,
      );
    }
    return uniformData;
  }

  /// Uploads the packed uniforms and returns their device buffer.
  gpu.DeviceBuffer _uploadUniforms(int uniformLength) {
    if (_uniformUploadLength != uniformLength) {
      _uniformUploadData = ByteData.sublistView(
        _uniformBytes,
        0,
        uniformLength,
      );
      _uniformUploadLength = uniformLength;
    }
    final uniformBytes = _uniformUploadData;
    final uniformHost = _uniformHost!;
    if (uniformLength <= uniformHost.blockLengthInBytes) {
      final uniformView = uniformHost.emplace(uniformBytes);
      assert(uniformView.offsetInBytes == 0);

      return uniformView.buffer;
    }
    // Oversize allocations are not retained by the HostBuffer ring. Use a
    // one-shot buffer instead.
    return gpu.gpuContext.createDeviceBufferWithCopy(uniformBytes);
  }

  /// Replays the frame onto [texture] as one render pass per pipeline run.
  ///
  /// Adjacent pipeline runs keep MapLibre's emission order, but compatible runs
  /// share one Flutter GPU render pass. Stencil clears, custom callbacks, and
  /// depth-write changes remain pass barriers.
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

    // MapLibre retains one combined depth/stencil attachment across the
    // whole frame. Separate Flutter GPU render passes must load/store both
    // aspects so a depth-only pass cannot invalidate tile masks.
    final mainDepthStencilTexture =
        needsMainDepthStencil || customMapCallback != null
        ? initialDepthStencilTexture ?? prepareDepthStencilTexture(texture)
        : null;

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
      if (plan.kind == RenderPassPlanKind.stencilClear) {
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
        final isDepthPrepass =
            plan.kind == RenderPassPlanKind.fillExtrusionDepth;
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
    if (submitEachRenderPass && hasRecordedPass) {
      currentCommandBuffer.submit();
    }
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
        MapLibreGpuRenderContext(
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
          depthMode: MapLibreGpuDepthMode.shared,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[GpuRenderer] gpuMapRenderCallback error: $error\n$stackTrace',
      );
    }
  }

  /// Prints one line of per-frame counts, at most once a second.
  ///
  /// Counts admitted entries rather than every native command. Persistent graph
  /// timings aggregate every newly prepared native frame since the last log.
  void _logFrameSummary({
    required List<DrawEntry> entries,
    required int commandCount,
    required int drawCount,
    required int renderPassCount,
    required int uboMicros,
    required PreparedGraphDetailedTimingSnapshot graphTiming,
  }) {
    int nFill = 0,
        nFE = 0,
        nBg = 0,
        nLine = 0,
        nSdf = 0,
        nGrad = 0,
        nPat = 0,
        nCircle = 0,
        nRaster = 0,
        nMerged = 0,
        totalVerts = 0;
    for (final entry in entries) {
      if (entry.shader == ShaderType.fill) {
        nFill++;
      } else if (entry.shader == ShaderType.fillExtrusion) {
        nFE++;
      } else if (entry.shader == ShaderType.background ||
          entry.shader == ShaderType.backgroundPattern) {
        nBg++;
      } else if (entry.shader == ShaderType.line) {
        nLine++;
      } else if (entry.shader == ShaderType.lineSDF) {
        nSdf++;
      } else if (entry.shader == ShaderType.lineGradient) {
        nGrad++;
      } else if (entry.shader == ShaderType.linePattern) {
        nPat++;
      } else if (entry.shader == ShaderType.circle) {
        nCircle++;
      } else if (entry.shader == ShaderType.raster) {
        nRaster++;
      }
      if (drawCommandIsCrossTileMerged(entry.flags)) nMerged++;
      totalVerts += entry.vertexCount;
    }
    String averageMicros(double? value) =>
        value == null ? '-' : '${value.toStringAsFixed(0)}us';
    String maxMicros(int count, int value) => count == 0 ? '-' : '${value}us';
    final totals = graphTiming.totals;
    final graphHitRate = (totals.hitRate * 100).toStringAsFixed(1);
    debugPrint(
      '[GpuRenderer] z=${zoom.toStringAsFixed(2)} n=$commandCount '
      'draws=$drawCount passes=$renderPassCount '
      'bg=$nBg fill=$nFill line=$nLine sdf=$nSdf grad=$nGrad pat=$nPat '
      'circle=$nCircle raster=$nRaster fe=$nFE merged=$nMerged '
      'verts=${totalVerts ~/ 1000}K '
      'graph=${totals.hitCount}/${totals.sampleCount}($graphHitRate%) '
      'graphHit=${averageMicros(totals.averageHitMicros)} '
      'graphRebuild=${averageMicros(totals.averageRebuildMicros)} '
      'ubo=${uboMicros}us',
    );
    debugPrint(
      '[GpuGraph] hitMax=${maxMicros(totals.hitCount, graphTiming.hitMaxMicros)} '
      'rebuildMax=${maxMicros(totals.rebuildCount, graphTiming.rebuildMaxMicros)} '
      'validate=${averageMicros(graphTiming.averageValidationMicros)} '
      'refresh=${averageMicros(graphTiming.averageRefreshMicros)} '
      'decode=${averageMicros(graphTiming.averageDecodeMicros)} '
      'capture=${averageMicros(graphTiming.averageCaptureMicros)} '
      'rebuildCause=noGraph:${graphTiming.noGraphRebuildCount} '
      'topology:${graphTiming.topologyMismatchRebuildCount} '
      'refresh:${graphTiming.refreshFailedRebuildCount}',
    );
  }

  void _logResourceSummary() {
    final timing = _resourceCache.timingMetrics.takeSnapshotAndReset();
    final cache = _resourceCache.sizeSnapshot;
    String lookup(int hits, int misses) =>
        '$hits/${hits + misses}(miss=$misses)';
    String average(double? micros) =>
        micros == null ? '-' : '${micros.toStringAsFixed(0)}us';
    String maximum(int count, int micros) => count == 0 ? '-' : '${micros}us';
    String megabytes(int bytes) =>
        '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

    debugPrint(
      '[GpuResource] vertex=${lookup(timing.vertexCacheHits, timing.vertexCacheMisses)} '
      'index=${lookup(timing.indexCacheHits, timing.indexCacheMisses)} '
      'texture=${lookup(timing.textureCacheHits, timing.textureCacheMisses)} '
      'cache=v:${cache.vertexCount}/${megabytes(cache.vertexBytes)} '
      'i:${cache.indexCount}/${megabytes(cache.indexBytes)} '
      't:${cache.textureCount}/${megabytes(cache.textureBytes)} '
      'total=${megabytes(cache.totalBytes)} '
      'evict=expiry:${timing.expiryEvictionCount}/${megabytes(timing.expiryEvictionBytes)} '
      'budget:${timing.budgetEvictionCount}/${megabytes(timing.budgetEvictionBytes)}',
    );
    debugPrint(
      '[GpuUpload] repack=${timing.repackCount}/${average(timing.averageRepackMicros)} '
      'max=${maximum(timing.repackCount, timing.repackMaxMicros)} '
      'vertex=${timing.vertexUploadCount}/${megabytes(timing.vertexUploadBytes)}/'
      '${average(timing.averageVertexUploadMicros)}/'
      '${maximum(timing.vertexUploadCount, timing.vertexUploadMaxMicros)} '
      'index=${timing.indexUploadCount}/${megabytes(timing.indexUploadBytes)}/'
      '${average(timing.averageIndexUploadMicros)}/'
      '${maximum(timing.indexUploadCount, timing.indexUploadMaxMicros)} '
      'texture=${timing.textureUploadCount}/${megabytes(timing.textureUploadBytes)}/'
      '${average(timing.averageTextureUploadMicros)}/'
      '${maximum(timing.textureUploadCount, timing.textureUploadMaxMicros)} '
      'frameOwned=v:${timing.frameVertexUploadCount}/'
      '${megabytes(timing.frameVertexUploadBytes)} '
      'i:${timing.frameIndexUploadCount}/${megabytes(timing.frameIndexUploadBytes)}',
    );
  }

  /// Releases resources owned by this renderer.
  void dispose() {
    _resourceCache.dispose();
    _uniformHost = null;
    _preparedGraph = null;
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
    _uniformBytes = Uint8List(0);
    _uniformData = ByteData(0);
    _uniformUploadData = ByteData(0);
    _uniformUploadLength = 0;
    _clearCommandViews();
    _drawEntries.clear();
    for (final entry in _drawEntryPool) {
      entry.releaseResources();
    }
    _drawEntryPool.clear();
    _drawEntryPoolCursor = 0;
    _renderPassPlans.clear();
    _renderPassPlanPool.clear();
    _passes.releaseResources();
  }
}

import 'dart:ffi' hide Size;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vector_math;

import 'draw_entry.dart';
import 'frame_binder.dart';
import 'pass_executor.dart';
import 'pipeline_registry.dart';
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
void sortClippingRunsBySubLayer(List<DrawEntry> entries, ByteData commandData) {
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
      final subLayer = commandData.getInt32(
        entry.commandOffset + DrawCommandAbi.subLayerIndex,
        Endian.little,
      );
      var insertion = index;
      while (insertion > start) {
        final previous = entries[insertion - 1];
        final previousSubLayer = commandData.getInt32(
          previous.commandOffset + DrawCommandAbi.subLayerIndex,
          Endian.little,
        );
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
  double devicePixelRatio,
  int uniformAlignment,
  int uniformCursor,
  bool hasMapGlobalUniform,
  bool needsMainDepthStencil,
});

typedef _FrameDrawResult = ({int drawCount, int renderPassCount});

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
  final List<gpu.HostBuffer> _transientUniforms = [];
  gpu.HostBuffer? _activeTransientUniforms;
  int _transientUniformIndex = 0;
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
    final vertices = repackVertexDataForGpu(
      _nativeBytes(dataAddress, vertexCount * sourceStride),
      vertexCount: vertexCount,
      sourceStride: sourceStride,
      shader: shader,
      flags: flags,
    );
    cached = _uploadBuffer(
      vertices,
      isFillExtrusion: shader == ShaderType.fillExtrusion,
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
    cached = _uploadBuffer(
      _nativeBytes(dataAddress, vertexCount * 2),
      isFillExtrusion: shader == ShaderType.fillExtrusion,
    );
    _resourceCache.storeIndexBuffer(cacheKey, cached);

    return cached;
  }

  GpuBufferEntry _frameIndexBuffer(int dataAddress, int byteLength) =>
      _uploadBuffer(_nativeBytes(dataAddress, byteLength));

  GpuBufferEntry _frameVertexBuffer(
    int dataAddress,
    int vertexCount,
    int sourceStride,
    int shader,
    int flags,
  ) {
    final source = _nativeBytes(dataAddress, vertexCount * sourceStride);

    // Skip repacking when the exported and GPU vertex layouts already match.
    return _uploadBuffer(
      sourceStride == gpuVertexStride(shader, flags)
          ? source
          : repackVertexDataForGpu(
              source,
              vertexCount: vertexCount,
              sourceStride: sourceStride,
              shader: shader,
              flags: flags,
            ),
    );
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
      final bytes = Pointer<Uint8>.fromAddress(dataAddress)
          .asTypedList(width * height * channels);
      texture.overwrite(ByteData.sublistView(bytes));
      _resourceCache.storeTexture(
        cacheKey,
        GpuTextureEntry(texture, width * height * channels),
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

  /// Renders one frame onto [texture].
  ///
  /// Appends this frame's passes to [commandBuffer].
  ///
  /// The caller owns submission unless [submitEachRenderPass] is true. Keeping
  /// submission with the caller lets map drawing and overlays share one command
  /// buffer.
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
      return _renderFrameImpl(
        commandBuffer: commandBuffer,
        texture: texture,
        frameClearColor: frameClearColor,
        submitEachRenderPass: submitEachRenderPass,
        frameMetadata: frameMetadata,
        initialDepthStencilTexture: initialDepthStencilTexture,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        devicePixelRatio: devicePixelRatio,
        gpuMapRenderCallback: gpuMapRenderCallback,
        mapTransform: mapTransform,
        minimumLayerIndex: minimumLayerIndex,
        maximumLayerIndex: maximumLayerIndex,
        advanceResourceFrame: advanceResourceFrame,
      );
    } on DepthStencilAttachmentError {
      rethrow;
    } catch (e, st) {
      debugPrint('[GpuRenderer] error: $e\n$st');

      return 0;
    } finally {
      if (evictResourceCaches) _resourceCache.evictCaches();
    }
  }

  int _renderFrameImpl({
    required gpu.CommandBuffer commandBuffer,
    required gpu.Texture texture,
    required vector_math.Vector4 frameClearColor,
    required bool submitEachRenderPass,
    FrameCommandMetadata? frameMetadata,
    gpu.Texture? initialDepthStencilTexture,
    double? logicalWidth,
    double? logicalHeight,
    required double devicePixelRatio,
    MapLibreGpuRenderCallback? gpuMapRenderCallback,
    MapLibreGpuMapTransform? mapTransform,
    int? minimumLayerIndex,
    int? maximumLayerIndex,
    required bool advanceResourceFrame,
  }) {
    _beginFrame(advanceResourceFrame: advanceResourceFrame);
    final shouldLog = _logSw.elapsedMilliseconds >= 1000;
    if (shouldLog) _logSw.reset();
    final stopwatch = Stopwatch()..start();
    final metadata = frameMetadata ?? bridge.frameGetMetadata();
    final effectiveMapCallback =
        gpuMapRenderCallback != null &&
            threeDimensionalCallbackInLayerRange(
              _lastFillExtrusionLayerIndex(metadata),
              minimumLayerIndex: minimumLayerIndex,
              maximumLayerIndex: maximumLayerIndex,
            )
        ? gpuMapRenderCallback
        : null;
    final decoded = _decodeCommands(
      metadata,
      shouldLog: shouldLog,
      minimumLayerIndex: minimumLayerIndex,
      maximumLayerIndex: maximumLayerIndex,
    );
    if (decoded == null) {
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
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        devicePixelRatio: devicePixelRatio,
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
    final commandBytes = decoded.commandBytes;
    final commandData = decoded.commandData;
    final commandCount = decoded.commandCount;
    final dpr = decoded.devicePixelRatio;
    final hasMapGlobal = decoded.hasMapGlobalUniform;
    final needsMainDepthStencil = decoded.needsMainDepthStencil;
    final decodeMicros = stopwatch.elapsedMicroseconds;

    final layout = layoutFrameUniforms(
      drawableCursor: decoded.uniformCursor,
      alignment: decoded.uniformAlignment,
      hasMapGlobal: hasMapGlobal,
    );
    final mapGlobalOffset = layout.mapGlobalOffset;
    final uniformLength = layout.totalBytes;
    final uniformData = _packUniforms(
      layout,
      commandBytes: commandBytes,
      commandData: commandData,
      devicePixelRatio: dpr,
      texture: texture,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      hasMapGlobal: hasMapGlobal,
    );
    final uniformMicros = stopwatch.elapsedMicroseconds;
    final uniformBuffer = _uploadUniforms(uniformLength);

    final binder = FrameBinder(
      pipelines: _pipelines,
      uniformBuffer: uniformBuffer,
      mapGlobalOffset: mapGlobalOffset,
      // Oversize emplacements allocate one-shot DeviceBuffers outside the
      // HostBuffer ring. Never retain those through pooled draw entries.
      cacheUniformViews:
          uniformLength <= _activeTransientUniforms!.blockLengthInBytes,
    );

    final drawResult = _recordTexturePasses(
      commandBuffer,
      texture,
      binder,
      submitEachRenderPass: submitEachRenderPass,
      frameClearColor: frameClearColor,
      uniformData: uniformData,
      initialDepthStencilTexture: initialDepthStencilTexture,
      needsMainDepthStencil: needsMainDepthStencil,
      customMapCallback: effectiveMapCallback,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      devicePixelRatio: devicePixelRatio,
      mapTransform: mapTransform,
    );
    if (shouldLog) {
      _logFrameSummary(
        commandCount: commandCount,
        drawCount: drawResult.drawCount,
        renderPassCount: drawResult.renderPassCount,
        uboMicros: uniformMicros - decodeMicros,
      );
    }
    return drawResult.drawCount;
  }

  /// Initializes frame-scoped scratch state.
  void _beginFrame({required bool advanceResourceFrame}) {
    if (advanceResourceFrame) {
      _resourceCache.beginFrame();
      _sharedDepthStencilInitialized = false;
      _transientUniformIndex = 0;
    }
    _drawEntries.clear();
    _drawEntryPoolCursor = 0;
    if (_transientUniformIndex == _transientUniforms.length) {
      _transientUniforms.add(gpu.gpuContext.createHostBuffer());
    } else {
      _transientUniforms[_transientUniformIndex].reset();
    }
    _activeTransientUniforms = _transientUniforms[_transientUniformIndex++];
  }

  int? _lastFillExtrusionLayerIndex(FrameCommandMetadata metadata) {
    final commandCount = metadata.commandCount;
    final stride = metadata.commandStride;
    final commands = metadata.commands;
    if (commandCount <= 0 ||
        stride != DrawCommandAbi.size ||
        commands == nullptr) {
      return null;
    }
    final data = ByteData.sublistView(
      commands.cast<Uint8>().asTypedList(commandCount * stride),
    );
    int? layerIndex;
    for (var index = 0; index < commandCount; index += 1) {
      final offset = index * stride;
      final shader = data.getUint32(
        offset + DrawCommandAbi.shaderType,
        Endian.little,
      );
      if (shader == ShaderType.fillExtrusion) {
        layerIndex = data.getUint32(
          offset + DrawCommandAbi.layerIndex,
          Endian.little,
        );
      }
    }

    return layerIndex;
  }

  /// Reads the native command buffer into pooled [DrawEntry] values.
  ///
  /// Returns null when no drawable or control entries can be decoded.
  ///
  /// Also assigns each entry its uniform ranges, since their offsets run
  /// consecutively in decode order.
  _FrameDecode? _decodeCommands(
    FrameCommandMetadata frameMetadata, {
    required bool shouldLog,
    int? minimumLayerIndex,
    int? maximumLayerIndex,
  }) {
    final entries = _drawEntries;
    final metadata = frameMetadata;
    final commandCount = metadata.commandCount;
    if (commandCount <= 0) {
      _clearCommandViews();
      _releaseUnusedDrawEntries();

      return null;
    }
    final commandsPointer = metadata.commands;
    if (commandsPointer == nullptr) {
      _clearCommandViews();
      _releaseUnusedDrawEntries();

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
      _releaseUnusedDrawEntries();

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
    final commandBytes = _commandBytes;
    final commandData = _commandData;
    final dpr = bridge.devicePixelRatio;
    final backendAlignment = gpu.gpuContext.minimumUniformByteAlignment;
    final uniformAlignment =
        backendAlignment < RendererUboAbi.minimumUniformByteAlignment
        ? RendererUboAbi.minimumUniformByteAlignment
        : backendAlignment;

    int uniformCursor = 0;
    int lineCommandCount = 0;
    var hasTriangulatedOutline = false;
    var needsMainDepthStencil = false;
    for (var index = 0; index < commandCount; index += 1) {
      final commandOffset = index * stride;
      final layerIndex = commandData.getUint32(
        commandOffset + DrawCommandAbi.layerIndex,
        Endian.little,
      );
      if (!layerIndexInRange(
        layerIndex,
        minimumLayerIndex: minimumLayerIndex,
        maximumLayerIndex: maximumLayerIndex,
      )) {
        continue;
      }
      final entry = _decodeCommand(
        commandData,
        commandOffset,
        shouldLog: shouldLog,
      );
      if (entry == null) continue;
      entries.add(entry);
      if (entry.stencilMode == StencilModeType.clear) {
        // A mid-frame clear carries no geometry and binds no uniforms, but it
        // still needs the attachment it clears.
        needsMainDepthStencil = true;
        continue;
      }
      if (isLineShader(entry.shader)) lineCommandCount++;
      if (entry.shader == ShaderType.fillOutlineTriangulated) {
        hasTriangulatedOutline = true;
      }
      if (commandNeedsDepthStencil(
        shader: entry.shader,
        flags: entry.flags,
        stencilMode: entry.stencilMode,
      )) {
        needsMainDepthStencil = true;
      }
      uniformCursor = _assignUniformRanges(
        entry,
        uniformCursor,
        uniformAlignment,
      );
    }
    sortClippingRunsBySubLayer(entries, commandData);
    _releaseUnusedDrawEntries();
    if (entries.isEmpty) return null;

    return (
      commandBytes: commandBytes,
      commandData: commandData,
      commandCount: commandCount,
      devicePixelRatio: dpr,
      uniformAlignment: uniformAlignment,
      uniformCursor: uniformCursor,
      hasMapGlobalUniform: frameNeedsMapGlobalUniform(
        lineCommandCount: lineCommandCount,
        hasTriangulatedOutline: hasTriangulatedOutline,
      ),
      needsMainDepthStencil: needsMainDepthStencil,
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
    required gpu.Texture texture,
    required double? logicalWidth,
    required double? logicalHeight,
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
      final physicalWidth = texture.width;
      final physicalHeight = texture.height;
      final safeDpr = dpr.isFinite && dpr > 0 ? dpr : 1.0;
      final global = mapGlobalUniformValues(
        logicalWidth: logicalWidth ?? physicalWidth / safeDpr,
        logicalHeight: logicalHeight ?? physicalHeight / safeDpr,
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
    final uniformHost = _activeTransientUniforms!;
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
    final entries = _drawEntries;
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

    for (final entry in entries) {
      entry.pipelineKey = entry.stencilMode == StencilModeType.clear
          ? null
          : pipelineKeyFor(shader: entry.shader, flags: entry.flags);
      entry.depthPipelineKey = depthPipelineKeyFor(
        shader: entry.shader,
        flags: entry.flags,
      );
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
  /// Counts admitted entries rather than every native command.
  void _logFrameSummary({
    required int commandCount,
    required int drawCount,
    required int renderPassCount,
    required int uboMicros,
  }) {
    final entries = _drawEntries;
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
    debugPrint(
      '[GpuRenderer] z=${zoom.toStringAsFixed(2)} n=$commandCount '
      'draws=$drawCount passes=$renderPassCount '
      'bg=$nBg fill=$nFill line=$nLine sdf=$nSdf grad=$nGrad pat=$nPat '
      'circle=$nCircle raster=$nRaster fe=$nFE merged=$nMerged '
      'verts=${totalVerts ~/ 1000}K ubo=${uboMicros}us',
    );
  }

  /// Releases resources owned by this renderer.
  void dispose() {
    _resourceCache.dispose();
    _transientUniforms.clear();
    _activeTransientUniforms = null;
    _transientUniformIndex = 0;
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

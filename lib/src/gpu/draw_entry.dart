import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame/pipeline_key.dart';
import '../frame/render_pass_plan.dart';
import '../frame/ubo_abi.dart';
import 'resource_cache.dart';

/// One draw command decoded into the state required by a render pass.
class DrawEntry implements RenderPassPlanningEntryView {
  // Flutter GPU's HostBuffer rotates through four DeviceBuffers. Retaining one
  // view bundle per ring slot removes steady-state wrapper allocation without
  // keeping an unbounded history of transient uniform buffers.
  static const int _uniformBufferRingSize = 4;

  /// Byte offset of this command inside the exported command block.
  int commandOffset;
  @override
  int shader;
  int drawMode;

  /// DrawCommandFlags bitset.
  @override
  int flags;
  @override
  int layer;
  GpuBufferEntry? vertexBuffer;
  GpuBufferEntry? indexBuffer;
  int vertexCount;
  int indexCount;

  /// Dash atlas, gradient ramp, pattern atlas, or raster tile.
  gpu.Texture? texture;
  int textureFilter;
  int stencilReference;
  @override
  int stencilMode;

  /// Native sublayer order retained after the command snapshot is released.
  int subLayerIndex;

  /// The color-pass pipeline selected for this entry.
  RenderPipelineKey? pipelineKey;

  /// The depth-prepass pipeline, for fill extrusion only.
  RenderPipelineKey? depthPipelineKey;

  @override
  Object? get pipelineIdentity => pipelineKey;

  @override
  Object? get depthPipelineIdentity => depthPipelineKey;

  @override
  double fillExtrusionOpacity = 1.0;
  int drawableUniformOffset = 0;
  int drawableUniformLength = 0;
  int propsUniformOffset = 0;
  int propsUniformLength = 0;
  int tilePropsUniformOffset = 0;
  int tilePropsUniformLength = 0;
  final List<UniformBindingViews> _uniformViewCache = <UniformBindingViews>[];
  int _uniformViewCursor = 0;

  DrawEntry(
    this.commandOffset,
    this.shader,
    this.drawMode,
    this.flags,
    this.layer,
    this.vertexCount,
    this.indexCount,
    this.vertexBuffer,
    this.indexBuffer,
    this.texture,
    this.textureFilter,
    this.stencilReference,
    this.stencilMode, {
    this.subLayerIndex = 0,
  });

  /// Resets this entry for another command while retaining reusable uniform
  /// views.
  void reset(
    int nextCommandOffset,
    int nextShader,
    int nextDrawMode,
    int nextFlags,
    int nextLayer,
    int nextVCount,
    int nextICount,
    GpuBufferEntry? nextVertexBuffer,
    GpuBufferEntry? nextIndexBuffer,
    gpu.Texture? nextTexture,
    int nextTexFilter,
    int nextStencilReference,
    int nextStencilMode, {
    int nextSubLayerIndex = 0,
  }) {
    commandOffset = nextCommandOffset;
    shader = nextShader;
    drawMode = nextDrawMode;
    flags = nextFlags;
    layer = nextLayer;
    vertexCount = nextVCount;
    indexCount = nextICount;
    vertexBuffer = nextVertexBuffer;
    indexBuffer = nextIndexBuffer;
    texture = nextTexture;
    textureFilter = nextTexFilter;
    stencilReference = nextStencilReference;
    stencilMode = nextStencilMode;
    subLayerIndex = nextSubLayerIndex;
    pipelineKey = null;
    depthPipelineKey = null;
    fillExtrusionOpacity = 1.0;
    drawableUniformOffset = 0;
    drawableUniformLength = 0;
    propsUniformOffset = 0;
    propsUniformLength = 0;
    tilePropsUniformOffset = 0;
    tilePropsUniformLength = 0;
  }

  /// Drops references to GPU resources and cached uniform views.
  void releaseResources() {
    vertexBuffer = null;
    indexBuffer = null;
    texture = null;
    pipelineKey = null;
    depthPipelineKey = null;
    _uniformViewCache.clear();
    _uniformViewCursor = 0;
  }

  /// Returns uniform buffer views for this entry.
  ///
  /// Matching views are reused when [cache] is true.
  UniformBindingViews uniformViews(
    gpu.DeviceBuffer buffer,
    int mapGlobalOffset, {
    required bool cache,
  }) {
    if (cache) {
      for (final views in _uniformViewCache) {
        if (views.matches(this, buffer, mapGlobalOffset)) return views;
      }
    }
    final views = UniformBindingViews(this, buffer, mapGlobalOffset);
    if (!cache) return views;
    if (_uniformViewCache.length < _uniformBufferRingSize) {
      _uniformViewCache.add(views);
    } else {
      _uniformViewCache[_uniformViewCursor] = views;
      _uniformViewCursor = (_uniformViewCursor + 1) % _uniformBufferRingSize;
    }
    return views;
  }
}

/// Lazily created uniform buffer views for one draw entry and device buffer.
class UniformBindingViews {
  UniformBindingViews(DrawEntry entry, this.buffer, this.mapGlobalOffset)
    : drawableOffset = entry.drawableUniformOffset,
      drawableLength = entry.drawableUniformLength,
      propsOffset = entry.propsUniformOffset,
      propsLength = entry.propsUniformLength,
      tilePropsOffset = entry.tilePropsUniformOffset,
      tilePropsLength = entry.tilePropsUniformLength;

  final gpu.DeviceBuffer buffer;
  final int mapGlobalOffset;
  final int drawableOffset;
  final int drawableLength;
  final int propsOffset;
  final int propsLength;
  final int tilePropsOffset;
  final int tilePropsLength;

  late final gpu.BufferView drawable = gpu.BufferView(
    buffer,
    offsetInBytes: drawableOffset,
    lengthInBytes: drawableLength,
  );
  late final gpu.BufferView props = gpu.BufferView(
    buffer,
    offsetInBytes: propsOffset,
    lengthInBytes: propsLength,
  );
  late final gpu.BufferView global = gpu.BufferView(
    buffer,
    offsetInBytes: mapGlobalOffset,
    lengthInBytes: RendererUboAbi.mapGlobalBytes,
  );
  late final gpu.BufferView tileProps = gpu.BufferView(
    buffer,
    offsetInBytes: tilePropsOffset,
    lengthInBytes: tilePropsLength,
  );

  bool matches(
    DrawEntry entry,
    gpu.DeviceBuffer nextBuffer,
    int nextMapGlobalOffset,
  ) =>
      identical(buffer, nextBuffer) &&
      mapGlobalOffset == nextMapGlobalOffset &&
      drawableOffset == entry.drawableUniformOffset &&
      drawableLength == entry.drawableUniformLength &&
      propsOffset == entry.propsUniformOffset &&
      propsLength == entry.propsUniformLength &&
      tilePropsOffset == entry.tilePropsUniformOffset &&
      tilePropsLength == entry.tilePropsUniformLength;
}

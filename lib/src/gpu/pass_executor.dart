import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vector_math;

import '../frame/gpu_state.dart';
import '../native/draw_command.dart';
import 'draw_entry.dart';
import 'frame_binder.dart';
import 'pipeline_registry.dart';

/// Wraps a render-pass creation failure involving a depth/stencil attachment.
final class DepthStencilAttachmentError implements Exception {
  const DepthStencilAttachmentError(this.cause, this.stackTrace);

  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'Depth/stencil attachment failed: $cause';
}

/// Records planned draw runs into Flutter GPU render passes.
///
/// Methods append work to caller-provided command buffers without submitting.
class FramePassExecutor {
  gpu.ColorAttachment? _colorOnlyAttachment;
  gpu.RenderTarget? _colorOnlyTarget;
  gpu.ColorAttachment? _depthColorAttachment;
  gpu.DepthStencilAttachment? _depthAttachment;
  gpu.RenderTarget? _depthTarget;

  /// Returns a render target configured with the requested attachments and
  /// load actions.
  ///
  /// Attachment descriptors are reused between calls. Flutter GPU copies their
  /// fields when the render pass is created.
  gpu.RenderTarget renderTarget(
    gpu.Texture colorTexture,
    vector_math.Vector4 frameClearColor, {
    required bool clearColor,
    gpu.Texture? depthStencilTexture,
    required bool clearDepth,
    required bool clearStencil,
    double depthClearValue = 1.0,
    int stencilClearValue = 0,
  }) {
    final colorLoadAction = clearColor
        ? gpu.LoadAction.clear
        : gpu.LoadAction.load;
    if (depthStencilTexture == null) {
      var color = _colorOnlyAttachment;
      if (color == null) {
        color = gpu.ColorAttachment(
          texture: colorTexture,
          loadAction: colorLoadAction,
          clearValue: frameClearColor,
        );
        _colorOnlyAttachment = color;
        _colorOnlyTarget = gpu.RenderTarget(colorAttachments: [color]);
      } else {
        color
          ..texture = colorTexture
          ..loadAction = colorLoadAction
          ..clearValue = frameClearColor;
      }
      return _colorOnlyTarget!;
    }

    var color = _depthColorAttachment;
    var depth = _depthAttachment;
    if (color == null || depth == null) {
      color = gpu.ColorAttachment(
        texture: colorTexture,
        loadAction: colorLoadAction,
        clearValue: frameClearColor,
      );
      depth = gpu.DepthStencilAttachment(
        texture: depthStencilTexture,
        depthLoadAction: clearDepth
            ? gpu.LoadAction.clear
            : gpu.LoadAction.load,
        depthStoreAction: gpu.StoreAction.store,
        depthClearValue: depthClearValue,
        stencilLoadAction: clearStencil
            ? gpu.LoadAction.clear
            : gpu.LoadAction.load,
        stencilStoreAction: gpu.StoreAction.store,
        stencilClearValue: stencilClearValue,
      );
      _depthColorAttachment = color;
      _depthAttachment = depth;
      _depthTarget = gpu.RenderTarget(
        colorAttachments: [color],
        depthStencilAttachment: depth,
      );
    } else {
      color
        ..texture = colorTexture
        ..loadAction = colorLoadAction
        ..clearValue = frameClearColor;
      depth
        ..texture = depthStencilTexture
        ..depthLoadAction = clearDepth
            ? gpu.LoadAction.clear
            : gpu.LoadAction.load
        ..depthStoreAction = gpu.StoreAction.store
        ..depthClearValue = depthClearValue
        ..stencilLoadAction = clearStencil
            ? gpu.LoadAction.clear
            : gpu.LoadAction.load
        ..stencilStoreAction = gpu.StoreAction.store
        ..stencilClearValue = stencilClearValue;
    }
    return _depthTarget!;
  }

  /// Creates a render pass and identifies depth/stencil attachment failures.
  gpu.RenderPass createRenderPass(
    gpu.CommandBuffer commandBuffer,
    gpu.RenderTarget renderTarget, {
    required bool hasDepthStencilAttachment,
  }) {
    try {
      return commandBuffer.createRenderPass(renderTarget);
    } catch (error, stackTrace) {
      if (hasDepthStencilAttachment) {
        throw DepthStencilAttachmentError(error, stackTrace);
      }
      rethrow;
    }
  }

  /// Applies MapLibre's premultiplied-alpha blend state to [pass].
  void setPremultipliedAlphaBlend(gpu.RenderPass pass) {
    pass.setColorBlendEnable(true);
    pass.setColorBlendEquation(premultipliedAlphaBlendEquation());
  }

  /// Begins a pass for map content using the requested attachment state.
  gpu.RenderPass beginOverlayPass(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture texture,
    vector_math.Vector4 frameClearColor, {
    bool clearColor = false,
    gpu.Texture? depthStencilTexture,
    bool clearDepth = false,
    bool clearStencil = false,
    bool depthWrite = false,
  }) {
    final target = renderTarget(
      texture,
      frameClearColor,
      clearColor: clearColor,
      depthStencilTexture: depthStencilTexture,
      clearDepth: clearDepth,
      clearStencil: clearStencil,
    );
    final pass = createRenderPass(
      commandBuffer,
      target,
      hasDepthStencilAttachment: depthStencilTexture != null,
    );
    setPremultipliedAlphaBlend(pass);
    // Flutter 3.38-3.44 ignores the boolean argument and always enables
    // writes. A pass therefore contains runs with one depth-write value only.
    if (depthWrite && depthStencilTexture != null) {
      pass.setDepthWriteEnable(true);
    }
    return pass;
  }

  /// Draws entries in the half-open range from [start] to [end].
  ///
  /// Returns the number of recorded draws.
  int drawRun(
    gpu.RenderPass pass,
    ResolvedPipeline pipeline,
    List<DrawEntry> entries,
    int start,
    int end,
    FrameBinder binder, {
    required bool hasDepthStencilAttachment,
    required bool propsAreRunConstant,
    bool setPrimitive = false,
    bool depthTest = false,
    int stencilMode = StencilModeType.disabled,
    bool cullBackFaces = false,
  }) {
    // Bindings and every mutable pipeline descriptor field are reset at the
    // run boundary. Flutter GPU snapshots them when draw() is appended.
    pass.clearBindings();
    pass.setDepthCompareOperation(
      depthTest && hasDepthStencilAttachment
          ? gpu.CompareFunction.lessEqual
          : gpu.CompareFunction.always,
    );
    pass.setStencilConfig(stencilConfigFor(stencilMode));
    pass.setCullMode(cullBackFaces ? gpu.CullMode.backFace : gpu.CullMode.none);
    if (cullBackFaces) {
      pass.setWindingOrder(gpu.WindingOrder.counterClockwise);
    }
    pass.setPrimitiveType(_primitiveTypeFor(entries[start].drawMode));
    pass.bindPipeline(pipeline.pipeline);
    binder.bindRunConstants(
      pass,
      pipeline,
      entries[start],
      bindProps: propsAreRunConstant,
    );
    var drawCount = 0;
    for (var index = start; index < end; index += 1) {
      final entry = entries[index];
      if (setPrimitive) {
        pass.setPrimitiveType(_primitiveTypeFor(entry.drawMode));
      }
      if (stencilMode != StencilModeType.disabled) {
        pass.setStencilReference(entry.stencilReference & 0xff);
      }
      pass.bindVertexBuffer(entry.vertexBuffer!.view, entry.vertexCount);
      pass.bindIndexBuffer(
        entry.indexBuffer!.view,
        gpu.IndexType.int16,
        entry.indexCount,
      );
      binder.bind(pass, pipeline, entry, bindProps: !propsAreRunConstant);
      pass.draw();
      drawCount += 1;
    }
    return drawCount;
  }

  /// Records a pass that clears the shared stencil attachment.
  void clearStencilPass(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture colorTexture,
    vector_math.Vector4 frameClearColor,
    gpu.Texture depthStencilTexture, {
    required bool clearColor,
    required bool attachmentInitialized,
    required int clearValue,
  }) {
    final target = renderTarget(
      colorTexture,
      frameClearColor,
      clearColor: clearColor,
      depthStencilTexture: depthStencilTexture,
      clearDepth: !attachmentInitialized,
      clearStencil: true,
      stencilClearValue: clearValue & 0xff,
    );
    createRenderPass(commandBuffer, target, hasDepthStencilAttachment: true);
  }

  /// Records a pass that clears the frame's render target.
  void clearFramePass(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture colorTexture,
    vector_math.Vector4 frameClearColor, {
    gpu.Texture? depthStencilTexture,
    required bool clearDepthStencil,
  }) {
    final attachedDepthStencil = clearDepthStencil ? depthStencilTexture : null;
    final target = renderTarget(
      colorTexture,
      frameClearColor,
      clearColor: true,
      depthStencilTexture: attachedDepthStencil,
      clearDepth: attachedDepthStencil != null,
      clearStencil: attachedDepthStencil != null,
    );
    createRenderPass(
      commandBuffer,
      target,
      hasDepthStencilAttachment: attachedDepthStencil != null,
    );
  }

  /// Drops cached attachment descriptors and render targets.
  void releaseResources() {
    _colorOnlyAttachment = null;
    _colorOnlyTarget = null;
    _depthColorAttachment = null;
    _depthAttachment = null;
    _depthTarget = null;
  }

  static gpu.PrimitiveType _primitiveTypeFor(int drawMode) =>
      switch (drawMode) {
        DrawModeType.lines => gpu.PrimitiveType.line,
        DrawModeType.lineStrip => gpu.PrimitiveType.lineStrip,
        DrawModeType.points => gpu.PrimitiveType.point,
        _ => gpu.PrimitiveType.triangle,
      };
}

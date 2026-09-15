import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;

/// Records logical passes into one native pass per command buffer.
///
/// Later clears use full-screen draws so color, depth, and stencil remain in
/// the same native pass. Logical passes must share the first pass's color and
/// depth/stencil textures. A later pass may omit depth/stencil operations.
class SingleRenderPassRecorder(final gpu.ShaderLibrary shaders) {
  gpu.RenderPipeline? _pipeline;
  gpu.UniformSlot? _colorSlot;
  gpu.DeviceBuffer? _vertices;
  double? _vertexDepth;
  gpu.HostBuffer? _uniforms;
  gpu.CommandBuffer? _commandBuffer;
  gpu.RenderPass? _pass;
  gpu.Texture? _colorTexture;
  gpu.Texture? _depthStencilTexture;
  final _color = Float32List(4);
  final _replaceStencil = gpu.StencilConfig(
    compareFunction: .always,
    depthStencilPassOperation: .setToReferenceValue,
    readMask: 0xff,
    writeMask: 0xff,
  );
  final _keepStencil = gpu.StencilConfig(writeMask: 0);
  final _preserveColor = gpu.ColorBlendEquation(
    sourceColorBlendFactor: .zero,
    destinationColorBlendFactor: .one,
    sourceAlphaBlendFactor: .zero,
    destinationAlphaBlendFactor: .one,
  );

  /// Advances the uniform allocation ring once before recording a frame.
  void beginFrame() {
    _uniforms?.reset();
    _commandBuffer = null;
    _pass = null;
    _colorTexture = null;
    _depthStencilTexture = null;
  }

  /// Creates a single-color pass and performs its requested clears.
  ///
  /// The returned pass has default draw state and no vertex, index, uniform,
  /// or texture bindings. Callers must bind a pipeline before drawing.
  gpu.RenderPass createRenderPass(
    gpu.CommandBuffer commandBuffer,
    gpu.RenderTarget target,
  ) {
    final color = target.colorAttachments.single;
    final depth = target.depthStencilAttachment;
    final colorLoad = color.loadAction;
    final depthLoad = depth?.depthLoadAction;
    final stencilLoad = depth?.stencilLoadAction;
    if (!identical(_commandBuffer, commandBuffer)) {
      final pass = commandBuffer.createRenderPass(target);
      _commandBuffer = commandBuffer;
      _colorTexture = color.texture;
      _depthStencilTexture = depth?.texture;
      _pass = pass;

      return pass;
    }
    if (!identical(_colorTexture, color.texture)) {
      throw StateError('A command buffer must use one map color texture.');
    }
    if (depth != null && !identical(_depthStencilTexture, depth.texture)) {
      throw StateError(
        'A command buffer must use one map depth/stencil texture.',
      );
    }
    final pass = _pass!;
    _resetDrawState(pass, color.texture);
    final clearColor = colorLoad == .clear;
    final clearDepth = depthLoad == .clear;
    final clearStencil = stencilLoad == .clear;
    if (!clearColor && !clearDepth && !clearStencil) return pass;
    final context = gpu.gpuContext;
    if (_pipeline == null) {
      final fragment = shaders['AttachmentClearFragment']!;
      _pipeline = context.createRenderPipeline(
        shaders['AttachmentClearVertex']!,
        fragment,
      );
      _colorSlot = fragment.getUniformSlot('ClearColor');
    }
    final clearDepthValue = depth?.depthClearValue ?? 1.0;
    if (_vertices == null || _vertexDepth != clearDepthValue) {
      final vertices = Float32List.fromList([
        -1,
        -1,
        clearDepthValue,
        3,
        -1,
        clearDepthValue,
        -1,
        3,
        clearDepthValue,
      ]);
      _vertices = context.createDeviceBufferWithCopy(
        ByteData.sublistView(vertices),
      );
      _vertexDepth = clearDepthValue;
    }
    _color.setAll(0, color.clearValue.storage);
    final uniforms = _uniforms ??= context.createHostBuffer();
    pass.bindPipeline(_pipeline!);
    pass.bindVertexBuffer(
      gpu.BufferView(_vertices!, offsetInBytes: 0, lengthInBytes: 36),
    );
    pass.bindUniform(
      _colorSlot!,
      uniforms.emplace(ByteData.sublistView(_color)),
    );
    pass.setColorBlendEnable(!clearColor);
    if (!clearColor) pass.setColorBlendEquation(_preserveColor);
    pass.setDepthCompareOperation(.always);
    pass.setDepthWriteEnable(clearDepth);
    pass.setStencilConfig(clearStencil ? _replaceStencil : _keepStencil);
    if (clearStencil) pass.setStencilReference(depth!.stencilClearValue);
    pass.draw(3);
    _resetDrawState(pass, color.texture);

    return pass;
  }

  void _resetDrawState(gpu.RenderPass pass, gpu.Texture color) {
    pass.clearBindings();
    pass.setColorBlendEnable(false);
    pass.setColorBlendEquation(gpu.ColorBlendEquation());
    pass.setDepthCompareOperation(.always);
    pass.setDepthWriteEnable(false);
    pass.setStencilConfig(gpu.StencilConfig());
    pass.setStencilReference(0);
    pass.setCullMode(.none);
    pass.setWindingOrder(.clockwise);
    pass.setPrimitiveType(.triangle);
    pass.setPolygonMode(.fill);
    pass.setViewport(gpu.Viewport(width: color.width, height: color.height));
    pass.setScissor(gpu.Scissor(width: color.width, height: color.height));
  }

  /// Releases retained GPU resources after the renderer stops using them.
  void dispose() {
    _pipeline = null;
    _colorSlot = null;
    _vertices = null;
    _vertexDepth = null;
    _uniforms = null;
    _commandBuffer = null;
    _pass = null;
    _colorTexture = null;
    _depthStencilTexture = null;
  }
}

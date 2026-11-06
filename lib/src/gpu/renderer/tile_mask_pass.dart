part of '../renderer.dart';

/// Renders each tile's clip reference into a texture that batched draws
/// sample instead of testing the stencil attachment.
///
/// The mask is rendered once per native frame from the frame's clipping mask
/// commands and shared by every stratum. Frames without batched commands
/// leave the texture untouched.
final class _TileMaskPass {
  gpu.Texture? _texture;
  var _width = 0;
  var _height = 0;
  var _renderedFrameSequence = -1;

  /// Returns the mask for [frameSequence], rendering it when a batched entry
  /// exists and the mask was not rendered for this frame yet.
  gpu.Texture? prepare({
    required int frameSequence,
    required List<DrawEntry> entries,
    required FrameBinder binder,
    required FramePassExecutor executor,
    required int width,
    required int height,
  }) {
    var hasBatched = false;
    for (final entry in entries) {
      if (entry.batchMemberCount > 0) {
        hasBatched = true;
        break;
      }
    }
    if (!hasBatched) return null;
    final texture = _ensureTexture(width, height);
    if (texture == null) return null;
    if (_renderedFrameSequence == frameSequence) return texture;
    final commands = gpu.gpuContext.createCommandBuffer();
    final pass = commands.createRenderPass(
      gpu.RenderTarget(
        colorAttachments: [
          gpu.ColorAttachment(
            texture: texture,
            loadAction: .clear,
            storeAction: .store,
            clearValue: vector_math.Vector4(0, 0, 0, 1),
          ),
        ],
      ),
    );
    pass.setColorBlendEnable(false);
    pass.setDepthWriteEnable(false);
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      if (entry.shader != ShaderType.clippingMask ||
          entry.stencilMode != StencilModeType.clippingMask ||
          entry.vertexBuffer == null ||
          entry.indexBuffer == null) {
        continue;
      }
      executor.drawRun(
        pass,
        binder.pipelineForKey(RenderPipelineKey.tileMaskId),
        entries,
        index,
        index + 1,
        binder,
        hasDepthStencilAttachment: false,
        propsAreRunConstant: false,
      );
    }
    commands.submit();
    _renderedFrameSequence = frameSequence;

    return texture;
  }

  // RGBA8 is the one format every backend renders to; Impeller's OpenGL ES
  // backend cannot encode a pass onto a single-channel target. The reference
  // lives in red.
  gpu.Texture? _ensureTexture(int width, int height) {
    final cached = _texture;
    if (cached != null && _width == width && _height == height) return cached;
    _texture = null;
    _renderedFrameSequence = -1;
    try {
      final texture = gpu.gpuContext.createTexture(
        .devicePrivate,
        width,
        height,
        format: .r8g8b8a8UNormInt,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      );
      _texture = texture;
      _width = width;
      _height = height;

      return texture;
    } catch (error) {
      debugPrint('[GpuRenderer] tile mask texture unavailable: $error');

      return null;
    }
  }

  void dispose() {
    _texture = null;
    _width = 0;
    _height = 0;
    _renderedFrameSequence = -1;
  }
}

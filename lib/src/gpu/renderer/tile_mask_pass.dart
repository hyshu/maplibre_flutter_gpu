part of '../renderer.dart';

/// Renders each tile's clip reference into a texture that batched draws
/// sample instead of testing the stencil attachment.
///
/// The masks are rendered once per native frame from the frame's clipping
/// mask commands and shared by every stratum. A frame holds one texture per
/// clipping-mask group, because MapLibre renders masks again mid-frame when a
/// layer group's tiles differ from the masks already in the stencil, and a
/// batched draw must clip against the masks that were current when it was
/// emitted. Frames without batched commands leave the textures untouched.
final class _TileMaskPass {
  final _textures = <gpu.Texture>[];
  var _width = 0;
  var _height = 0;
  var _renderedFrameSequence = -1;

  /// Renders the masks of [frameSequence] when a batched entry exists and
  /// they were not rendered for this frame yet, and records each entry's
  /// [DrawEntry.tileMaskGroup]. Returns whether batched entries exist.
  bool prepare({
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
    if (!hasBatched) return false;
    if (_renderedFrameSequence == frameSequence &&
        _width == width &&
        _height == height) {
      return true;
    }
    final groups = tileMaskGroupsFor([
      for (final entry in entries) _isClippingMask(entry),
    ]);
    var groupCount = 1;
    for (var index = 0; index < entries.length; index += 1) {
      entries[index].tileMaskGroup = groups[index];
      if (groups[index] + 1 > groupCount) groupCount = groups[index] + 1;
    }
    if (!_ensureTextures(groupCount, width, height)) return false;
    // Each group gets its own command buffer, like the single mask before
    // groups existed, so no backend sees two passes in one buffer here.
    for (var group = 0; group < groupCount; group += 1) {
      final commands = gpu.gpuContext.createCommandBuffer();
      final pass = commands.createRenderPass(
        gpu.RenderTarget(
          colorAttachments: [
            gpu.ColorAttachment(
              texture: _textures[group],
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
        if (entry.tileMaskGroup != group ||
            !_isClippingMask(entry) ||
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
    }
    _renderedFrameSequence = frameSequence;

    return true;
  }

  /// Returns the mask texture of [group], or null when the frame has none.
  gpu.Texture? textureForGroup(int group) =>
      group >= 0 && group < _textures.length ? _textures[group] : null;

  static bool _isClippingMask(DrawEntry entry) =>
      entry.shader == ShaderType.clippingMask &&
      entry.stencilMode == StencilModeType.clippingMask;

  // RGBA8 is the one format every backend renders to. Impeller's OpenGL ES
  // backend cannot encode a pass onto a single-channel target. The reference
  // lives in red.
  bool _ensureTextures(int count, int width, int height) {
    if (_width != width || _height != height) {
      _textures.clear();
      _renderedFrameSequence = -1;
      _width = width;
      _height = height;
    }
    while (_textures.length < count) {
      try {
        _textures.add(
          gpu.gpuContext.createTexture(
            .devicePrivate,
            width,
            height,
            format: .r8g8b8a8UNormInt,
            enableRenderTargetUsage: true,
            enableShaderReadUsage: true,
          ),
        );
      } catch (error) {
        debugPrint('[GpuRenderer] tile mask texture unavailable: $error');
        _textures.clear();

        return false;
      }
    }
    return true;
  }

  void dispose() {
    _textures.clear();
    _width = 0;
    _height = 0;
    _renderedFrameSequence = -1;
  }
}

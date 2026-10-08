part of '../renderer.dart';

/// Owns offscreen targets shared by all compositing strata in a frame.
final class _OffscreenPasses {
  final _textures = <int, gpu.Texture>{};
  final _kinds = <int, OffscreenPassKind>{};
  var _recorded = false;
  final _transparent = vector_math.Vector4.zero();
  final _additiveBlend = gpu.ColorBlendEquation(
    sourceColorBlendFactor: .one,
    destinationColorBlendFactor: .one,
    sourceAlphaBlendFactor: .one,
    destinationAlphaBlendFactor: .one,
  );

  /// Submits offscreen passes before any stratum samples their textures.
  ///
  /// Each target uses its own command buffer so backends restricted to one
  /// render target per command buffer keep the same attachment throughout.
  _FrameDrawResult render(GpuPreparedFrame frame, FramePassExecutor executor) {
    if (_recorded) return (drawCount: 0, renderPassCount: 0);
    final plans = frame._offscreenPlans;
    if (plans.isEmpty) {
      _textures.clear();
      _kinds.clear();
      _recorded = true;

      return (drawCount: 0, renderPassCount: 0);
    }
    final entries = frame._graphState.graph.entries;
    final activeIds = plans.map((plan) => plan.targetId).toSet();
    _textures.removeWhere((id, _) => !activeIds.contains(id));
    _kinds.removeWhere((id, _) => !activeIds.contains(id));
    var drawCount = 0;
    for (final plan in plans) {
      var texture = _textures[plan.targetId];
      if (texture == null ||
          texture.width != plan.width ||
          texture.height != plan.height ||
          _kinds[plan.targetId] != plan.kind) {
        texture = gpu.gpuContext.createTexture(
          .devicePrivate,
          plan.width,
          plan.height,
          format: plan.kind == .heatmap
              ? .r16g16b16a16Float
              : .r8g8b8a8UNormInt,
        );
        _textures[plan.targetId] = texture;
        _kinds[plan.targetId] = plan.kind;
      }
      final commands = gpu.gpuContext.createCommandBuffer();
      final pass = commands.createRenderPass(
        gpu.RenderTarget(
          colorAttachments: [
            gpu.ColorAttachment(
              texture: texture,
              loadAction: .clear,
              storeAction: .store,
              clearValue: _transparent,
            ),
          ],
        ),
      );
      pass.setColorBlendEnable(plan.kind == .heatmap);
      if (plan.kind == .heatmap) {
        pass.setColorBlendEquation(_additiveBlend);
      }
      pass.setDepthWriteEnable(false);
      var start = plan.start;
      while (start < plan.end) {
        final entry = entries[start];
        var end = start + 1;
        while (end < plan.end &&
            entries[end].pipelineKey == entry.pipelineKey) {
          end++;
        }
        drawCount += executor.drawRun(
          pass,
          frame.binder!.pipelineFor(entry),
          entries,
          start,
          end,
          frame.binder!,
          hasDepthStencilAttachment: false,
          propsAreRunConstant: false,
        );
        start = end;
      }
      commands.submit();
    }
    for (final index in frame._graphState.offscreenTopology.compositeIndices) {
      final entry = entries[index];
      entry.sampledRenderTarget = _textures[entry.renderTargetId]!;
    }
    _recorded = true;

    return (drawCount: drawCount, renderPassCount: plans.length);
  }

  void beginFrame() => _recorded = false;

  void dispose() {
    _textures.clear();
    _kinds.clear();
    _recorded = false;
  }
}

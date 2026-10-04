part of '../renderer.dart';

/// Owns density targets shared by all compositing strata in a frame.
final class _HeatmapPasses {
  final _textures = <int, gpu.Texture>{};
  var _recorded = false;
  final _transparent = vector_math.Vector4.zero();
  final _additiveBlend = gpu.ColorBlendEquation(
    sourceColorBlendFactor: .one,
    destinationColorBlendFactor: .one,
    sourceAlphaBlendFactor: .one,
    destinationAlphaBlendFactor: .one,
  );

  /// Submits density passes before any stratum samples their textures.
  ///
  /// Each target uses its own command buffer so backends restricted to one
  /// render target per command buffer keep the same attachment throughout.
  _FrameDrawResult render(GpuPreparedFrame frame, FramePassExecutor executor) {
    if (_recorded) return (drawCount: 0, renderPassCount: 0);
    final entries = frame._graphState.graph.entries;
    final plans = planHeatmapPasses(entries);
    final activeIds = plans.map((plan) => plan.targetId).toSet();
    _textures.removeWhere((id, _) => !activeIds.contains(id));
    var drawCount = 0;
    for (final plan in plans) {
      var texture = _textures[plan.targetId];
      if (texture == null ||
          texture.width != plan.width ||
          texture.height != plan.height) {
        texture = gpu.gpuContext.createTexture(
          .devicePrivate,
          plan.width,
          plan.height,
          format: .r16g16b16a16Float,
        );
        _textures[plan.targetId] = texture;
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
      pass.setColorBlendEnable(true);
      pass.setColorBlendEquation(_additiveBlend);
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
    for (final entry in entries) {
      if (entry.shader == ShaderType.heatmapTexture) {
        entry.heatmapTexture = _textures[entry.renderTargetId]!;
      }
    }
    _recorded = true;

    return (drawCount: drawCount, renderPassCount: plans.length);
  }

  void beginFrame() {
    _recorded = false;
  }

  void dispose() {
    _textures.clear();
    _recorded = false;
  }
}

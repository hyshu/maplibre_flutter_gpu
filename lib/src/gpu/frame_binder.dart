import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame/gpu_state.dart';
import 'draw_entry.dart';
import 'pipeline_registry.dart';

/// Binds pipelines, uniforms, and textures for one frame's draw entries.
///
/// Pipeline-specific binding slots are described by [ResolvedPipeline].
class FrameBinder {
  FrameBinder({
    required this._pipelines,
    required this._uniformBuffer,
    required this._mapGlobalOffset,
    required this._cacheUniformViews,
  });

  final MapPipelineRegistry _pipelines;
  final gpu.DeviceBuffer _uniformBuffer;
  final int _mapGlobalOffset;
  final bool _cacheUniformViews;

  /// Returns the color-pass pipeline selected for [entry].
  ResolvedPipeline pipelineFor(DrawEntry entry) =>
      _pipelines[entry.pipelineKey!];

  /// Returns the depth-prepass pipeline selected for [entry].
  ResolvedPipeline depthPipelineFor(DrawEntry entry) =>
      _pipelines[entry.depthPipelineKey!];

  /// Binds uniforms that are identical for every draw in a pipeline run.
  void bindRunConstants(
    gpu.RenderPass pass,
    ResolvedPipeline pipeline,
    DrawEntry first, {
    required bool bindProps,
  }) {
    final views = first.uniformViews(
      _uniformBuffer,
      _mapGlobalOffset,
      cache: _cacheUniformViews,
    );
    final vertexGlobal = pipeline.vertexGlobal;
    if (vertexGlobal != null) {
      pass.bindUniform(vertexGlobal, views.global);
    }
    if (bindProps) _bindProps(pass, pipeline, views);
  }

  /// Binds the per-entry uniforms and texture available to [pipeline].
  void bind(
    gpu.RenderPass pass,
    ResolvedPipeline pipeline,
    DrawEntry entry, {
    required bool bindProps,
  }) {
    final views = entry.uniformViews(
      _uniformBuffer,
      _mapGlobalOffset,
      cache: _cacheUniformViews,
    );
    final drawable = views.drawable;
    pass.bindUniform(pipeline.vertexDrawable, drawable);
    final fragmentDrawable = pipeline.fragmentDrawable;
    if (fragmentDrawable != null) {
      pass.bindUniform(fragmentDrawable, drawable);
    }

    if (bindProps) _bindProps(pass, pipeline, views);

    // A pipeline can declare tile props for a command that exported none. A
    // zero length indicates that no tile props are available.
    if (entry.tilePropsUniformLength > 0) {
      final tileProps = views.tileProps;
      final vertexTileProps = pipeline.vertexTileProps;
      final fragmentTileProps = pipeline.fragmentTileProps;
      if (vertexTileProps != null) {
        pass.bindUniform(vertexTileProps, tileProps);
      }
      if (fragmentTileProps != null) {
        pass.bindUniform(fragmentTileProps, tileProps);
      }
    }

    final fragmentImage = pipeline.fragmentImage;
    final texture = entry.texture;
    if (fragmentImage != null && texture != null) {
      pass.bindTexture(
        fragmentImage,
        texture,
        sampler: samplerOptionsFor(entry.shader, entry.textureFilter),
      );
    }
  }

  static void _bindProps(
    gpu.RenderPass pass,
    ResolvedPipeline pipeline,
    UniformBindingViews views,
  ) {
    final vertexProps = pipeline.vertexProps;
    final fragmentProps = pipeline.fragmentProps;
    if (vertexProps == null && fragmentProps == null) return;
    final props = views.props;
    if (vertexProps != null) pass.bindUniform(vertexProps, props);
    if (fragmentProps != null) pass.bindUniform(fragmentProps, props);
  }
}

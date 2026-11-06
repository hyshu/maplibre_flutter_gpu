import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../fill_extrusion/fill_extrusion_renderer.dart';
import '../frame/pipeline_key.dart';
import 'gpu_profile_counters.dart';

/// A created pipeline and the uniform slots it binds.
///
/// A null optional slot means that the pipeline's shaders do not declare it.
/// Slots must be resolved from the shaders because resolving an undeclared
/// slot throws.
class const ResolvedPipeline({
  required final gpu.RenderPipeline pipeline,

  /// The drawable UBO. Every pipeline binds it in the vertex stage.
  required final gpu.UniformSlot vertexDrawable,

  /// The drawable UBO used by the `background-pattern` fragment shader.
  ///
  /// Dart writes the atlas dimensions into MapLibre's unused padding in place
  /// of `GlobalPaintParamsUBO`.
  final gpu.UniformSlot? fragmentDrawable,

  /// The evaluated paint properties UBO for the corresponding shader stage.
  final gpu.UniformSlot? vertexProps,
  final gpu.UniformSlot? fragmentProps,

  /// The viewport-space values mirrored from MapLibre's
  /// `GlobalPaintParamsUBO` into `MapGlobalUBO`.
  final gpu.UniformSlot? vertexGlobal,

  /// The tile-specific shader properties.
  final gpu.UniformSlot? vertexTileProps,
  final gpu.UniformSlot? fragmentTileProps,

  /// The image sampler used by the fragment shader.
  final gpu.UniformSlot? fragmentImage,

  /// The premultiplied color ramp used by heatmap composition.
  final gpu.UniformSlot? fragmentColorRamp,

  /// The tile batch member table, bound in both stages of batched pipelines.
  final gpu.UniformSlot? vertexBatch,
  final gpu.UniformSlot? fragmentBatch,

  /// The tile mask sampled by batched fragments.
  final gpu.UniformSlot? fragmentTileMask,

  /// The application material drawn by this fill-extrusion pipeline.
  ///
  /// Its draws bind the entry's material vertex stream, and application
  /// attributes in the second slot, instead of the native vertex buffer.
  final FillExtrusionMaterial? fillExtrusionMaterial,
});

/// The shaders and UBO names one [RenderPipelineKey] is built from.
///
/// A slot is resolved only when its name or presence is specified here.
typedef PipelineSpec = ({
  String vertex,
  String fragment,
  String drawable,
  String? vertexProps,
  String? fragmentProps,
  String? tileProps,
  bool fragmentDrawable,
  bool vertexTileProps,
  bool mapGlobal,
  bool image,
  bool colorRamp,
  bool batch,
});

PipelineSpec _spec(
  String vertex,
  String fragment,
  String drawable, {
  String? vertexProps,
  String? fragmentProps,
  String? tileProps,
  bool fragmentDrawable = false,
  bool vertexTileProps = false,
  bool mapGlobal = false,
  bool image = false,
  bool colorRamp = false,
  bool batch = false,
}) => (
  vertex: vertex,
  fragment: fragment,
  drawable: drawable,
  vertexProps: vertexProps,
  fragmentProps: fragmentProps,
  tileProps: tileProps,
  fragmentDrawable: fragmentDrawable,
  vertexTileProps: vertexTileProps,
  mapGlobal: mapGlobal,
  image: image,
  colorRamp: colorRamp,
  batch: batch,
);

/// Creates a spec with evaluated properties in both shader stages.
PipelineSpec _lineSpec(
  String vertex,
  String fragment,
  String drawable, {
  String props = 'LineEvaluatedPropsUBO',
  String? tileProps,
  bool image = false,
  bool vertexTileProps = false,
  bool mapGlobal = true,
  bool batch = false,
}) => _spec(
  vertex,
  fragment,
  drawable,
  vertexProps: props,
  fragmentProps: props,
  tileProps: tileProps,
  vertexTileProps: vertexTileProps,
  mapGlobal: mapGlobal,
  image: image,
  batch: batch,
);

const _fillBatchDrawable = 'FillDrawableUBOBatch';
const _fillOutlineTriangulatedBatchDrawable =
    'FillOutlineTriangulatedDrawableUBOBatch';

/// Tile-batched variants draw several tiles with one command. Their drawable
/// and tile property blocks are member arrays, and their fragments sample the
/// tile mask.
final _tileBatchSpecs = <RenderPipelineKey, PipelineSpec>{
  .tileMaskId: _spec(
    'TileMaskIdVertex',
    'TileMaskIdFragment',
    'ClippingMaskDrawableUBO',
    fragmentProps: 'TileMaskIdUBO',
  ),
  .fillBatched: _spec(
    'FillBatchedVertex',
    'FillBatchedFragment',
    _fillBatchDrawable,
    fragmentProps: _fillProps,
    batch: true,
  ),
  .fillDataDrivenBatched: _spec(
    'FillDDBatchedVertex',
    'FillDDBatchedFragment',
    _fillBatchDrawable,
    vertexProps: _fillProps,
    batch: true,
  ),
  .fillOutlineBatched: _spec(
    'FillOutlineBatchedVertex',
    'FillOutlineBatchedFragment',
    _fillBatchDrawable,
    fragmentProps: _fillProps,
    batch: true,
  ),
  .fillOutlineTriangulatedBatched: _spec(
    'FillOutlineTriangulatedBatchedVertex',
    'FillOutlineTriangulatedBatchedFragment',
    _fillOutlineTriangulatedBatchDrawable,
    fragmentProps: _fillProps,
    mapGlobal: true,
    batch: true,
  ),
  .fillOutlineTriangulatedPackedBatched: _spec(
    'FillOutlineTriangulatedPackedBatchedVertex',
    'FillOutlineTriangulatedBatchedFragment',
    _fillOutlineTriangulatedBatchDrawable,
    fragmentProps: _fillProps,
    mapGlobal: true,
    batch: true,
  ),
  .fillOutlineTriangulatedDataDrivenBatched: _spec(
    'FillOutlineTriangulatedDDBatchedVertex',
    'FillOutlineTriangulatedDDBatchedFragment',
    _fillOutlineTriangulatedBatchDrawable,
    vertexProps: _fillProps,
    mapGlobal: true,
    batch: true,
  ),
  .lineBatched: _lineSpec(
    'LineBatchedVertex',
    'LineBatchedFragment',
    'LineDrawableUBOBatch',
    batch: true,
  ),
  .linePackedBatched: _lineSpec(
    'LinePackedBatchedVertex',
    'LineBatchedFragment',
    'LineDrawableUBOBatch',
    batch: true,
  ),
  .lineDataDrivenBatched: _lineSpec(
    'LineDDBatchedVertex',
    'LineDDBatchedFragment',
    'LineDrawableUBOBatch',
    batch: true,
  ),
  .lineSdfBatched: _lineSpec(
    'LineSDFBatchedVertex',
    'LineSDFBatchedFragment',
    'LineSDFDrawableUBOBatch',
    tileProps: 'LineSDFTilePropsUBOBatch',
    image: true,
    batch: true,
  ),
  .lineSdfPackedBatched: _lineSpec(
    'LineSDFPackedBatchedVertex',
    'LineSDFBatchedFragment',
    'LineSDFDrawableUBOBatch',
    tileProps: 'LineSDFTilePropsUBOBatch',
    image: true,
    batch: true,
  ),
  .lineSdfDataDrivenBatched: _lineSpec(
    'LineSDFDDBatchedVertex',
    'LineSDFDDBatchedFragment',
    'LineSDFDrawableUBOBatch',
    tileProps: 'LineSDFTilePropsUBOBatch',
    image: true,
    batch: true,
  ),
  .lineGradientBatched: _lineSpec(
    'LineGradientBatchedVertex',
    'LineGradientBatchedFragment',
    'LineGradientDrawableUBOBatch',
    image: true,
    batch: true,
  ),
  .lineGradientPackedBatched: _lineSpec(
    'LineGradientPackedBatchedVertex',
    'LineGradientBatchedFragment',
    'LineGradientDrawableUBOBatch',
    image: true,
    batch: true,
  ),
  .lineGradientDataDrivenBatched: _lineSpec(
    'LineGradientDDBatchedVertex',
    'LineGradientDDBatchedFragment',
    'LineGradientDrawableUBOBatch',
    image: true,
    batch: true,
  ),
  .circleBatched: _lineSpec(
    'CircleBatchedVertex',
    'CircleBatchedFragment',
    'CircleDrawableUBOBatch',
    props: 'CircleEvaluatedPropsUBO',
    mapGlobal: false,
    batch: true,
  ),
  .circleDataDrivenBatched: _lineSpec(
    'CircleDDBatchedVertex',
    'CircleDDBatchedFragment',
    'CircleDrawableUBOBatch',
    props: 'CircleEvaluatedPropsUBO',
    mapGlobal: false,
    batch: true,
  ),
};

const _fillDrawable = 'FillDrawableUBO';
const _fillProps = 'FillEvaluatedPropsUBO';
const _fillOutlineTriangulatedDrawable = 'FillOutlineTriangulatedDrawableUBO';
const _fillExtrusionDrawable = 'FillExtrusionDrawableUBO';
const _fillExtrusionProps = 'FillExtrusionPropsUBO';

/// Every pipeline's shader pair and slot shape, in one table.
const _pipelineSpecs = <RenderPipelineKey, PipelineSpec>{
  .fill: (
    vertex: 'FillVertex',
    fragment: 'FillFragment',
    drawable: _fillDrawable,
    vertexProps: null,
    fragmentProps: _fillProps,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  // Data-driven color/opacity. Both UBOs are consumed in the vertex stage
  // because the fragment receives the already evaluated paint values.
  .fillDataDriven: (
    vertex: 'FillDDVertex',
    fragment: 'FillDDFragment',
    drawable: _fillDrawable,
    vertexProps: _fillProps,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  // Merged fills use screen-space vertices and never carry tile stencil state.
  .fillMerged: (
    vertex: 'FillMergedVertex',
    fragment: 'FillMergedFragment',
    drawable: _fillDrawable,
    vertexProps: null,
    fragmentProps: _fillProps,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .fillOutline: (
    vertex: 'FillOutlineVertex',
    fragment: 'FillOutlineFragment',
    drawable: _fillDrawable,
    vertexProps: null,
    fragmentProps: _fillProps,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .fillOutlineTriangulated: (
    vertex: 'FillOutlineTriangulatedVertex',
    fragment: 'FillOutlineTriangulatedFragment',
    drawable: _fillOutlineTriangulatedDrawable,
    vertexProps: null,
    fragmentProps: _fillProps,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: true,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .fillOutlineTriangulatedPacked: (
    vertex: 'FillOutlineTriangulatedPackedVertex',
    fragment: 'FillOutlineTriangulatedFragment',
    drawable: _fillOutlineTriangulatedDrawable,
    vertexProps: null,
    fragmentProps: _fillProps,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: true,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  // The vertex shader evaluates outline color and opacity before passing them
  // to the fragment shader.
  .fillOutlineTriangulatedDataDriven: (
    vertex: 'FillOutlineTriangulatedDDVertex',
    fragment: 'FillOutlineTriangulatedDDFragment',
    drawable: _fillOutlineTriangulatedDrawable,
    vertexProps: _fillProps,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: true,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  // New native builds upload the original packed 12/44-byte FE vertices.
  .fillExtrusion: (
    vertex: 'FillExtrusionVertex',
    fragment: 'FillExtrusionFragment',
    drawable: _fillExtrusionDrawable,
    vertexProps: _fillExtrusionProps,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .fillExtrusionDataDriven: (
    vertex: 'FillExtrusionDDVertex',
    fragment: 'FillExtrusionFragment',
    drawable: _fillExtrusionDrawable,
    vertexProps: _fillExtrusionProps,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .fillExtrusionDepth: (
    vertex: 'FillExtrusionVertex',
    fragment: 'FillExtrusionDepthFragment',
    drawable: _fillExtrusionDrawable,
    vertexProps: _fillExtrusionProps,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .fillExtrusionDataDrivenDepth: (
    vertex: 'FillExtrusionDDVertex',
    fragment: 'FillExtrusionDepthFragment',
    drawable: _fillExtrusionDrawable,
    vertexProps: _fillExtrusionProps,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  // Compatibility with already-packaged native artifacts that set bit24 and
  // expose the old 56-byte float-expanded DD layout.
  .fillExtrusionExpandedDataDriven: (
    vertex: 'FillExtrusionExpandedDDVertex',
    fragment: 'FillExtrusionFragment',
    drawable: _fillExtrusionDrawable,
    vertexProps: _fillExtrusionProps,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .fillExtrusionExpandedDataDrivenDepth: (
    vertex: 'FillExtrusionExpandedDDVertex',
    fragment: 'FillExtrusionDepthFragment',
    drawable: _fillExtrusionDrawable,
    vertexProps: _fillExtrusionProps,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .clippingMask: (
    vertex: 'ClippingMaskVertex',
    fragment: 'ClippingMaskFragment',
    drawable: 'ClippingMaskDrawableUBO',
    vertexProps: null,
    fragmentProps: null,
    tileProps: null,
    fragmentDrawable: false,
    vertexTileProps: false,
    mapGlobal: false,
    image: false,
    colorRamp: false,
    batch: false,
  ),
  .backgroundPattern: (
    vertex: 'BackgroundPatternVertex',
    fragment: 'BackgroundPatternFragment',
    drawable: 'BackgroundPatternDrawableUBO',
    vertexProps: 'BackgroundPatternPropsUBO',
    fragmentProps: 'BackgroundPatternPropsUBO',
    tileProps: null,
    fragmentDrawable: true,
    vertexTileProps: false,
    mapGlobal: false,
    image: true,
    colorRamp: false,
    batch: false,
  ),
};

/// Pipelines that share the slot layout produced by [_lineSpec].
///
/// Circle and raster use this layout even though they are not line shaders.
final _lineFamilySpecs = <RenderPipelineKey, PipelineSpec>{
  .line: _lineSpec('LineVertex', 'LineFragment', 'LineDrawableUBO'),
  .linePacked: _lineSpec('LinePackedVertex', 'LineFragment', 'LineDrawableUBO'),
  .lineDataDriven: _lineSpec(
    'LineDDVertex',
    'LineDDFragment',
    'LineDrawableUBO',
  ),
  .lineSdf: _lineSpec(
    'LineSDFVertex',
    'LineSDFFragment',
    'LineSDFDrawableUBO',
    tileProps: 'LineSDFTilePropsUBO',
    image: true,
  ),
  .lineSdfPacked: _lineSpec(
    'LineSDFPackedVertex',
    'LineSDFFragment',
    'LineSDFDrawableUBO',
    tileProps: 'LineSDFTilePropsUBO',
    image: true,
  ),
  .lineSdfDataDriven: _lineSpec(
    'LineSDFDDVertex',
    'LineSDFDDFragment',
    'LineSDFDrawableUBO',
    tileProps: 'LineSDFTilePropsUBO',
    image: true,
  ),
  .lineGradient: _lineSpec(
    'LineGradientVertex',
    'LineGradientFragment',
    'LineGradientDrawableUBO',
    image: true,
  ),
  .lineGradientPacked: _lineSpec(
    'LineGradientPackedVertex',
    'LineGradientFragment',
    'LineGradientDrawableUBO',
    image: true,
  ),
  .lineGradientDataDriven: _lineSpec(
    'LineGradientDDVertex',
    'LineGradientDDFragment',
    'LineGradientDrawableUBO',
    image: true,
  ),
  .linePattern: _lineSpec(
    'LinePatternVertex',
    'LinePatternFragment',
    'LinePatternDrawableUBO',
    tileProps: 'LinePatternTilePropsUBO',
    image: true,
    vertexTileProps: true,
  ),
  .linePatternPacked: _lineSpec(
    'LinePatternPackedVertex',
    'LinePatternFragment',
    'LinePatternDrawableUBO',
    tileProps: 'LinePatternTilePropsUBO',
    image: true,
    vertexTileProps: true,
  ),
  .linePatternDataDriven: _lineSpec(
    'LinePatternDDVertex',
    'LinePatternDDFragment',
    'LinePatternDrawableUBO',
    tileProps: 'LinePatternTilePropsUBO',
    image: true,
    vertexTileProps: true,
  ),
  .circle: _lineSpec(
    'CircleVertex',
    'CircleFragment',
    'CircleDrawableUBO',
    props: 'CircleEvaluatedPropsUBO',
    mapGlobal: false,
  ),
  .circleDataDriven: _lineSpec(
    'CircleDDVertex',
    'CircleDDFragment',
    'CircleDrawableUBO',
    props: 'CircleEvaluatedPropsUBO',
    mapGlobal: false,
  ),
  .heatmap: _lineSpec(
    'HeatmapVertex',
    'HeatmapFragment',
    'HeatmapDrawableUBO',
    props: 'HeatmapEvaluatedPropsUBO',
    mapGlobal: false,
  ),
  .heatmapDataDriven: _lineSpec(
    'HeatmapDDVertex',
    'HeatmapFragment',
    'HeatmapDrawableUBO',
    props: 'HeatmapEvaluatedPropsUBO',
    mapGlobal: false,
  ),
  .heatmapTexture: _spec(
    'HeatmapTextureVertex',
    'HeatmapTextureFragment',
    'HeatmapTexturePropsUBO',
    fragmentDrawable: true,
    mapGlobal: true,
    image: true,
    colorRamp: true,
    batch: false,
  ),
  .hillshadePrepare: _spec(
    'HillshadePrepareVertex',
    'HillshadePrepareFragment',
    'HillshadePrepareDrawableUBO',
    tileProps: 'HillshadePrepareTilePropsUBO',
    vertexTileProps: true,
    image: true,
  ),
  .hillshade: _spec(
    'HillshadeVertex',
    'HillshadeFragment',
    'HillshadeDrawableUBO',
    fragmentProps: 'HillshadeEvaluatedPropsUBO',
    tileProps: 'HillshadeTilePropsUBO',
    image: true,
  ),
  .raster: _lineSpec(
    'RasterVertex',
    'RasterFragment',
    'RasterDrawableUBO',
    props: 'RasterEvaluatedPropsUBO',
    mapGlobal: false,
    image: true,
  ),
};

final _specs = <RenderPipelineKey, PipelineSpec>{
  ..._pipelineSpecs,
  ..._lineFamilySpecs,
  ..._tileBatchSpecs,
};

/// Creates each pipeline once, on first use, and keeps its uniform slots.
class MapPipelineRegistry(final gpu.ShaderLibrary _shaderLibrary) {
  final List<ResolvedPipeline?> _resolved = .filled(
    RenderPipelineKey.values.length,
    null,
  );

  /// Keys covered by the spec table. Every [RenderPipelineKey] must appear.
  @visibleForTesting
  static Iterable<RenderPipelineKey> get specifiedKeys => _specs.keys;

  /// The pipeline for [key], created on first use.
  ResolvedPipeline operator [](RenderPipelineKey key) =>
      _resolved[key.index] ??= _create(
        _specs[key] ?? (throw StateError('No pipeline spec for $key')),
      );

  /// Creates the fill extrusion pipelines before their first rendered frame.
  ///
  /// This avoids performing backend pipeline creation when an extrusion first
  /// becomes visible during a camera gesture.
  void prewarmFillExtrusionPipelines() {
    this[.fillExtrusion];
    this[.fillExtrusionDepth];
    this[.fillExtrusionDataDriven];
    this[.fillExtrusionDataDrivenDepth];
    this[.fillExtrusionExpandedDataDriven];
    this[.fillExtrusionExpandedDataDrivenDepth];
  }

  /// Returns the pipelines in [keys] that have not been created yet.
  List<RenderPipelineKey> missing(Iterable<RenderPipelineKey> keys) => [
    for (final key in keys)
      if (_resolved[key.index] == null) key,
  ];

  /// Creates every pipeline in [keys] that does not exist yet.
  ///
  /// Returns the number of pipelines created. Creating pipelines before a
  /// layer type first appears keeps backend pipeline compilation out of
  /// camera gestures.
  int prewarm(Iterable<RenderPipelineKey> keys) {
    var created = 0;
    for (final key in keys) {
      if (_resolved[key.index] != null) continue;
      this[key];
      created += 1;
    }

    return created;
  }

  ResolvedPipeline _create(PipelineSpec spec) {
    final stopwatch = GpuProfileCounters.enabled
        ? (Stopwatch()..start())
        : null;
    final pipeline = _createUncounted(spec);
    if (stopwatch != null) {
      GpuProfileCounters.add(GpuProfileCounters.gpuPipelinesCreated);
      GpuProfileCounters.add(
        GpuProfileCounters.gpuPipelineMicros,
        stopwatch.elapsedMicroseconds,
      );
    }

    return pipeline;
  }

  ResolvedPipeline _createUncounted(PipelineSpec spec) {
    final vertex = _shader(spec.vertex);
    final fragment = _shader(spec.fragment);
    final tileProps = spec.tileProps;

    return ResolvedPipeline(
      pipeline: gpu.gpuContext.createRenderPipeline(vertex, fragment),
      vertexDrawable: vertex.getUniformSlot(spec.drawable),
      fragmentDrawable: spec.fragmentDrawable
          ? fragment.getUniformSlot(spec.drawable)
          : null,
      vertexProps: spec.vertexProps == null
          ? null
          : vertex.getUniformSlot(spec.vertexProps!),
      fragmentProps: spec.fragmentProps == null
          ? null
          : fragment.getUniformSlot(spec.fragmentProps!),
      vertexGlobal: spec.mapGlobal
          ? vertex.getUniformSlot('MapGlobalUBO')
          : null,
      vertexTileProps: spec.vertexTileProps && tileProps != null
          ? vertex.getUniformSlot(tileProps)
          : null,
      fragmentTileProps: tileProps == null
          ? null
          : fragment.getUniformSlot(tileProps),
      fragmentImage: spec.image ? fragment.getUniformSlot('u_image') : null,
      fragmentColorRamp: spec.colorRamp
          ? fragment.getUniformSlot('u_color_ramp')
          : null,
      vertexBatch: spec.batch ? vertex.getUniformSlot('TileBatchUBO') : null,
      fragmentBatch: spec.batch
          ? fragment.getUniformSlot('TileBatchUBO')
          : null,
      fragmentTileMask: spec.batch
          ? fragment.getUniformSlot('u_tile_mask')
          : null,
    );
  }

  gpu.Shader _shader(String name) {
    final shader = _shaderLibrary[name];
    if (shader == null) throw Exception('Shader not found: $name');

    return shader;
  }
}

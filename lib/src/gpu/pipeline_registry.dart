import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame/pipeline_key.dart';

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
);

const _fillDrawable = 'FillDrawableUBO';
const _fillProps = 'FillEvaluatedPropsUBO';
const _fillOutlineTriangulatedDrawable = 'FillOutlineTriangulatedDrawableUBO';
const _fillExtrusionDrawable = 'FillExtrusionDrawableUBO';
const _fillExtrusionProps = 'FillExtrusionPropsUBO';

/// Every pipeline's shader pair and slot shape, in one table.
const Map<RenderPipelineKey, PipelineSpec> _pipelineSpecs = {
  RenderPipelineKey.fill: (
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
  ),
  // Data-driven color/opacity. Both UBOs are consumed in the vertex stage
  // because the fragment receives the already evaluated paint values.
  RenderPipelineKey.fillDataDriven: (
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
  ),
  // Merged fills use screen-space vertices and never carry tile stencil state.
  RenderPipelineKey.fillMerged: (
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
  ),
  RenderPipelineKey.fillOutline: (
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
  ),
  RenderPipelineKey.fillOutlineTriangulated: (
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
  ),
  // The vertex shader evaluates outline color and opacity before passing them
  // to the fragment shader.
  RenderPipelineKey.fillOutlineTriangulatedDataDriven: (
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
  ),
  // New native builds upload the original packed 12/44-byte FE vertices.
  RenderPipelineKey.fillExtrusion: (
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
  ),
  RenderPipelineKey.fillExtrusionDataDriven: (
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
  ),
  RenderPipelineKey.fillExtrusionDepth: (
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
  ),
  RenderPipelineKey.fillExtrusionDataDrivenDepth: (
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
  ),
  // Compatibility with already-packaged native artifacts that set bit24 and
  // expose the old 56-byte float-expanded DD layout.
  RenderPipelineKey.fillExtrusionExpandedDataDriven: (
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
  ),
  RenderPipelineKey.fillExtrusionExpandedDataDrivenDepth: (
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
  ),
  RenderPipelineKey.clippingMask: (
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
  ),
  RenderPipelineKey.backgroundPattern: (
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
  ),
};

/// Pipelines that share the slot layout produced by [_lineSpec].
///
/// Circle and raster use this layout even though they are not line shaders.
final Map<RenderPipelineKey, PipelineSpec> _lineFamilySpecs = {
  RenderPipelineKey.line: _lineSpec(
    'LineVertex',
    'LineFragment',
    'LineDrawableUBO',
  ),
  RenderPipelineKey.lineDataDriven: _lineSpec(
    'LineDDVertex',
    'LineDDFragment',
    'LineDrawableUBO',
  ),
  RenderPipelineKey.lineSdf: _lineSpec(
    'LineSDFVertex',
    'LineSDFFragment',
    'LineSDFDrawableUBO',
    tileProps: 'LineSDFTilePropsUBO',
    image: true,
  ),
  RenderPipelineKey.lineSdfDataDriven: _lineSpec(
    'LineSDFDDVertex',
    'LineSDFDDFragment',
    'LineSDFDrawableUBO',
    tileProps: 'LineSDFTilePropsUBO',
    image: true,
  ),
  RenderPipelineKey.lineGradient: _lineSpec(
    'LineGradientVertex',
    'LineGradientFragment',
    'LineGradientDrawableUBO',
    image: true,
  ),
  RenderPipelineKey.lineGradientDataDriven: _lineSpec(
    'LineGradientDDVertex',
    'LineGradientDDFragment',
    'LineGradientDrawableUBO',
    image: true,
  ),
  RenderPipelineKey.linePattern: _lineSpec(
    'LinePatternVertex',
    'LinePatternFragment',
    'LinePatternDrawableUBO',
    tileProps: 'LinePatternTilePropsUBO',
    image: true,
    vertexTileProps: true,
  ),
  RenderPipelineKey.linePatternDataDriven: _lineSpec(
    'LinePatternDDVertex',
    'LinePatternDDFragment',
    'LinePatternDrawableUBO',
    tileProps: 'LinePatternTilePropsUBO',
    image: true,
    vertexTileProps: true,
  ),
  RenderPipelineKey.circle: _lineSpec(
    'CircleVertex',
    'CircleFragment',
    'CircleDrawableUBO',
    props: 'CircleEvaluatedPropsUBO',
    mapGlobal: false,
  ),
  RenderPipelineKey.circleDataDriven: _lineSpec(
    'CircleDDVertex',
    'CircleDDFragment',
    'CircleDrawableUBO',
    props: 'CircleEvaluatedPropsUBO',
    mapGlobal: false,
  ),
  RenderPipelineKey.raster: _lineSpec(
    'RasterVertex',
    'RasterFragment',
    'RasterDrawableUBO',
    props: 'RasterEvaluatedPropsUBO',
    mapGlobal: false,
    image: true,
  ),
};

final Map<RenderPipelineKey, PipelineSpec> _specs = {
  ..._pipelineSpecs,
  ..._lineFamilySpecs,
};

/// Creates each pipeline once, on first use, and keeps its uniform slots.
class MapPipelineRegistry(final gpu.ShaderLibrary _shaderLibrary) {
  final List<ResolvedPipeline?> _resolved = List<ResolvedPipeline?>.filled(
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
    this[RenderPipelineKey.fillExtrusion];
    this[RenderPipelineKey.fillExtrusionDepth];
    this[RenderPipelineKey.fillExtrusionDataDriven];
    this[RenderPipelineKey.fillExtrusionDataDrivenDepth];
    this[RenderPipelineKey.fillExtrusionExpandedDataDriven];
    this[RenderPipelineKey.fillExtrusionExpandedDataDrivenDepth];
  }

  ResolvedPipeline _create(PipelineSpec spec) {
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
    );
  }

  gpu.Shader _shader(String name) {
    final shader = _shaderLibrary[name];
    if (shader == null) throw Exception('Shader not found: $name');

    return shader;
  }
}

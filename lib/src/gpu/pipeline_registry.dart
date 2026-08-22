import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame/pipeline_key.dart';

/// A created pipeline and the uniform slots it binds.
///
/// A null optional slot means that the pipeline's shaders do not declare it.
/// Slots must be resolved from the shaders because resolving an undeclared
/// slot throws.
class ResolvedPipeline {
  const ResolvedPipeline({
    required this.pipeline,
    required this.vertexDrawable,
    this.fragmentDrawable,
    this.vertexProps,
    this.fragmentProps,
    this.vertexGlobal,
    this.vertexTileProps,
    this.fragmentTileProps,
    this.fragmentImage,
  });

  final gpu.RenderPipeline pipeline;
  final gpu.UniformSlot vertexDrawable;
  final gpu.UniformSlot? fragmentDrawable;
  final gpu.UniformSlot? vertexProps;
  final gpu.UniformSlot? fragmentProps;
  final gpu.UniformSlot? vertexGlobal;
  final gpu.UniformSlot? vertexTileProps;
  final gpu.UniformSlot? fragmentTileProps;
  final gpu.UniformSlot? fragmentImage;
}

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

const _fillExtrusionPackedLayout = gpu.VertexLayout(
  buffers: <gpu.VertexBuffer>[
    gpu.VertexBuffer(
      strideInBytes: 12,
      attributes: <gpu.VertexAttribute>[
        gpu.VertexAttribute(
          name: 'a_layout_packed',
          format: gpu.VertexFormat.uint32x3,
        ),
      ],
    ),
  ],
);

const _fillExtrusionPackedDataDrivenLayout = gpu.VertexLayout(
  buffers: <gpu.VertexBuffer>[
    gpu.VertexBuffer(
      strideInBytes: 44,
      attributes: <gpu.VertexAttribute>[
        gpu.VertexAttribute(
          name: 'a_layout_packed',
          format: gpu.VertexFormat.uint32x3,
        ),
        gpu.VertexAttribute(
          name: 'a_base_range',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 12,
        ),
        gpu.VertexAttribute(
          name: 'a_height_range',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 20,
        ),
        gpu.VertexAttribute(
          name: 'a_color_range',
          format: gpu.VertexFormat.float32x4,
          offsetInBytes: 28,
        ),
      ],
    ),
  ],
);

const _fillExtrusionPackedColorDataDrivenLayout = gpu.VertexLayout(
  buffers: <gpu.VertexBuffer>[
    gpu.VertexBuffer(
      strideInBytes: 36,
      attributes: <gpu.VertexAttribute>[
        gpu.VertexAttribute(
          name: 'a_layout_packed',
          format: gpu.VertexFormat.uint32x3,
        ),
        gpu.VertexAttribute(
          name: 'a_base_range',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 12,
        ),
        gpu.VertexAttribute(
          name: 'a_height_range',
          format: gpu.VertexFormat.float32x2,
          offsetInBytes: 20,
        ),
        gpu.VertexAttribute(
          name: 'a_color_range_packed',
          format: gpu.VertexFormat.uint32x2,
          offsetInBytes: 28,
        ),
      ],
    ),
  ],
);

gpu.VertexLayout? _vertexLayoutFor(String vertexShader) => switch (vertexShader) {
  'FillExtrusionVertex' => _fillExtrusionPackedLayout,
  'FillExtrusionDDVertex' => _fillExtrusionPackedDataDrivenLayout,
  'FillExtrusionDDPackedColorVertex' =>
    _fillExtrusionPackedColorDataDrivenLayout,
  _ => null,
};

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
  RenderPipelineKey.fillExtrusionPackedColorDataDriven: (
    vertex: 'FillExtrusionDDPackedColorVertex',
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
  RenderPipelineKey.fillExtrusionPackedColorDataDrivenDepth: (
    vertex: 'FillExtrusionDDPackedColorVertex',
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

class MapPipelineRegistry {
  MapPipelineRegistry(this._shaderLibrary);

  final gpu.ShaderLibrary _shaderLibrary;
  final List<ResolvedPipeline?> _resolved = List<ResolvedPipeline?>.filled(
    RenderPipelineKey.values.length,
    null,
  );

  @visibleForTesting
  static Iterable<RenderPipelineKey> get specifiedKeys => _specs.keys;

  ResolvedPipeline operator [](RenderPipelineKey key) =>
      _resolved[key.index] ??= _create(
        _specs[key] ?? (throw StateError('No pipeline spec for $key')),
      );

  void prewarmFillExtrusionPipelines() {
    this[RenderPipelineKey.fillExtrusion];
    this[RenderPipelineKey.fillExtrusionDepth];
    this[RenderPipelineKey.fillExtrusionDataDriven];
    this[RenderPipelineKey.fillExtrusionDataDrivenDepth];
    this[RenderPipelineKey.fillExtrusionPackedColorDataDriven];
    this[RenderPipelineKey.fillExtrusionPackedColorDataDrivenDepth];
    this[RenderPipelineKey.fillExtrusionExpandedDataDriven];
    this[RenderPipelineKey.fillExtrusionExpandedDataDrivenDepth];
  }

  ResolvedPipeline _create(PipelineSpec spec) {
    final vertex = _shader(spec.vertex);
    final fragment = _shader(spec.fragment);
    final tileProps = spec.tileProps;

    return ResolvedPipeline(
      pipeline: gpu.gpuContext.createRenderPipeline(
        vertex,
        fragment,
        vertexLayout: _vertexLayoutFor(spec.vertex),
      ),
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

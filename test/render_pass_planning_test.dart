import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/render_pass_plan.dart';

RenderPassPlanningEntry _entry({
  int shader = ShaderType.fill,
  int flags = 0,
  int layer = 0,
  int stencilMode = StencilModeType.disabled,
  required Object? pipeline,
  Object? depthPipeline,
  double opacity = 1.0,
}) => .new(
  shader: shader,
  flags: flags,
  layer: layer,
  stencilMode: stencilMode,
  pipelineIdentity: pipeline,
  depthPipelineIdentity: depthPipeline,
  fillExtrusionOpacity: opacity,
);

void main() {
  test(
    'only adjacent entries with identical pipeline and state share a run',
    () {
      final pipelineA = Object();
      final pipelineB = Object();
      const depthTest = 1 << 22;
      const depthWrite = 1 << 23;
      final plans = planRenderPasses(
        [
          _entry(pipeline: pipelineA),
          _entry(pipeline: pipelineA),
          _entry(pipeline: pipelineB),
          _entry(pipeline: pipelineA),
          _entry(pipeline: pipelineA, flags: depthTest),
          _entry(pipeline: pipelineA, flags: depthTest | depthWrite),
        ],
        hasDepthStencilAttachment: true,
        attachmentInitiallyInitialized: false,
      );

      expect(plans.map((plan) => (plan.start, plan.end)), [
        (0, 2),
        (2, 3),
        (3, 4),
        (4, 5),
        (5, 6),
      ]);
      expect(plans.map((plan) => plan.pipelineIdentity), [
        pipelineA,
        pipelineB,
        pipelineA,
        pipelineA,
        pipelineA,
      ]);
      expect(plans[3].clearDepth, isTrue);
      expect(plans[3].clearStencil, isTrue);
      expect(plans[3].depthTest, isTrue);
      expect(plans[3].depthWrite, isFalse);
      expect(plans[4].clearDepth, isFalse);
      expect(plans[4].depthWrite, isTrue);
    },
  );

  test('stencil clear remains a single ordered control pass', () {
    final pipeline = Object();
    final plans = planRenderPasses(
      [
        _entry(pipeline: pipeline),
        _entry(
          shader: ShaderType.clippingMask,
          stencilMode: StencilModeType.clear,
          pipeline: null,
        ),
        _entry(pipeline: pipeline, stencilMode: StencilModeType.clippingTest),
      ],
      hasDepthStencilAttachment: true,
      attachmentInitiallyInitialized: false,
    );

    expect(plans.map((plan) => plan.kind), [
      RenderPassPlanKind.color,
      RenderPassPlanKind.stencilClear,
      RenderPassPlanKind.color,
    ]);
    expect(plans.map((plan) => (plan.start, plan.end)), [
      (0, 1),
      (1, 2),
      (2, 3),
    ]);
    expect(plans[1].clearDepth, isTrue);
    expect(plans[1].clearStencil, isTrue);
    expect(plans[2].clearDepth, isFalse);
    expect(plans[2].clearStencil, isFalse);
  });

  test('fill extrusion plans depth runs before color runs per layer', () {
    final fixedColor = Object();
    final dataDrivenColor = Object();
    final fixedDepth = Object();
    final dataDrivenDepth = Object();
    final plans = planRenderPasses(
      [
        _entry(
          shader: ShaderType.fillExtrusion,
          layer: 7,
          pipeline: fixedColor,
          depthPipeline: fixedDepth,
          opacity: 0.5,
        ),
        _entry(
          shader: ShaderType.fillExtrusion,
          layer: 7,
          pipeline: dataDrivenColor,
          depthPipeline: dataDrivenDepth,
          opacity: 1.0,
        ),
        _entry(
          shader: ShaderType.fillExtrusion,
          layer: 8,
          pipeline: dataDrivenColor,
          depthPipeline: dataDrivenDepth,
          opacity: 1.0,
        ),
      ],
      hasDepthStencilAttachment: true,
      attachmentInitiallyInitialized: false,
    );

    expect(plans.map((plan) => plan.kind), [
      RenderPassPlanKind.fillExtrusionDepth,
      RenderPassPlanKind.fillExtrusionDepth,
      RenderPassPlanKind.color,
      RenderPassPlanKind.color,
      RenderPassPlanKind.color,
    ]);
    expect(plans.map((plan) => (plan.start, plan.end)), [
      (0, 1),
      (1, 2),
      (0, 1),
      (1, 2),
      (2, 3),
    ]);
    expect(plans[0].pipelineIdentity, same(fixedDepth));
    expect(plans[1].pipelineIdentity, same(dataDrivenDepth));
    expect(plans[0].clearDepth, isTrue);
    expect(plans[1].clearDepth, isFalse);
    expect(plans[2].depthWrite, isFalse);
    expect(plans[3].depthWrite, isFalse);
    expect(plans[4].needsDepthPrepass, isFalse);
    expect(plans[4].depthWrite, isTrue);
  });

  test('NaN fill extrusion opacity conservatively adds a depth prepass', () {
    final color = Object();
    final depth = Object();
    final plans = planRenderPasses(
      [
        _entry(
          shader: ShaderType.fillExtrusion,
          pipeline: color,
          depthPipeline: depth,
          opacity: double.nan,
        ),
      ],
      hasDepthStencilAttachment: true,
      attachmentInitiallyInitialized: false,
    );

    expect(plans, hasLength(2));
    expect(plans.first.kind, RenderPassPlanKind.fillExtrusionDepth);
    expect(plans.last.kind, RenderPassPlanKind.color);
    expect(plans.last.needsDepthPrepass, isTrue);
    expect(plans.last.depthWrite, isFalse);
  });

  test('only first pass using the attachment clears it', () {
    final pipeline = Object();
    const depthTest = 1 << 22;
    final plans = planRenderPasses(
      [
        _entry(pipeline: pipeline),
        _entry(pipeline: pipeline, stencilMode: StencilModeType.clippingTest),
        _entry(pipeline: pipeline, flags: depthTest),
      ],
      hasDepthStencilAttachment: true,
      attachmentInitiallyInitialized: false,
    );

    expect(plans[0].needsDepthStencilAttachment, isFalse);
    expect(plans[0].clearDepth, isFalse);
    expect(plans[1].clearDepth, isTrue);
    expect(plans[1].clearStencil, isTrue);
    expect(plans[2].clearDepth, isFalse);
    expect(plans[2].clearStencil, isFalse);

    final initializedPlans = planRenderPasses(
      [_entry(pipeline: pipeline, stencilMode: StencilModeType.clippingTest)],
      hasDepthStencilAttachment: true,
      attachmentInitiallyInitialized: true,
    );
    expect(initializedPlans.single.clearDepth, isFalse);
    expect(initializedPlans.single.clearStencil, isFalse);
  });

  test('missing attachment omits extrusion prepass and depth state', () {
    final color = Object();
    final depth = Object();
    final plans = planRenderPasses(
      [
        _entry(
          shader: ShaderType.fillExtrusion,
          pipeline: color,
          depthPipeline: depth,
          opacity: 0.5,
        ),
      ],
      hasDepthStencilAttachment: false,
      attachmentInitiallyInitialized: false,
    );

    expect(plans, hasLength(1));
    expect(plans.single.kind, RenderPassPlanKind.color);
    expect(plans.single.needsDepthPrepass, isTrue);
    expect(plans.single.depthTest, isFalse);
    expect(plans.single.depthWrite, isFalse);
    expect(plans.single.clearDepth, isFalse);
    expect(plans.single.clearStencil, isFalse);
  });

  test('caller-owned output list is cleared and reused', () {
    final output = <RenderPassPlan>[];
    final pool = <RenderPassPlan>[];
    final pipeline = Object();

    final first = planRenderPasses(
      [_entry(pipeline: pipeline), _entry(pipeline: Object())],
      hasDepthStencilAttachment: false,
      attachmentInitiallyInitialized: false,
      output: output,
      pool: pool,
    );
    expect(identical(first, output), isTrue);
    expect(first, hasLength(2));
    final reusedPlan = first.first;

    final second = planRenderPasses(
      [_entry(pipeline: pipeline)],
      hasDepthStencilAttachment: false,
      attachmentInitiallyInitialized: false,
      output: output,
      pool: pool,
    );
    expect(identical(second, output), isTrue);
    expect(second, hasLength(1));
    expect(identical(second.first, reusedPlan), isTrue);
    expect(pool, hasLength(2));
  });

  test('custom 3D inserts after the last fill-extrusion pass', () {
    final fill = Object();
    final extrusion = Object();
    final entries = [
      _entry(pipeline: fill),
      _entry(
        shader: ShaderType.fillExtrusion,
        layer: 3,
        pipeline: extrusion,
        depthPipeline: Object(),
      ),
      _entry(pipeline: Object()),
    ];
    final plans = planRenderPasses(
      entries,
      hasDepthStencilAttachment: true,
      attachmentInitiallyInitialized: true,
    );

    expect(threeDimensionalRenderInsertionIndex(plans, entries), 2);
    expect(entries[plans[1].start].shader, ShaderType.fillExtrusion);
    expect(entries[plans[2].start].shader, ShaderType.fill);
  });

  test('custom 3D falls back to the end when style has no buildings', () {
    final entries = [_entry(pipeline: Object()), _entry(pipeline: Object())];
    final plans = planRenderPasses(
      entries,
      hasDepthStencilAttachment: true,
      attachmentInitiallyInitialized: true,
    );

    expect(threeDimensionalRenderInsertionIndex(plans, entries), plans.length);
  });
}

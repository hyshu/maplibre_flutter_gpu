// Groups decoded draw entries into the ordered render passes the frame needs.
//
// This is the step that decides where MapLibre's depth prepasses and mid-frame
// stencil clears fall relative to color work, so it is pure and testable
// against a synthetic entry list rather than a live GPU frame.
import 'package:flutter/foundation.dart';

import '../native/draw_command.dart';
import 'draw_flags.dart';

/// Work performed by a planned render pass.
enum RenderPassPlanKind { color, fillExtrusionDepth, stencilClear }

/// GPU-independent input used to reproduce MapLibre's ordered render passes.
abstract interface class RenderPassPlanningEntryView {
  int get shader;
  int get flags;
  int get layer;
  int get stencilMode;
  Object? get pipelineIdentity;
  Object? get depthPipelineIdentity;
  double get fillExtrusionOpacity;
}

/// Immutable [RenderPassPlanningEntryView] used for planning and tests.
@immutable
class const RenderPassPlanningEntry({
  required final int shader,
  required final int flags,
  required final int layer,
  required final int stencilMode,
  required final Object? pipelineIdentity,
  final Object? depthPipelineIdentity,
  final double fillExtrusionOpacity = 1.0,
}) implements RenderPassPlanningEntryView;

/// One half-open run that can be replayed without changing GPU pass state.
class RenderPassPlan({
  required var RenderPassPlanKind kind,
  required var int start,
  required var int end,
  required var Object? pipelineIdentity,
  required var bool needsDepthStencilAttachment,
  required var bool clearDepth,
  required var bool clearStencil,
  required var bool depthTest,
  required var bool depthWrite,
  required var int stencilMode,
  required var bool cullBackFaces,
  required var bool setPrimitive,
  required var bool needsDepthPrepass,
}) {
  void reset({
    required RenderPassPlanKind kind,
    required int start,
    required int end,
    required Object? pipelineIdentity,
    required bool needsDepthStencilAttachment,
    required bool clearDepth,
    required bool clearStencil,
    required bool depthTest,
    required bool depthWrite,
    required int stencilMode,
    required bool cullBackFaces,
    required bool setPrimitive,
    required bool needsDepthPrepass,
  }) {
    this.kind = kind;
    this.start = start;
    this.end = end;
    this.pipelineIdentity = pipelineIdentity;
    this.needsDepthStencilAttachment = needsDepthStencilAttachment;
    this.clearDepth = clearDepth;
    this.clearStencil = clearStencil;
    this.depthTest = depthTest;
    this.depthWrite = depthWrite;
    this.stencilMode = stencilMode;
    this.cullBackFaces = cullBackFaces;
    this.setPrimitive = setPrimitive;
    this.needsDepthPrepass = needsDepthPrepass;
  }
}

const _depthStencilAttachmentPresent = Object();

/// Plans pass boundaries without touching Flutter GPU objects.
///
/// Equal pipelines separated in the native stream remain separated. Fill
/// extrusions are planned per contiguous layer, with optional depth-only runs
/// before their color runs.
List<RenderPassPlan> planRenderPasses(
  List<RenderPassPlanningEntryView> es, {
  required bool hasDepthStencilAttachment,
  required bool attachmentInitiallyInitialized,
  List<RenderPassPlan>? output,
  List<RenderPassPlan>? pool,
}) {
  final plans = output ?? <RenderPassPlan>[];
  plans.clear();
  var poolCursor = 0;
  void addPlan({
    required RenderPassPlanKind kind,
    required int start,
    required int end,
    required Object? pipelineIdentity,
    required bool needsDepthStencilAttachment,
    required bool clearDepth,
    required bool clearStencil,
    required bool depthTest,
    required bool depthWrite,
    required int stencilMode,
    required bool cullBackFaces,
    required bool setPrimitive,
    required bool needsDepthPrepass,
  }) {
    if (pool == null || poolCursor == pool.length) {
      final plan = RenderPassPlan(
        kind: kind,
        start: start,
        end: end,
        pipelineIdentity: pipelineIdentity,
        needsDepthStencilAttachment: needsDepthStencilAttachment,
        clearDepth: clearDepth,
        clearStencil: clearStencil,
        depthTest: depthTest,
        depthWrite: depthWrite,
        stencilMode: stencilMode,
        cullBackFaces: cullBackFaces,
        setPrimitive: setPrimitive,
        needsDepthPrepass: needsDepthPrepass,
      );
      pool?.add(plan);
      plans.add(plan);
    } else {
      final plan = pool[poolCursor];
      plan.reset(
        kind: kind,
        start: start,
        end: end,
        pipelineIdentity: pipelineIdentity,
        needsDepthStencilAttachment: needsDepthStencilAttachment,
        clearDepth: clearDepth,
        clearStencil: clearStencil,
        depthTest: depthTest,
        depthWrite: depthWrite,
        stencilMode: stencilMode,
        cullBackFaces: cullBackFaces,
        setPrimitive: setPrimitive,
        needsDepthPrepass: needsDepthPrepass,
      );
      plans.add(plan);
    }
    poolCursor++;
  }

  if (es.isEmpty) return plans;
  final mainDepthStencilTexture = hasDepthStencilAttachment
      ? _depthStencilAttachmentPresent
      : null;
  var attachmentInitialized =
      mainDepthStencilTexture != null && attachmentInitiallyInitialized;
  var cursor = 0;
  while (cursor < es.length) {
    final first = es[cursor];
    if (first.stencilMode == StencilModeType.clear) {
      addPlan(
        kind: RenderPassPlanKind.stencilClear,
        start: cursor,
        end: cursor + 1,
        pipelineIdentity: null,
        needsDepthStencilAttachment: true,
        clearDepth: mainDepthStencilTexture != null && !attachmentInitialized,
        clearStencil: mainDepthStencilTexture != null,
        depthTest: false,
        depthWrite: false,
        stencilMode: StencilModeType.clear,
        cullBackFaces: false,
        setPrimitive: false,
        needsDepthPrepass: false,
      );
      if (mainDepthStencilTexture != null) attachmentInitialized = true;
      cursor++;
      continue;
    }

    if (first.shader != ShaderType.fillExtrusion) {
      final pipeline = first.pipelineIdentity;
      if (pipeline == null) {
        throw StateError('Draw entry at $cursor has no pipeline identity');
      }
      final depthTest = drawCommandUsesDepth(first.flags);
      final depthWrite = drawCommandWritesDepth(first.flags);
      final stencilMode = first.stencilMode;
      final needsAttachment =
          depthTest || stencilMode != StencilModeType.disabled;
      var end = cursor + 1;
      while (end < es.length &&
          es[end].stencilMode != StencilModeType.clear &&
          es[end].shader != ShaderType.fillExtrusion &&
          identical(es[end].pipelineIdentity, pipeline) &&
          drawCommandUsesDepth(es[end].flags) == depthTest &&
          drawCommandWritesDepth(es[end].flags) == depthWrite &&
          es[end].stencilMode == stencilMode) {
        end++;
      }
      addPlan(
        kind: RenderPassPlanKind.color,
        start: cursor,
        end: end,
        pipelineIdentity: pipeline,
        needsDepthStencilAttachment: needsAttachment,
        clearDepth:
            needsAttachment &&
            mainDepthStencilTexture != null &&
            !attachmentInitialized,
        clearStencil:
            needsAttachment &&
            mainDepthStencilTexture != null &&
            !attachmentInitialized,
        depthTest: depthTest,
        depthWrite: depthWrite,
        stencilMode: stencilMode,
        cullBackFaces: false,
        setPrimitive: first.shader == ShaderType.fillOutline,
        needsDepthPrepass: false,
      );
      if (needsAttachment && mainDepthStencilTexture != null) {
        attachmentInitialized = true;
      }
      cursor = end;
      continue;
    }

    // Commands from one 3D TileLayerGroup invocation are contiguous in the
    // MapLibre stream. Keep separate layers as separate pass groups.
    var layerEnd = cursor + 1;
    while (layerEnd < es.length &&
        es[layerEnd].shader == ShaderType.fillExtrusion &&
        es[layerEnd].layer == first.layer) {
      layerEnd++;
    }
    final needsDepthPrepass = fillExtrusionNeedsDepthPrepass(
      first.fillExtrusionOpacity,
    );

    if (mainDepthStencilTexture != null && needsDepthPrepass) {
      var depthCursor = cursor;
      while (depthCursor < layerEnd) {
        final depthPipeline = es[depthCursor].depthPipelineIdentity;
        if (depthPipeline == null) {
          throw StateError(
            'Fill-extrusion entry at $depthCursor has no depth pipeline',
          );
        }
        var depthEnd = depthCursor + 1;
        while (depthEnd < layerEnd &&
            identical(es[depthEnd].depthPipelineIdentity, depthPipeline)) {
          depthEnd++;
        }
        addPlan(
          kind: RenderPassPlanKind.fillExtrusionDepth,
          start: depthCursor,
          end: depthEnd,
          pipelineIdentity: depthPipeline,
          needsDepthStencilAttachment: true,
          clearDepth: !attachmentInitialized,
          clearStencil: !attachmentInitialized,
          depthTest: true,
          depthWrite: true,
          stencilMode: StencilModeType.disabled,
          cullBackFaces: true,
          setPrimitive: false,
          needsDepthPrepass: true,
        );
        attachmentInitialized = true;
        depthCursor = depthEnd;
      }
    }

    var colorCursor = cursor;
    while (colorCursor < layerEnd) {
      final colorFirst = es[colorCursor];
      final colorPipeline = colorFirst.pipelineIdentity;
      if (colorPipeline == null) {
        throw StateError(
          'Fill-extrusion entry at $colorCursor has no pipeline',
        );
      }
      final stencilMode = colorFirst.stencilMode;
      var colorEnd = colorCursor + 1;
      while (colorEnd < layerEnd &&
          identical(es[colorEnd].pipelineIdentity, colorPipeline) &&
          es[colorEnd].stencilMode == stencilMode) {
        colorEnd++;
      }
      addPlan(
        kind: RenderPassPlanKind.color,
        start: colorCursor,
        end: colorEnd,
        pipelineIdentity: colorPipeline,
        needsDepthStencilAttachment: true,
        clearDepth: mainDepthStencilTexture != null && !attachmentInitialized,
        clearStencil: mainDepthStencilTexture != null && !attachmentInitialized,
        depthTest: mainDepthStencilTexture != null,
        depthWrite: mainDepthStencilTexture != null && !needsDepthPrepass,
        stencilMode: stencilMode,
        cullBackFaces: true,
        setPrimitive: false,
        needsDepthPrepass: needsDepthPrepass,
      );
      if (mainDepthStencilTexture != null) attachmentInitialized = true;
      colorCursor = colorEnd;
    }
    cursor = layerEnd;
  }
  return plans;
}

/// Returns the boundary immediately after the last fill-extrusion pass.
///
/// A custom geographic 3D pass inserted at this boundary sees the completed
/// building depth buffer, while every later style pass keeps its native order.
/// Styles without fill extrusions insert custom 3D at the end of GPU drawing.
int threeDimensionalRenderInsertionIndex(
  List<RenderPassPlan> plans,
  List<RenderPassPlanningEntryView> entries,
) {
  for (var index = plans.length - 1; index >= 0; index--) {
    final plan = plans[index];
    if (plan.kind != RenderPassPlanKind.stencilClear &&
        entries[plan.start].shader == ShaderType.fillExtrusion) {
      return index + 1;
    }
  }
  return plans.length;
}

import 'package:flutter/foundation.dart';
import 'package:maplibre_flutter_gpu/src/frame/render_pass_plan.dart';

/// Immutable render-pass input for tests that do not allocate GPU resources.
@immutable
class const RenderPassPlanningEntry({
  @override required final int shader,
  @override required final int flags,
  @override required final int layer,
  @override required final int stencilMode,
  @override required final Object? pipelineIdentity,
  @override final Object? depthPipelineIdentity,
  @override final double fillExtrusionOpacity = 1.0,
}) implements RenderPassPlanningEntryView;

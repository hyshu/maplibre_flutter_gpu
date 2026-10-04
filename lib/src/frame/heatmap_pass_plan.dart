import '../native/draw_command.dart';

/// Native target metadata needed to separate density passes from map drawing.
abstract interface class HeatmapPlanningEntryView {
  int get shader;
  int get renderTargetId;
  int get renderTargetWidth;
  int get renderTargetHeight;
}

/// One cleared density target and its half-open range of accumulation draws.
typedef HeatmapPassPlan = ({
  int targetId,
  int width,
  int height,
  int start,
  int end,
});

/// Preserves offscreen pass boundaries, including clears without geometry.
///
/// Density commands must follow their target's clear and share its dimensions.
/// Invalid target references throw a [StateError] before any GPU work is recorded.
List<HeatmapPassPlan> planHeatmapPasses(
  List<HeatmapPlanningEntryView> entries,
) {
  final plans = <HeatmapPassPlan>[];
  final targetIds = <int>{};
  var index = 0;
  while (index < entries.length) {
    final entry = entries[index];
    if (entry.shader == ShaderType.heatmap) {
      throw StateError('Heatmap density draw has no preceding target clear');
    }
    if (entry.shader != ShaderType.renderTarget) {
      index++;
      continue;
    }
    final id = entry.renderTargetId;
    final width = entry.renderTargetWidth;
    final height = entry.renderTargetHeight;
    if (id == 0 || width <= 0 || height <= 0 || !targetIds.add(id)) {
      throw StateError('Invalid or repeated heatmap render target $id');
    }
    final start = ++index;
    while (index < entries.length &&
        entries[index].shader == ShaderType.heatmap) {
      final draw = entries[index];
      if (draw.renderTargetId != id ||
          draw.renderTargetWidth != width ||
          draw.renderTargetHeight != height) {
        throw StateError('Heatmap density draw does not match target $id');
      }
      index++;
    }
    plans.add((
      targetId: id,
      width: width,
      height: height,
      start: start,
      end: index,
    ));
  }
  for (final entry in entries) {
    if (entry.shader == ShaderType.heatmapTexture &&
        !targetIds.contains(entry.renderTargetId)) {
      throw StateError('Heatmap composite has no density target');
    }
  }
  return plans;
}

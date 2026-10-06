import '../native/draw_command.dart';
import 'draw_flags.dart';

/// Native metadata needed to separate offscreen passes from map drawing.
abstract interface class OffscreenPlanningEntryView {
  int get shader;
  int get flags;
  int get renderTargetId;
  int get renderTargetWidth;
  int get renderTargetHeight;
}

/// Determines target precision, blending, and the shaders that may access it.
enum OffscreenPassKind { heatmap, hillshade }

/// One cleared target and its half-open range of preparation draws.
typedef OffscreenPassPlan = ({
  OffscreenPassKind kind,
  int targetId,
  int width,
  int height,
  int start,
  int end,
});

/// Preserves offscreen pass boundaries, including clears without geometry.
///
/// Preparation draws must follow their target's clear and share its dimensions.
/// Invalid dependencies throw a [StateError] before any GPU work is recorded.
List<OffscreenPassPlan> planOffscreenPasses(
  List<OffscreenPlanningEntryView> entries,
) {
  final plans = <OffscreenPassPlan>[];
  final targetKinds = <int, OffscreenPassKind>{};
  var index = 0;
  while (index < entries.length) {
    final entry = entries[index];
    if (_isPreparation(entry.shader)) {
      throw StateError('Offscreen draw has no preceding target clear');
    }
    if (entry.shader != ShaderType.renderTarget) {
      index++;
      continue;
    }
    final id = entry.renderTargetId;
    final width = entry.renderTargetWidth;
    final height = entry.renderTargetHeight;
    final kind = entry.flags & DrawCommandFlags.renderTargetRgba8 != 0
        ? OffscreenPassKind.hillshade
        : OffscreenPassKind.heatmap;
    if (id == 0 || width <= 0 || height <= 0 || targetKinds.containsKey(id)) {
      throw StateError('Invalid or repeated offscreen render target $id');
    }
    targetKinds[id] = kind;
    final shader = kind == .heatmap
        ? ShaderType.heatmap
        : ShaderType.hillshadePrepare;
    final start = ++index;
    while (index < entries.length && _isPreparation(entries[index].shader)) {
      final draw = entries[index];
      if (draw.shader != shader ||
          draw.renderTargetId != id ||
          draw.renderTargetWidth != width ||
          draw.renderTargetHeight != height) {
        throw StateError('Offscreen draw does not match target $id');
      }
      index++;
    }
    plans.add((
      kind: kind,
      targetId: id,
      width: width,
      height: height,
      start: start,
      end: index,
    ));
  }
  for (final entry in entries) {
    final expectedKind = switch (entry.shader) {
      ShaderType.heatmapTexture => OffscreenPassKind.heatmap,
      ShaderType.hillshade => OffscreenPassKind.hillshade,
      _ => null,
    };
    if (expectedKind != null &&
        targetKinds[entry.renderTargetId] != expectedKind) {
      throw StateError('Composite has no matching offscreen target');
    }
  }
  return plans;
}

bool _isPreparation(int shader) =>
    shader == ShaderType.heatmap || shader == ShaderType.hillshadePrepare;

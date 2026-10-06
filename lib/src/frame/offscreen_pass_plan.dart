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
) => OffscreenPassTopology.capture(entries).plan(entries);

/// Offscreen command positions retained while entry shaders and order are stable.
///
/// Target identities and dimensions remain frame-owned and are read by [plan].
final class OffscreenPassTopology {
  const OffscreenPassTopology._(
    this._preparationIndices,
    this.compositeIndices,
  );

  /// Captures only commands that create, draw into, or sample offscreen targets.
  factory OffscreenPassTopology.capture(
    List<OffscreenPlanningEntryView> entries,
  ) {
    List<int>? preparationIndices;
    List<int>? compositeIndices;
    for (var index = 0; index < entries.length; index++) {
      final shader = entries[index].shader;
      if (shader == ShaderType.renderTarget || _isPreparation(shader)) {
        (preparationIndices ??= []).add(index);
      } else if (shader == ShaderType.heatmapTexture ||
          shader == ShaderType.hillshade) {
        (compositeIndices ??= []).add(index);
      }
    }
    if (preparationIndices == null && compositeIndices == null) {
      return const OffscreenPassTopology._([], []);
    }
    return OffscreenPassTopology._(
      preparationIndices ?? const [],
      compositeIndices == null ? const [] : List.unmodifiable(compositeIndices),
    );
  }

  final List<int> _preparationIndices;

  /// Entry positions whose sampled textures must be bound before map drawing.
  final List<int> compositeIndices;

  /// Resolves current targets without visiting ordinary map commands.
  ///
  /// [entries] must retain the captured shaders and order. Invalid dependencies
  /// throw a [StateError]. An empty topology returns without reading entries.
  List<OffscreenPassPlan> plan(List<OffscreenPlanningEntryView> entries) {
    if (_preparationIndices.isEmpty && compositeIndices.isEmpty) {
      return const [];
    }
    final plans = <OffscreenPassPlan>[];
    final targetKinds = <int, OffscreenPassKind>{};
    var cursor = 0;
    while (cursor < _preparationIndices.length) {
      final index = _preparationIndices[cursor++];
      final entry = entries[index];
      if (_isPreparation(entry.shader)) {
        throw StateError('Offscreen draw has no preceding target clear');
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
      final start = index + 1;
      var end = start;
      while (cursor < _preparationIndices.length &&
          _preparationIndices[cursor] == end) {
        final draw = entries[end];
        if (!_isPreparation(draw.shader)) break;
        if (draw.shader != shader ||
            draw.renderTargetId != id ||
            draw.renderTargetWidth != width ||
            draw.renderTargetHeight != height) {
          throw StateError('Offscreen draw does not match target $id');
        }
        cursor++;
        end++;
      }
      plans.add((
        kind: kind,
        targetId: id,
        width: width,
        height: height,
        start: start,
        end: end,
      ));
    }
    for (final index in compositeIndices) {
      final entry = entries[index];
      final expectedKind = entry.shader == ShaderType.heatmapTexture
          ? OffscreenPassKind.heatmap
          : OffscreenPassKind.hillshade;
      if (targetKinds[entry.renderTargetId] != expectedKind) {
        throw StateError('Composite has no matching offscreen target');
      }
    }
    return plans;
  }
}

bool _isPreparation(int shader) =>
    shader == ShaderType.heatmap || shader == ShaderType.hillshadePrepare;

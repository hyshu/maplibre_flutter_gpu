import 'package:flutter/foundation.dart'
    show internal, kDebugMode, kProfileMode;

/// Process-wide counters describing how much symbol work each frame performs.
///
/// The package benchmarks under `e2e/visual/gpu_app` read these to attribute
/// frame time to full overlay rebuilds, position-only relayouts, visual cache
/// misses, and native label synchronization. Counting compiles to nothing in
/// release builds. The class is internal and is not exported by the barrel.
@internal
abstract final class SymbolProfileCounters {
  /// Whether counting is compiled in.
  static const enabled = kProfileMode || kDebugMode;

  /// Map frames that rebuilt every symbol overlay.
  static const fullSymbolUpdates = 'fullSymbolUpdates';

  /// Map frames that only repositioned existing symbol children.
  static const relayoutUpdates = 'relayoutUpdates';

  /// Map frames that changed neither symbol membership nor positions.
  static const noSymbolChangeFrames = 'noSymbolChangeFrames';

  /// Map frames whose native placement snapshot version changed.
  static const labelsChangedFrames = 'labelsChangedFrames';

  /// Calls that rendered a native frame and read its state.
  static const nativeRenderCalls = 'nativeRenderCalls';

  /// Microseconds spent reading and reconciling native placements.
  static const labelSyncMicros = 'labelSyncMicros';

  /// Microseconds spent projecting placements to screen positions.
  static const labelProjectionMicros = 'labelProjectionMicros';

  /// Overlay widget builds.
  static const overlayBuilds = 'overlayBuilds';

  /// Relayout notifications that rebuilt the overlay because a component
  /// crossed the culling boundary.
  static const relayoutSetStates = 'relayoutSetStates';

  /// Relayout notifications handled by render objects alone.
  static const relayoutNotifies = 'relayoutNotifies';

  /// Default text widgets rebuilt because their style data changed.
  static const textVisualMisses = 'textVisualMisses';

  /// Default icon widgets rebuilt because their style data changed.
  static const iconVisualMisses = 'iconVisualMisses';

  /// Visual misses where only an affine transform differed.
  static const transformOnlyMisses = 'transformOnlyMisses';

  /// Symbol batch layouts.
  static const batchLayouts = 'batchLayouts';

  /// Symbol batch paints.
  static const batchPaints = 'batchPaints';

  static final _values = <String, int>{};

  /// Adds [amount] to the counter named [key].
  static void add(String key, [int amount = 1]) {
    if (!enabled) return;
    _values[key] = (_values[key] ?? 0) + amount;
  }

  /// Returns a copy of every counter recorded since the last [reset].
  static Map<String, int> snapshot() =>
      enabled ? Map.unmodifiable(Map.of(_values)) : const {};

  /// Clears every counter.
  static void reset() => _values.clear();
}

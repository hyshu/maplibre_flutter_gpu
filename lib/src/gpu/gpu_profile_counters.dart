import 'package:flutter/foundation.dart'
    show internal, kDebugMode, kProfileMode;

/// Process-wide counters describing how much GPU recording work frames perform.
///
/// The package benchmarks under `e2e/visual/gpu_app` read these to attribute
/// UI-thread frame time to native command preparation, uniform packing, and
/// render pass recording. Counting compiles to nothing in release builds. The
/// class is internal and is not exported by the barrel.
@internal
abstract final class GpuProfileCounters {
  /// Whether counting is compiled in.
  static const enabled = kProfileMode || kDebugMode;

  /// Native frames prepared from exported commands.
  static const gpuFrames = 'gpuFrames';

  /// Prepared frames that reused the previous persistent graph.
  static const gpuGraphReuses = 'gpuGraphReuses';

  /// Exported native commands across prepared frames.
  static const gpuCommands = 'gpuCommands';

  /// Microseconds spent preparing frames, including graph refresh, uniform
  /// packing, and pipeline state.
  static const gpuPrepareMicros = 'gpuPrepareMicros';

  /// Microseconds spent refreshing or rebuilding the persistent graph.
  static const gpuGraphMicros = 'gpuGraphMicros';

  /// Microseconds spent packing uniform buffers.
  static const gpuUboMicros = 'gpuUboMicros';

  /// Compositing strata recorded.
  static const gpuStrata = 'gpuStrata';

  /// Microseconds spent recording render passes for strata.
  static const gpuRecordMicros = 'gpuRecordMicros';

  /// Draw calls recorded across finished frames.
  static const gpuDraws = 'gpuDraws';

  /// Render passes recorded across finished frames.
  static const gpuRenderPasses = 'gpuRenderPasses';

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

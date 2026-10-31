import 'package:flutter/foundation.dart';

/// Opt-in wall-clock timings for GPU command preparation and resource uploads.
///
/// Enable with `--dart-define=MAPLIBRE_GPU_PROFILE=true`. Upload measurements
/// end when the API call returns and do not measure GPU execution or completion.
/// Nested phases overlap and must not be added to their enclosing frame phase.
/// Frame preparation and stratum recording are call timings, not complete
/// Flutter frame timings. A frame can record several strata.
@internal
final gpuCpuProfile = GpuCpuProfile();

/// Collects CPU-side elapsed times without timing work when disabled.
@internal
final class GpuCpuProfile {
  /// Creates a collector with the compile-time profiling flag by default.
  GpuCpuProfile({
    this.enabled = const bool.fromEnvironment('MAPLIBRE_GPU_PROFILE'),
  });

  /// Whether clocks and samples are collected.
  final bool enabled;
  final _samples = <String, List<int>>{};
  final _bytes = <String, int>{};
  Stopwatch? _logClock;

  /// Starts an elapsed-time clock, or returns null when profiling is disabled.
  Stopwatch? start() => enabled ? (Stopwatch()..start()) : null;

  /// Records a completed operation and its optional transfer byte count.
  void finish(String phase, Stopwatch? clock, {int bytes = 0}) {
    if (clock == null) return;
    record(phase, clock.elapsedMicroseconds, bytes: bytes);
  }

  /// Records CPU-side elapsed time in microseconds.
  void record(String phase, int micros, {int bytes = 0}) {
    if (!enabled) return;
    _logClock ??= Stopwatch()..start();
    (_samples[phase] ??= []).add(micros);
    _bytes[phase] = (_bytes[phase] ?? 0) + bytes;
  }

  /// Removes the accumulated samples and returns their interval summaries.
  Map<String, GpuCpuPhaseTiming> takeSnapshotAndReset() {
    final snapshot = <String, GpuCpuPhaseTiming>{};
    for (final entry in _samples.entries) {
      final samples = entry.value..sort();
      snapshot[entry.key] = (
        count: samples.length,
        totalMicros: samples.fold<int>(0, (sum, value) => sum + value),
        p95Micros: samples[(samples.length * 0.95).ceil() - 1],
        maxMicros: samples.last,
        bytes: _bytes[entry.key] ?? 0,
      );
    }
    _samples.clear();
    _bytes.clear();
    _logClock?.reset();

    return snapshot;
  }

  /// Logs one CPU summary per phase after at least one second of frame work.
  void logIfDue() {
    if (!enabled || (_logClock?.elapsedMilliseconds ?? 0) < 1000) return;
    final snapshot = takeSnapshotAndReset();
    for (final entry in snapshot.entries) {
      final timing = entry.value;
      final average = (timing.totalMicros / timing.count).toStringAsFixed(1);
      debugPrint(
        '[GpuCpu] phase=${entry.key} n=${timing.count} '
        'totalUs=${timing.totalMicros} avgUs=$average '
        'p95Us=${timing.p95Micros} maxUs=${timing.maxMicros} '
        'bytes=${timing.bytes}',
      );
    }
  }
}

/// Elapsed-time statistics for one phase, with bytes transferred in its calls.
@internal
typedef GpuCpuPhaseTiming = ({
  int count,
  int totalMicros,
  int p95Micros,
  int maxMicros,
  int bytes,
});

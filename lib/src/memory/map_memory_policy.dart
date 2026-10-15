import '../gpu/resource_cache_policy.dart';

const _mib = 1024 * 1024;
const _gib = 1024 * _mib;

/// Process measurements in bytes. Zero means the measurement is unavailable.
final class MapMemorySnapshot {
  /// Creates a snapshot without estimating missing measurements.
  const MapMemorySnapshot({
    this.physicalBytes = 0,
    this.availableBytes = 0,
    this.usageBytes = 0,
  });

  /// Physical RAM used to select the device tier.
  final int physicalBytes;

  /// Advisory system or process allocation headroom.
  final int availableBytes;

  /// Total process footprint on Apple platforms or RSS elsewhere.
  final int usageBytes;
}

/// Cache targets and process guardrails for one map.
///
/// Visible resources may exceed cache targets. The process limit is a soft
/// trigger for reclamation, not a guarantee that allocations cannot exceed it.
final class MapMemoryBudget {
  /// Creates retention targets and process-wide pressure thresholds.
  const MapMemoryBudget({
    required this.gpu,
    required this.customizerBytes,
    required this.nativeTileCount,
    required this.processLimitBytes,
    required this.reserveBytes,
  });

  /// Renderer buffer, texture, and upload page retention limits.
  final GpuResourceCacheBudget gpu;

  /// Target retained bytes for copied and customized building geometry.
  final int customizerBytes;

  /// Maximum unused native tiles per source, independent of visible tiles.
  final int nativeTileCount;

  /// Process usage that triggers the strongest cache reduction, in bytes.
  final int processLimitBytes;

  /// Available memory below which caches shrink, in bytes.
  final int reserveBytes;

  /// Selects conservative defaults when device memory cannot be measured.
  factory MapMemoryBudget.forDevice({
    required int physicalBytes,
    required bool mobile,
  }) {
    final tier = physicalBytes <= 0 || physicalBytes <= 3 * _gib
        ? 0
        : physicalBytes <= 6 * _gib
        ? 1
        : mobile
        ? 2
        : 3;
    final regular = [16, 24, 32, 64][tier] * _mib;
    final extrusion = [32, 48, 64, 96][tier] * _mib;

    return MapMemoryBudget(
      gpu: GpuResourceCacheBudget(
        regularMinBytes: regular,
        regularMaxBytes: regular,
        fillExtrusionMinBytes: extrusion,
        fillExtrusionMaxBytes: extrusion,
        textureBytes: [16, 24, 32, 48][tier] * _mib,
        poolBytes: [48, 72, 96, 128][tier] * _mib,
      ),
      customizerBytes: [16, 32, 48, 64][tier] * _mib,
      nativeTileCount: [4, 8, 12, 24][tier],
      processLimitBytes: [384, 640, 896, 1536][tier] * _mib,
      reserveBytes: [96, 128, 192, 256][tier] * _mib,
    );
  }

  MapMemoryBudget _atLevel(int level) {
    if (level == 0) return this;
    final divisor = level == 1 ? 2 : 4;

    return MapMemoryBudget(
      gpu: GpuResourceCacheBudget(
        regularMinBytes: gpu.regularMinBytes ~/ divisor,
        regularMaxBytes: gpu.regularMaxBytes ~/ divisor,
        fillExtrusionMinBytes: gpu.fillExtrusionMinBytes ~/ divisor,
        fillExtrusionMaxBytes: gpu.fillExtrusionMaxBytes ~/ divisor,
        textureBytes: gpu.textureBytes ~/ divisor,
        poolBytes: gpu.poolBytes ~/ divisor,
      ),
      customizerBytes: customizerBytes ~/ divisor,
      nativeTileCount: level == 2 ? 0 : nativeTileCount ~/ 2,
      processLimitBytes: processLimitBytes,
      reserveBytes: reserveBytes,
    );
  }
}

/// A change to retention limits and whether existing caches must be reclaimed.
typedef MapMemoryDecision = ({MapMemoryBudget budget, bool changed, bool trim});

/// Shrinks immediately and restores cache capacity only after sustained relief.
final class MapMemoryPolicy {
  /// Starts at normal capacity using [base] as the recovery ceiling.
  MapMemoryPolicy(this.base);

  /// Device-specific targets before pressure reductions.
  final MapMemoryBudget base;
  var _level = 0;
  Duration _lastPressure = Duration.zero;
  Duration? _healthySince;

  /// Current targets after pressure and recovery adjustments.
  MapMemoryBudget get budget => base._atLevel(_level);

  /// [elapsed] must come from a monotonic clock.
  MapMemoryDecision evaluate(
    MapMemorySnapshot snapshot, {
    required Duration elapsed,
    bool warning = false,
  }) {
    final available = snapshot.availableBytes;
    final usage = snapshot.usageBytes;
    final critical =
        warning ||
        (available > 0 && available < base.reserveBytes ~/ 2) ||
        usage >= base.processLimitBytes;
    final constrained =
        (available > 0 && available < base.reserveBytes) ||
        usage >= base.processLimitBytes * 85 ~/ 100;
    final target = critical
        ? 2
        : constrained
        ? 1
        : 0;
    final previous = _level;
    if (target > 0) {
      _lastPressure = elapsed;
      _healthySince = null;
      if (target > _level) _level = target;
    } else {
      final measured = available > 0 || usage > 0;
      final healthy =
          measured &&
          (available == 0 || available >= base.reserveBytes * 2) &&
          (usage == 0 || usage < base.processLimitBytes * 70 ~/ 100);
      if (!healthy) {
        _healthySince = null;
      } else {
        _healthySince ??= elapsed;
        if (_level > 0 &&
            elapsed - _lastPressure >= const Duration(seconds: 60) &&
            elapsed - _healthySince! >= const Duration(seconds: 30)) {
          _level--;
          _lastPressure = elapsed;
          _healthySince = elapsed;
        }
      }
    }

    return (
      budget: budget,
      changed: previous != _level,
      trim: warning || _level > previous,
    );
  }
}

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
  ///
  /// Geometry budgets grow from their floor toward a ceiling only while a
  /// scene keeps that much geometry visible, so a dense city view is not
  /// evicted and uploaded again on every zoom change. A zoom 14 view of a
  /// dense city holds about 30 MB of line and fill geometry and up to 60 MB
  /// of buildings. Memory pressure halves or quarters every value.
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

    return MapMemoryBudget(
      gpu: GpuResourceCacheBudget(
        regularMinBytes: [16, 24, 32, 64][tier] * _mib,
        regularMaxBytes: [32, 48, 64, 96][tier] * _mib,
        fillExtrusionMinBytes: [32, 48, 64, 96][tier] * _mib,
        fillExtrusionMaxBytes: [64, 96, 96, 96][tier] * _mib,
        textureBytes: [16, 24, 32, 48][tier] * _mib,
        poolBytes: [64, 96, 128, 128][tier] * _mib,
      ),
      customizerBytes: [16, 32, 48, 64][tier] * _mib,
      nativeTileCount: [8, 12, 16, 24][tier],
      processLimitBytes: _processLimitBytes(physicalBytes, tier),
      reserveBytes: [96, 128, 192, 256][tier] * _mib,
    );
  }

  /// Process usage that marks the strongest reduction.
  ///
  /// Resident size counts engine, driver, and code pages that no cache limit
  /// can shrink, so the limit follows device memory rather than the cache
  /// tiers. A fixed tier value on a phone left the policy at its strongest
  /// level after one system warning, with nothing retained between zooms,
  /// because usage could never fall back under the recovery threshold. The
  /// tier values remain the floor for unmeasured devices.
  static int _processLimitBytes(int physicalBytes, int tier) {
    final floor = [384, 640, 896, 1536][tier] * _mib;
    final share = physicalBytes * 2 ~/ 5;
    if (share < floor) return floor;
    if (share > 2 * _gib) return 2 * _gib;

    return share;
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

  /// Retention reduction, with zero for normal, one for half, and two for quarter.
  int get pressureLevel => _level;

  /// [elapsed] must come from a monotonic clock.
  MapMemoryDecision evaluate(
    MapMemorySnapshot snapshot, {
    required Duration elapsed,
    bool warning = false,
  }) {
    final available = snapshot.availableBytes;
    final usage = snapshot.usageBytes;
    // A platform warning releases caches now and halves retention after
    // that. Quartering is reserved for measured exhaustion, because a phone
    // that warns once while loading would otherwise keep nothing between
    // zoom levels for a minute or more.
    final critical =
        (available > 0 && available < base.reserveBytes ~/ 2) ||
        usage >= base.processLimitBytes;
    final constrained =
        warning ||
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

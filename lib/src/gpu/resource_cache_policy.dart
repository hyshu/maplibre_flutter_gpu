import '../native/draw_command.dart';

/// Resource categories used by retention policy and eviction diagnostics.
enum GpuCacheClass { line, fillExtrusion, other, indexBuffer, texture }

/// The lifetime condition that made a cached resource eligible for removal.
enum GpuCacheExpiryReason { superseded, unused }

/// Returns the retention category of geometry using [shader].
GpuCacheClass gpuCacheClassForShader(int shader) => switch (shader) {
  ShaderType.line ||
  ShaderType.lineSDF ||
  ShaderType.lineGradient ||
  ShaderType.linePattern => .line,
  ShaderType.fillExtrusion => .fillExtrusion,
  _ => .other,
};

/// Frame and byte limits shared by resource retention and budget enforcement.
abstract final class GpuCachePolicy {
  /// Submitted frame generations retained before resource reuse.
  static const framesInFlight = 4;

  /// Idle frame limit for textures and unclassified resources.
  static const unusedRetentionFrames = 60;

  /// Idle frame limit for regular cached geometry.
  static const regularBufferUnusedRetentionFrames = 1800;

  /// Idle frame limit for cached line geometry.
  static const lineUnusedRetentionFrames = 1800;

  /// Idle frame limit for cached fill extrusion geometry.
  static const fillExtrusionUnusedRetentionFrames = 1800;

  /// Minimum budget for regular vertex and index buffers.
  static const regularMinBufferCacheBudgetBytes = 64 * 1024 * 1024;

  /// Maximum budget for regular vertex and index buffers.
  static const regularMaxBufferCacheBudgetBytes = 96 * 1024 * 1024;

  /// Allocation step used when growing the regular buffer budget.
  static const regularBudgetGrowthStepBytes = 8 * 1024 * 1024;

  /// Recent frame window used to measure regular geometry activity.
  static const regularBudgetWorkingSetFrames = 8;

  /// Idle frame window before the regular buffer budget may shrink.
  static const regularBudgetIdleShrinkFrames = 1800;

  /// Minimum budget for fill extrusion buffers.
  static const fillExtrusionMinBufferCacheBudgetBytes = 64 * 1024 * 1024;

  /// Maximum budget for fill extrusion buffers.
  static const fillExtrusionMaxBufferCacheBudgetBytes = 96 * 1024 * 1024;

  /// Recent frame window used to measure fill extrusion activity.
  static const fillExtrusionBudgetWorkingSetFrames = 8;

  /// Idle frame window before the fill extrusion budget may shrink.
  static const fillExtrusionBudgetIdleShrinkFrames = 120;

  /// Maximum retained source pixel bytes.
  static const textureCacheBudgetBytes = 64 * 1024 * 1024;

  /// Frame interval between eviction diagnostics.
  static const evictionClassLogFrames = 60;
}

/// Whether expiry maintenance is due on [frame].
bool gpuCacheExpiryMaintenanceDue(
  int frame, {
  int interval = GpuCachePolicy.framesInFlight,
}) => frame % interval == 0;

/// Classifies why a cache entry is eligible for expiry on [frame].
///
/// Superseded generations take precedence over age when both rules match, so
/// diagnostics attribute four-frame generation retirement consistently.
GpuCacheExpiryReason? gpuCacheEntryExpiryReason({
  required int frame,
  required int lastUsed,
  required bool superseded,
  int unusedRetentionFrames = GpuCachePolicy.unusedRetentionFrames,
}) {
  final age = frame - lastUsed;
  if (superseded && age >= GpuCachePolicy.framesInFlight) return .superseded;
  if (age >= unusedRetentionFrames) return .unused;

  return null;
}

/// Whether a cache entry can be removed on [frame].
///
/// Superseded entries expire after in-flight frames have finished. Other
/// entries expire after [unusedRetentionFrames] without use.
bool gpuCacheEntryExpired({
  required int frame,
  required int lastUsed,
  required bool superseded,
  int unusedRetentionFrames = GpuCachePolicy.unusedRetentionFrames,
}) =>
    gpuCacheEntryExpiryReason(
      frame: frame,
      lastUsed: lastUsed,
      superseded: superseded,
      unusedRetentionFrames: unusedRetentionFrames,
    ) !=
    null;

/// Retention used for one cached vertex buffer when it is not superseded.
///
/// Cached geometry gets a thirty-second reuse window. The adaptive regular and
/// fill-extrusion byte budgets remain authoritative, so active memory pressure
/// can still evict old entries before this time limit is reached.
int gpuVertexUnusedRetentionFrames(int shader, {bool isFillExtrusion = false}) {
  if (isFillExtrusion || shader == ShaderType.fillExtrusion) {
    return GpuCachePolicy.fillExtrusionUnusedRetentionFrames;
  }
  if (gpuCacheClassForShader(shader) == .line) {
    return GpuCachePolicy.lineUnusedRetentionFrames;
  }
  return GpuCachePolicy.regularBufferUnusedRetentionFrames;
}

/// Retention used for one cached index buffer when it is not superseded.
int gpuIndexUnusedRetentionFrames({bool isFillExtrusion = false}) =>
    isFillExtrusion
    ? GpuCachePolicy.fillExtrusionUnusedRetentionFrames
    : GpuCachePolicy.regularBufferUnusedRetentionFrames;

/// Chooses the pressure-driven regular buffer budget for [residentBytes].
///
/// Retained geometry grows the budget from 64 MiB in 8 MiB steps, up to
/// 96 MiB, before eviction removes reusable line, fill, and index buffers.
int gpuRegularBufferBudgetForResidentBytes(
  int residentBytes, {
  int minBytes = GpuCachePolicy.regularMinBufferCacheBudgetBytes,
  int maxBytes = GpuCachePolicy.regularMaxBufferCacheBudgetBytes,
  int growthStepBytes = GpuCachePolicy.regularBudgetGrowthStepBytes,
}) {
  if (residentBytes < 0) {
    throw RangeError.value(
      residentBytes,
      'residentBytes',
      'must not be negative',
    );
  }
  if (minBytes < 0 || maxBytes < minBytes || growthStepBytes <= 0) {
    throw ArgumentError('Invalid regular buffer cache budget bounds');
  }
  if (residentBytes <= minBytes) return minBytes;
  if (residentBytes >= maxBytes) return maxBytes;
  final rounded =
      ((residentBytes + growthStepBytes - 1) ~/ growthStepBytes) *
      growthStepBytes;
  if (rounded < minBytes) return minBytes;
  if (rounded > maxBytes) return maxBytes;

  return rounded;
}

/// Chooses the fill-extrusion buffer budget from its recently visible working
/// set. Two working sets worth of space keeps adjacent zoom-level tiles warm
/// while panning or zooming. The clamp bounds memory use on unusually dense
/// scenes.
int gpuFillExtrusionBudgetForWorkingSetBytes(
  int recentWorkingSetBytes, {
  int minBytes = GpuCachePolicy.fillExtrusionMinBufferCacheBudgetBytes,
  int maxBytes = GpuCachePolicy.fillExtrusionMaxBufferCacheBudgetBytes,
}) {
  if (recentWorkingSetBytes < 0) {
    throw RangeError.value(
      recentWorkingSetBytes,
      'recentWorkingSetBytes',
      'must not be negative',
    );
  }
  if (minBytes < 0 || maxBytes < minBytes) {
    throw ArgumentError('Invalid fill-extrusion cache budget bounds');
  }
  final targetBytes = recentWorkingSetBytes * 2;
  if (targetBytes < minBytes) return minBytes;
  if (targetBytes > maxBytes) return maxBytes;

  return targetBytes;
}

/// Applies hysteresis to the fill-extrusion budget.
///
/// The budget grows immediately when the visible working set needs more room,
/// but does not shrink while fill-extrusion geometry is still active. After a
/// sustained period without recent fill-extrusion use it may fall back to the
/// target budget, normally the 64 MiB floor.
int gpuFillExtrusionBudgetWithHysteresis({
  required int currentBudgetBytes,
  required int targetBudgetBytes,
  required bool hasRecentWorkingSet,
  required int framesSinceRecentUse,
  int idleShrinkFrames = GpuCachePolicy.fillExtrusionBudgetIdleShrinkFrames,
}) {
  if (currentBudgetBytes < 0 ||
      targetBudgetBytes < 0 ||
      framesSinceRecentUse < 0 ||
      idleShrinkFrames < 0) {
    throw ArgumentError('Fill-extrusion budget inputs must be non-negative');
  }
  if (targetBudgetBytes > currentBudgetBytes) return targetBudgetBytes;
  if (hasRecentWorkingSet || framesSinceRecentUse < idleShrinkFrames) {
    return currentBudgetBytes;
  }
  return targetBudgetBytes;
}

/// Selects entries to remove until the remaining size does not exceed
/// [maxBytes].
///
/// Entries used in [currentFrame] are never selected. Older entries take
/// priority, followed by larger entries when their last-use frames match.
List<K> gpuCacheBudgetVictims<K>(
  Map<K, ({int lastUsed, int bytes})> entries, {
  required int currentFrame,
  required int maxBytes,
}) {
  var totalBytes = entries.values.fold<int>(
    0,
    (total, entry) => total + entry.bytes,
  );
  if (totalBytes <= maxBytes) return [];

  final candidates =
      entries.entries
          .where((entry) => entry.value.lastUsed < currentFrame)
          .toList(growable: false)
        ..sort((a, b) {
          final ageOrder = a.value.lastUsed.compareTo(b.value.lastUsed);
          if (ageOrder != 0) return ageOrder;

          return b.value.bytes.compareTo(a.value.bytes);
        });
  final victims = <K>[];
  for (final candidate in candidates) {
    if (totalBytes <= maxBytes) break;
    victims.add(candidate.key);
    totalBytes -= candidate.value.bytes;
  }
  return victims;
}

/// Whether budget enforcement must run again after protected entries age.
bool gpuCacheBudgetNeedsRetry({
  required int residentBytes,
  required int maxBytes,
}) => residentBytes > maxBytes;

/// Removes expired versions from [cache].
///
/// For each resource ID, the most recently used version is treated as current.
void evictExpiredCacheVersions<K, V>(
  Map<K, V> cache, {
  required int frame,
  required int Function(K key) idOf,
  required int Function(K key) versionOf,
  required int Function(V value) lastUsedOf,
  int Function(V value)? unusedRetentionFramesOf,
  int Function(K key, V value)? unusedRetentionFramesForEntry,
  void Function(K key, V value)? onEvict,
  void Function(K key, V value, GpuCacheExpiryReason reason)? onEvictReason,
}) {
  final latestVersion = <int, int>{};
  final latestUse = <int, int>{};
  for (final entry in cache.entries) {
    final id = idOf(entry.key);
    final used = lastUsedOf(entry.value);
    if (used >= (latestUse[id] ?? -1)) {
      latestUse[id] = used;
      latestVersion[id] = versionOf(entry.key);
    }
  }
  cache.removeWhere((key, value) {
    final reason = gpuCacheEntryExpiryReason(
      frame: frame,
      lastUsed: lastUsedOf(value),
      superseded: versionOf(key) != latestVersion[idOf(key)],
      unusedRetentionFrames:
          unusedRetentionFramesForEntry?.call(key, value) ??
          unusedRetentionFramesOf?.call(value) ??
          GpuCachePolicy.unusedRetentionFrames,
    );
    if (reason == null) return false;
    onEvict?.call(key, value);
    onEvictReason?.call(key, value, reason);

    return true;
  });
}

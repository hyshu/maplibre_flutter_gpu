import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';

void main() {
  test('expiry eviction callback reports removed keys and values', () {
    final cache = <({int id, int version}), ({int lastUsed, int bytes})>{
      (id: 1, version: 1): (lastUsed: 1, bytes: 100),
      (id: 1, version: 2): (lastUsed: 10, bytes: 200),
    };
    var evictedBytes = 0;
    ({int id, int version})? evictedKey;

    evictExpiredCacheVersions(
      cache,
      frame: 10,
      idOf: (key) => key.id,
      versionOf: (key) => key.version,
      lastUsedOf: (value) => value.lastUsed,
      unusedRetentionFramesOf: (_) => 100,
      onEvict: (key, value) {
        evictedKey = key;
        evictedBytes += value.bytes;
      },
    );

    expect(cache.keys, contains((id: 1, version: 2)));
    expect(cache.keys, isNot(contains((id: 1, version: 1))));
    expect(evictedKey, (id: 1, version: 1));
    expect(evictedBytes, 100);
  });

  test('entry-specific retention can use cache key metadata', () {
    final cache = <({int id, int version, bool longLived}), ({int lastUsed})>{
      (id: 1, version: 1, longLived: true): (lastUsed: 0),
      (id: 2, version: 1, longLived: false): (lastUsed: 0),
    };

    evictExpiredCacheVersions(
      cache,
      frame: 70,
      idOf: (key) => key.id,
      versionOf: (key) => key.version,
      lastUsedOf: (value) => value.lastUsed,
      unusedRetentionFramesForEntry: (key, _) => key.longLived ? 120 : 60,
    );

    expect(cache.keys, contains((id: 1, version: 1, longLived: true)));
    expect(cache.keys, isNot(contains((id: 2, version: 1, longLived: false))));
  });

  test('fill extrusion cache budget follows the recent working set', () {
    const mib = 1024 * 1024;

    expect(gpuFillExtrusionBudgetForWorkingSetBytes(0), 64 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(32 * mib), 64 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(40 * mib), 80 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(64 * mib), 128 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(96 * mib), 192 * mib);
    expect(gpuFillExtrusionBudgetForWorkingSetBytes(128 * mib), 192 * mib);
  });

  test('fill extrusion budget grows immediately but shrinks only after idle', () {
    const mib = 1024 * 1024;

    expect(
      gpuFillExtrusionBudgetWithHysteresis(
        currentBudgetBytes: 64 * mib,
        targetBudgetBytes: 112 * mib,
        hasRecentWorkingSet: true,
        framesSinceRecentUse: 0,
      ),
      112 * mib,
    );
    expect(
      gpuFillExtrusionBudgetWithHysteresis(
        currentBudgetBytes: 112 * mib,
        targetBudgetBytes: 64 * mib,
        hasRecentWorkingSet: true,
        framesSinceRecentUse: 0,
      ),
      112 * mib,
    );
    expect(
      gpuFillExtrusionBudgetWithHysteresis(
        currentBudgetBytes: 112 * mib,
        targetBudgetBytes: 64 * mib,
        hasRecentWorkingSet: false,
        framesSinceRecentUse: 119,
        idleShrinkFrames: 120,
      ),
      112 * mib,
    );
    expect(
      gpuFillExtrusionBudgetWithHysteresis(
        currentBudgetBytes: 112 * mib,
        targetBudgetBytes: 64 * mib,
        hasRecentWorkingSet: false,
        framesSinceRecentUse: 120,
        idleShrinkFrames: 120,
      ),
      64 * mib,
    );
  });

  test('fill extrusion cache budget rejects invalid inputs and bounds', () {
    expect(
      () => gpuFillExtrusionBudgetForWorkingSetBytes(-1),
      throwsRangeError,
    );
    expect(
      () => gpuFillExtrusionBudgetForWorkingSetBytes(
        1,
        minBytes: 100,
        maxBytes: 99,
      ),
      throwsArgumentError,
    );
    expect(
      () => gpuFillExtrusionBudgetWithHysteresis(
        currentBudgetBytes: -1,
        targetBudgetBytes: 0,
        hasRecentWorkingSet: false,
        framesSinceRecentUse: 0,
      ),
      throwsArgumentError,
    );
  });
}

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
}

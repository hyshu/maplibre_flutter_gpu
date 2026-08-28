import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_miss_tracker.dart';

typedef _TestKey = ({int id, int version, int identity});

void main() {
  GpuCacheMissTracker<_TestKey> tracker({int historyLimit = 8}) => .new(
    idOf: (key) => key.id,
    versionOf: (key) => key.version,
    historyLimit: historyLimit,
  );

  GpuCacheMissSnapshot only(GpuCacheMissTracker<_TestKey> value) {
    final snapshot = value.takeSnapshotAndReset();
    expect(snapshot, hasLength(1));
    return snapshot.single;
  }

  void missAndStore(
    GpuCacheMissTracker<_TestKey> value,
    _TestKey key, {
    int bytes = 1024,
    bool classify = true,
  }) {
    value.recordLookup(key: key, hit: false);
    value.recordStore(key: key, bytes: bytes, classify: classify);
  }

  test('first observed resource is classified as new', () {
    final value = tracker();
    const key = (id: 7, version: 1, identity: 100);

    missAndStore(value, key, bytes: 4096);
    final snapshot = only(value);

    expect(snapshot.reason, GpuCacheMissReason.newBuffer);
    expect(snapshot.count, 1);
    expect(snapshot.bytes, 4096);
  });

  test('same id with a new version is classified as version churn', () {
    final value = tracker();

    missAndStore(value, (id: 7, version: 1, identity: 100));
    value.takeSnapshotAndReset();
    missAndStore(value, (id: 7, version: 2, identity: 200), bytes: 2048);

    final snapshot = only(value);
    expect(snapshot.reason, GpuCacheMissReason.versionChange);
    expect(snapshot.bytes, 2048);
  });

  test('same id/version with another exact key is identity churn', () {
    final value = tracker();

    missAndStore(value, (id: 7, version: 1, identity: 100));
    value.takeSnapshotAndReset();
    missAndStore(value, (id: 7, version: 1, identity: 200));

    expect(only(value).reason, GpuCacheMissReason.identityChange);
  });

  test('identity churn logs bounded previous and current key samples', () {
    final value = tracker();
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    try {
      missAndStore(value, (id: 7, version: 1, identity: 100));
      value.takeSnapshotAndReset();
      for (var identity = 200; identity < 205; identity += 1) {
        missAndStore(value, (id: 7, version: 1, identity: identity));
      }

      expect(messages, hasLength(4));
      expect(messages.first, contains('[GpuIdentityChange] id=7 version=1'));
      expect(messages.first, contains('identity: 100'));
      expect(messages.first, contains('identity: 200'));
    } finally {
      debugPrint = originalDebugPrint;
    }
  });

  test('identity sample limit resets with interval metrics', () {
    final value = tracker();
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    try {
      missAndStore(value, (id: 7, version: 1, identity: 100));
      value.takeSnapshotAndReset();
      for (var identity = 200; identity < 205; identity += 1) {
        missAndStore(value, (id: 7, version: 1, identity: identity));
      }
      expect(messages, hasLength(4));

      value.takeSnapshotAndReset();
      missAndStore(value, (id: 7, version: 1, identity: 300));
      expect(messages, hasLength(5));
    } finally {
      debugPrint = originalDebugPrint;
    }
  });

  test('exact expiry revisit outranks version and identity history', () {
    final value = tracker();
    const key = (id: 7, version: 1, identity: 100);

    missAndStore(value, key);
    value.takeSnapshotAndReset();
    value.recordEviction(key: key, kind: .expiry);
    missAndStore(value, key, bytes: 8192);

    final snapshot = only(value);
    expect(snapshot.reason, GpuCacheMissReason.expiryRevisit);
    expect(snapshot.bytes, 8192);
  });

  test('exact budget revisit is classified separately', () {
    final value = tracker();
    const key = (id: 7, version: 1, identity: 100);

    missAndStore(value, key);
    value.takeSnapshotAndReset();
    value.recordEviction(key: key, kind: .budget);
    missAndStore(value, key);

    expect(only(value).reason, GpuCacheMissReason.budgetRevisit);
  });

  test('non-target stores clear pending misses without affecting history', () {
    final value = tracker();
    const ignored = (id: 7, version: 1, identity: 100);

    missAndStore(value, ignored, classify: false);
    expect(value.takeSnapshotAndReset(), isEmpty);

    missAndStore(value, (id: 7, version: 2, identity: 200));
    expect(only(value).reason, GpuCacheMissReason.newBuffer);
  });

  test('interval reset preserves history for later classification', () {
    final value = tracker();

    missAndStore(value, (id: 7, version: 1, identity: 100));
    value.takeSnapshotAndReset();
    expect(value.takeSnapshotAndReset(), isEmpty);

    missAndStore(value, (id: 7, version: 2, identity: 200));
    expect(only(value).reason, GpuCacheMissReason.versionChange);
  });

  test('hits establish identity history without creating miss totals', () {
    final value = tracker();
    const key = (id: 7, version: 3, identity: 100);

    value.recordLookup(key: key, hit: true);
    expect(value.takeSnapshotAndReset(), isEmpty);

    missAndStore(value, (id: 7, version: 3, identity: 200));
    expect(only(value).reason, GpuCacheMissReason.identityChange);
  });

  test('history is bounded and constructor rejects invalid limit', () {
    expect(() => tracker(historyLimit: 0), throwsRangeError);

    final value = tracker(historyLimit: 2);
    missAndStore(value, (id: 1, version: 1, identity: 1));
    missAndStore(value, (id: 2, version: 1, identity: 2));
    missAndStore(value, (id: 3, version: 1, identity: 3));
    value.takeSnapshotAndReset();

    // ID 1 fell out of the bounded history, so seeing it again is intentionally
    // treated as new rather than keeping unbounded diagnostic state.
    missAndStore(value, (id: 1, version: 2, identity: 4));
    expect(only(value).reason, GpuCacheMissReason.newBuffer);
  });

  test('pending upload failures retain only bounded recent misses', () {
    final value = tracker(historyLimit: 2);
    const first = (id: 1, version: 1, identity: 1);
    const second = (id: 2, version: 1, identity: 2);
    const third = (id: 3, version: 1, identity: 3);

    value
      ..recordLookup(key: first, hit: false)
      ..recordLookup(key: second, hit: false)
      ..recordLookup(key: third, hit: false)
      ..recordStore(key: first, bytes: 1, classify: true)
      ..recordStore(key: second, bytes: 2, classify: true)
      ..recordStore(key: third, bytes: 3, classify: true);

    final snapshot = only(value);
    expect(snapshot.reason, GpuCacheMissReason.newBuffer);
    expect(snapshot.count, 2);
    expect(snapshot.bytes, 5);
  });
}

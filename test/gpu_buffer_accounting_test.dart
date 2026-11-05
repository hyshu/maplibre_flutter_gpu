import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/buffer_accounting.dart';

const _enabled = bool.fromEnvironment('MAPLIBRE_GPU_BUFFER_ACCOUNTING');

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('accounting requires both Android and the compile-time opt-in', () {
    final accounting = GpuBufferAccounting();
    final buffer = Object();
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        gpuBufferAccountingEnabled,
        platform == TargetPlatform.android && _enabled,
      );
      if (platform != TargetPlatform.android) {
        expect(accounting.track(buffer, 4096), isFalse);
      }
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(accounting.track(buffer, 4096), _enabled);
    expect(accounting.track(buffer, 4096), isFalse);
  });

  test('disabled accounting does not validate or attach capacities', () {
    final accounting = GpuBufferAccounting();
    final buffer = Object();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(accounting.track(buffer, -1), isFalse);
    expect(accounting.track(buffer, 0), isFalse);
    expect(accounting.track(buffer, 4096), isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(accounting.track(buffer, 8192), _enabled);
    if (!_enabled) expect(accounting.track(buffer, -1), isFalse);
  });

  test('shared consumers account the full buffer only once', () {
    final accounting = GpuBufferAccounting();
    final buffer = Object();
    final cache = [buffer];
    final retainedFrame = [buffer];
    expect(accounting.track(cache.single, 4096), _enabled);
    expect(accounting.track(retainedFrame.single, 4096), isFalse);
    cache.clear();
    expect(accounting.track(retainedFrame.single, 4096), isFalse);
  });

  test('equal buffer keys still have independent identities', () {
    final accounting = GpuBufferAccounting();
    final first = _EqualBufferIdentity();
    final second = _EqualBufferIdentity();
    expect(first, second);
    expect(identical(first, second), isFalse);
    expect(accounting.track(first, 1024), _enabled);
    expect(accounting.track(second, 2048), _enabled);
    expect(accounting.track(first, 1024), isFalse);
    expect(accounting.track(second, 2048), isFalse);
  });

  test('zero capacity leaves no accounting attachment', () {
    final accounting = GpuBufferAccounting();
    final buffer = Object();
    expect(accounting.track(buffer, 0), isFalse);
    expect(accounting.track(buffer, 64), _enabled);
    expect(accounting.track(buffer, 64), isFalse);
  });

  test('invalid sizes leave the previous accounting intact', () {
    final accounting = GpuBufferAccounting();
    final buffer = Object();
    expect(() => accounting.track(buffer, -1), throwsRangeError);
    expect(accounting.track(buffer, 4096), isTrue);
    expect(() => accounting.track(buffer, 8192), throwsArgumentError);
    expect(() => accounting.track(buffer, 0), throwsArgumentError);
    expect(accounting.track(buffer, 4096), isFalse);
  }, skip: !_enabled);
}

final class _EqualBufferIdentity {
  @override
  bool operator ==(Object other) => other is _EqualBufferIdentity;

  @override
  int get hashCode => 1;
}

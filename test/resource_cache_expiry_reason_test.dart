import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';

void main() {
  test(
    'expiry reason distinguishes superseded generations from unused age',
    () {
      expect(
        gpuCacheEntryExpiryReason(
          frame: 13,
          lastUsed: 10,
          superseded: true,
          unusedRetentionFrames: 600,
        ),
        isNull,
      );
      expect(
        gpuCacheEntryExpiryReason(
          frame: 14,
          lastUsed: 10,
          superseded: true,
          unusedRetentionFrames: 600,
        ),
        GpuCacheExpiryReason.superseded,
      );
      expect(
        gpuCacheEntryExpiryReason(
          frame: 610,
          lastUsed: 10,
          superseded: false,
          unusedRetentionFrames: 600,
        ),
        GpuCacheExpiryReason.unused,
      );
    },
  );

  test('superseded reason wins when both expiry rules match', () {
    expect(
      gpuCacheEntryExpiryReason(
        frame: 700,
        lastUsed: 10,
        superseded: true,
        unusedRetentionFrames: 600,
      ),
      GpuCacheExpiryReason.superseded,
    );
  });
}

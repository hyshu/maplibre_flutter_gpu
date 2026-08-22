import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/persistent_buffer_pool.dart';

void main() {
  test('persistent buffer pool eligibility is capped at 256 KiB', () {
    expect(gpuPersistentBufferPoolEligible(0), isFalse);
    expect(gpuPersistentBufferPoolEligible(1), isTrue);
    expect(gpuPersistentBufferPoolEligible(256 * 1024), isTrue);
    expect(gpuPersistentBufferPoolEligible(256 * 1024 + 1), isFalse);
  });

  test('persistent buffer pool reserves 16-byte aligned ranges', () {
    expect(gpuPersistentBufferPoolReservedBytes(0), 0);
    expect(gpuPersistentBufferPoolReservedBytes(1), 16);
    expect(gpuPersistentBufferPoolReservedBytes(16), 16);
    expect(gpuPersistentBufferPoolReservedBytes(17), 32);
    expect(gpuPersistentBufferPoolReservedBytes(256 * 1024), 256 * 1024);
  });

  test('persistent buffer pool helpers reject invalid inputs', () {
    expect(() => gpuPersistentBufferPoolEligible(-1), throwsRangeError);
    expect(
      () => gpuPersistentBufferPoolEligible(1, maxAllocationBytes: 0),
      throwsArgumentError,
    );
    expect(() => gpuPersistentBufferPoolReservedBytes(-1), throwsRangeError);
    expect(
      () => gpuPersistentBufferPoolReservedBytes(1, alignmentBytes: 0),
      throwsArgumentError,
    );
  });
}

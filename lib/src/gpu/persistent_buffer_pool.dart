import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

const _defaultPageBytes = 1024 * 1024;
const _defaultMaxPageBytes = 192 * 1024 * 1024;
const _defaultMaxAllocationBytes = 256 * 1024;
const _defaultAlignmentBytes = 16;
const _defaultQuarantineFrames = 4;

/// Whether [bytes] is small enough to share a persistent upload page.
@visibleForTesting
bool gpuPersistentBufferPoolEligible(
  int bytes, {
  int maxAllocationBytes = _defaultMaxAllocationBytes,
}) {
  if (bytes < 0) {
    throw RangeError.value(bytes, 'bytes', 'must not be negative');
  }
  if (maxAllocationBytes <= 0) {
    throw ArgumentError.value(
      maxAllocationBytes,
      'maxAllocationBytes',
      'must be positive',
    );
  }
  return bytes > 0 && bytes <= maxAllocationBytes;
}

/// Rounded storage reserved inside a persistent upload page.
@visibleForTesting
int gpuPersistentBufferPoolReservedBytes(
  int bytes, {
  int alignmentBytes = _defaultAlignmentBytes,
}) {
  if (bytes < 0) {
    throw RangeError.value(bytes, 'bytes', 'must not be negative');
  }
  if (alignmentBytes <= 0) {
    throw ArgumentError.value(
      alignmentBytes,
      'alignmentBytes',
      'must be positive',
    );
  }
  if (bytes == 0) return 0;
  return ((bytes + alignmentBytes - 1) ~/ alignmentBytes) * alignmentBytes;
}

/// Whether another persistent page fits inside the physical pool cap.
@visibleForTesting
bool gpuPersistentBufferPoolCanAddPage({
  required int currentPageBytes,
  required int pageBytes,
  required int maxPageBytes,
}) {
  if (currentPageBytes < 0 || pageBytes <= 0 || maxPageBytes < pageBytes) {
    throw ArgumentError('Invalid persistent GPU buffer page budget');
  }

  return currentPageBytes <= maxPageBytes - pageBytes;
}

/// Whether the largest pooled allocation still fits after alignment.
@visibleForTesting
bool gpuPersistentBufferPoolMaxAllocationFitsPage({
  required int pageBytes,
  required int maxAllocationBytes,
  required int alignmentBytes,
}) {
  if (pageBytes <= 0 || maxAllocationBytes <= 0 || alignmentBytes <= 0) {
    throw ArgumentError('Invalid persistent GPU buffer allocation bounds');
  }

  return gpuPersistentBufferPoolReservedBytes(
        maxAllocationBytes,
        alignmentBytes: alignmentBytes,
      ) <=
      pageBytes;
}

/// Interval activity and current physical occupancy of the persistent pool.
final class const GpuPersistentBufferPoolSnapshot({
  required final int pageCount,
  required final int pageBytes,
  required final int writeCount,
  required final int writeBytes,
  required final int pageAllocationCount,
  required final int reusedRangeCount,
});

/// One immutable cached range inside a host-visible persistent page.
///
/// Call [release] only after the cache no longer owns the range. The allocator
/// quarantines it for the configured in-flight frame count before allowing an
/// overwrite.
final class GpuPersistentBufferAllocation._(
  final gpu.DeviceBuffer buffer,
  final int offsetInBytes,
  final int lengthInBytes,
  final int _reservedBytes,
  final _GpuPersistentBufferPage _page,
  final int _quarantineFrames,
) {
  var _released = false;

  void release(int frame) {
    if (_released) return;
    _released = true;
    _page.release(
      offsetInBytes,
      _reservedBytes,
      readyFrame: frame + _quarantineFrames,
    );
  }
}

/// A persistent range allocator for cached vertex/index uploads.
///
/// Payloads up to 256 KiB are packed into 1 MiB host-visible pages, capped at
/// 192 MiB total. Freed ranges sit in a four-frame quarantine before entering
/// the page free-list, so submitted draws cannot observe later overwrites.
/// Larger payloads and cap overflow use dedicated buffers outside this pool.
final class GpuPersistentBufferPool({
  gpu.GpuContext? context,
  final int pageBytes = _defaultPageBytes,
  final int maxPageBytes = _defaultMaxPageBytes,
  final int maxAllocationBytes = _defaultMaxAllocationBytes,
  final int alignmentBytes = _defaultAlignmentBytes,
  final int quarantineFrames = _defaultQuarantineFrames,
}) {
  this {
    if (pageBytes <= 0 ||
        maxAllocationBytes <= 0 ||
        alignmentBytes <= 0 ||
        !gpuPersistentBufferPoolMaxAllocationFitsPage(
          pageBytes: pageBytes,
          maxAllocationBytes: maxAllocationBytes,
          alignmentBytes: alignmentBytes,
        ) ||
        maxPageBytes < pageBytes ||
        quarantineFrames < 0) {
      throw ArgumentError('Invalid persistent GPU buffer pool configuration');
    }
  }

  final gpu.GpuContext _context = context ?? gpu.gpuContext;
  final _pages = <_GpuPersistentBufferPage>[];

  // One monotonic clock is shared by every allocation so diagnostics do not
  // allocate a Stopwatch per upload and perturb the small-buffer hot path.
  final _timingClock = Stopwatch()..start();
  var _searchMicros = 0;
  var _searchMaxMicros = 0;
  var _pageAllocationMicros = 0;
  var _pageAllocationMaxMicros = 0;
  var _overwriteMicros = 0;
  var _overwriteMaxMicros = 0;
  var _flushMicros = 0;
  var _flushMaxMicros = 0;

  var _writeCount = 0;
  var _writeBytes = 0;
  var _pageAllocationCount = 0;
  var _reusedRangeCount = 0;

  /// Packs [bytes] into a persistent page, or returns null for large payloads.
  GpuPersistentBufferAllocation? allocate(
    Uint8List bytes, {
    required int frame,
  }) {
    final byteLength = bytes.lengthInBytes;
    if (!gpuPersistentBufferPoolEligible(
      byteLength,
      maxAllocationBytes: maxAllocationBytes,
    )) {
      return null;
    }
    final reservedBytes = gpuPersistentBufferPoolReservedBytes(
      byteLength,
      alignmentBytes: alignmentBytes,
    );

    final searchStart = _timingClock.elapsedMicroseconds;
    _GpuPersistentBufferPage? selected;
    int? offset;
    var reusedRange = false;
    for (final page in _pages) {
      final allocation = page.allocate(reservedBytes);
      if (allocation == null) continue;
      selected = page;
      offset = allocation.offset;
      reusedRange = allocation.reusedRange;
      break;
    }
    final searchMicros = _timingClock.elapsedMicroseconds - searchStart;
    _searchMicros += searchMicros;
    if (searchMicros > _searchMaxMicros) _searchMaxMicros = searchMicros;

    if (selected == null) {
      if (!gpuPersistentBufferPoolCanAddPage(
        currentPageBytes: _pages.length * pageBytes,
        pageBytes: pageBytes,
        maxPageBytes: maxPageBytes,
      )) {
        return null;
      }
      final pageAllocationStart = _timingClock.elapsedMicroseconds;
      selected = .new(
        _context.createDeviceBuffer(.hostVisible, pageBytes),
        pageBytes,
      );
      final pageAllocationMicros =
          _timingClock.elapsedMicroseconds - pageAllocationStart;
      _pageAllocationMicros += pageAllocationMicros;
      if (pageAllocationMicros > _pageAllocationMaxMicros) {
        _pageAllocationMaxMicros = pageAllocationMicros;
      }
      _pages.add(selected);
      _pageAllocationCount += 1;
      final allocation = selected.allocate(reservedBytes)!;
      offset = allocation.offset;
    }

    final data = ByteData.sublistView(bytes);
    final overwriteStart = _timingClock.elapsedMicroseconds;
    final success = selected.buffer.overwrite(
      data,
      destinationOffsetInBytes: offset!,
    );
    final overwriteMicros = _timingClock.elapsedMicroseconds - overwriteStart;
    _overwriteMicros += overwriteMicros;
    if (overwriteMicros > _overwriteMaxMicros) {
      _overwriteMaxMicros = overwriteMicros;
    }
    if (!success) {
      selected.release(offset, reservedBytes, readyFrame: frame);
      selected.reclaim(frame);
      throw StateError(
        'Failed to write persistent GPU buffer range '
        '(offset=$offset, length=$byteLength)',
      );
    }

    final flushStart = _timingClock.elapsedMicroseconds;
    selected.buffer.flush(offsetInBytes: offset, lengthInBytes: byteLength);
    final flushMicros = _timingClock.elapsedMicroseconds - flushStart;
    _flushMicros += flushMicros;
    if (flushMicros > _flushMaxMicros) _flushMaxMicros = flushMicros;

    _writeCount += 1;
    _writeBytes += byteLength;
    if (reusedRange) _reusedRangeCount += 1;

    return ._(
      selected.buffer,
      offset,
      byteLength,
      reservedBytes,
      selected,
      quarantineFrames,
    );
  }

  /// Advances quarantine and drops fully unused pages, retaining one spare.
  void beginFrame(int frame) {
    for (final page in _pages) {
      page.reclaim(frame);
    }
    var keptSpare = false;
    _pages.removeWhere((page) {
      if (!page.fullyFree) return false;
      if (!keptSpare) {
        keptSpare = true;
        page.reset();
        return false;
      }
      return true;
    });
  }

  void _logTimingAndReset() {
    if (_writeCount == 0 && _pageAllocationCount == 0) {
      debugPrint('[GpuBufferPoolTiming] none');
    } else {
      String metric(int count, int total, int maximum) {
        if (count == 0) return '0/-/-/-';
        final average = (total / count).toStringAsFixed(0);
        return '$count/${total}us/${average}us/${maximum}us';
      }

      debugPrint(
        '[GpuBufferPoolTiming] '
        'search=${metric(_writeCount, _searchMicros, _searchMaxMicros)} '
        'newPage=${metric(_pageAllocationCount, _pageAllocationMicros, _pageAllocationMaxMicros)} '
        'overwrite=${metric(_writeCount, _overwriteMicros, _overwriteMaxMicros)} '
        'flush=${metric(_writeCount, _flushMicros, _flushMaxMicros)}',
      );
    }
    _searchMicros = 0;
    _searchMaxMicros = 0;
    _pageAllocationMicros = 0;
    _pageAllocationMaxMicros = 0;
    _overwriteMicros = 0;
    _overwriteMaxMicros = 0;
    _flushMicros = 0;
    _flushMaxMicros = 0;
  }

  /// Returns interval activity and resets only the interval counters.
  GpuPersistentBufferPoolSnapshot takeSnapshotAndReset() {
    final snapshot = GpuPersistentBufferPoolSnapshot(
      pageCount: _pages.length,
      pageBytes: _pages.length * pageBytes,
      writeCount: _writeCount,
      writeBytes: _writeBytes,
      pageAllocationCount: _pageAllocationCount,
      reusedRangeCount: _reusedRangeCount,
    );
    _logTimingAndReset();
    _writeCount = 0;
    _writeBytes = 0;
    _pageAllocationCount = 0;
    _reusedRangeCount = 0;
    return snapshot;
  }

  void dispose() {
    _pages.clear();
    _writeCount = 0;
    _writeBytes = 0;
    _pageAllocationCount = 0;
    _reusedRangeCount = 0;
    _searchMicros = 0;
    _searchMaxMicros = 0;
    _pageAllocationMicros = 0;
    _pageAllocationMaxMicros = 0;
    _overwriteMicros = 0;
    _overwriteMaxMicros = 0;
    _flushMicros = 0;
    _flushMaxMicros = 0;
  }
}

final class _GpuBufferRange(var int offset, var int length);

final class _GpuPendingBufferRange(
  super.offset,
  super.length,
  final int readyFrame,
) extends _GpuBufferRange;

final class _GpuPersistentBufferPage(
  final gpu.DeviceBuffer buffer,
  final int lengthInBytes,
) {
  var _cursor = 0;
  var _liveAllocations = 0;
  final _freeRanges = <_GpuBufferRange>[];
  final _pendingRanges = <_GpuPendingBufferRange>[];

  bool get fullyFree => _liveAllocations == 0 && _pendingRanges.isEmpty;

  ({int offset, bool reusedRange})? allocate(int reservedBytes) {
    for (var index = 0; index < _freeRanges.length; index += 1) {
      final range = _freeRanges[index];
      if (range.length < reservedBytes) continue;
      final offset = range.offset;
      if (range.length == reservedBytes) {
        _freeRanges.removeAt(index);
      } else {
        range
          ..offset += reservedBytes
          ..length -= reservedBytes;
      }
      _liveAllocations += 1;
      return (offset: offset, reusedRange: true);
    }
    if (_cursor + reservedBytes > lengthInBytes) return null;
    final offset = _cursor;
    _cursor += reservedBytes;
    _liveAllocations += 1;
    return (offset: offset, reusedRange: false);
  }

  void release(int offset, int length, {required int readyFrame}) {
    if (_liveAllocations <= 0) {
      throw StateError('Persistent GPU buffer page release underflow');
    }
    _liveAllocations -= 1;
    _pendingRanges.add(.new(offset, length, readyFrame));
  }

  void reclaim(int frame) {
    if (_pendingRanges.isEmpty) {
      if (fullyFree) reset();
      return;
    }
    var changed = false;
    _pendingRanges.removeWhere((range) {
      if (range.readyFrame > frame) return false;
      _freeRanges.add(.new(range.offset, range.length));
      changed = true;
      return true;
    });
    if (changed) _coalesceFreeRanges();
    if (fullyFree) reset();
  }

  void reset() {
    if (!fullyFree) return;
    _cursor = 0;
    _freeRanges.clear();
  }

  void _coalesceFreeRanges() {
    if (_freeRanges.length < 2) return;
    _freeRanges.sort((left, right) => left.offset.compareTo(right.offset));
    var write = 0;
    for (var read = 1; read < _freeRanges.length; read += 1) {
      final current = _freeRanges[write];
      final next = _freeRanges[read];
      if (current.offset + current.length == next.offset) {
        current.length += next.length;
      } else {
        write += 1;
        if (write != read) _freeRanges[write] = next;
      }
    }
    _freeRanges.removeRange(write + 1, _freeRanges.length);
  }
}

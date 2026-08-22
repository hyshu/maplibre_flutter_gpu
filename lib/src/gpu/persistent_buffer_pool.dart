import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

const int _defaultPageBytes = 1024 * 1024;
const int _defaultMaxAllocationBytes = 256 * 1024;
const int _defaultLargePageBytes = 8 * 1024 * 1024;
const int _defaultLargeMaxAllocationBytes = 4 * 1024 * 1024;
const int _defaultAlignmentBytes = 16;
const int _defaultQuarantineFrames = 4;

/// Whether [bytes] is small enough to share one persistent upload page tier.
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

enum GpuPersistentBufferPoolTier { small, large, dedicated }

/// Selects the persistent page tier for one upload payload.
@visibleForTesting
GpuPersistentBufferPoolTier gpuPersistentBufferPoolTierForBytes(
  int bytes, {
  int smallMaxAllocationBytes = _defaultMaxAllocationBytes,
  int largeMaxAllocationBytes = _defaultLargeMaxAllocationBytes,
}) {
  if (bytes < 0) {
    throw RangeError.value(bytes, 'bytes', 'must not be negative');
  }
  if (smallMaxAllocationBytes <= 0 ||
      largeMaxAllocationBytes <= smallMaxAllocationBytes) {
    throw ArgumentError('Invalid persistent GPU buffer pool tier bounds');
  }
  if (bytes == 0 || bytes > largeMaxAllocationBytes) {
    return GpuPersistentBufferPoolTier.dedicated;
  }
  if (bytes <= smallMaxAllocationBytes) {
    return GpuPersistentBufferPoolTier.small;
  }
  return GpuPersistentBufferPoolTier.large;
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

/// Interval activity and current physical occupancy of the persistent pool.
final class GpuPersistentBufferPoolSnapshot {
  const GpuPersistentBufferPoolSnapshot({
    required this.pageCount,
    required this.pageBytes,
    required this.writeCount,
    required this.writeBytes,
    required this.pageAllocationCount,
    required this.reusedRangeCount,
  });

  final int pageCount;
  final int pageBytes;
  final int writeCount;
  final int writeBytes;
  final int pageAllocationCount;
  final int reusedRangeCount;
}

/// One immutable cached range inside a host-visible persistent page.
///
/// Call [release] only after the cache no longer owns the range. The allocator
/// quarantines it for the configured in-flight frame count before allowing an
/// overwrite.
final class GpuPersistentBufferAllocation {
  GpuPersistentBufferAllocation._(
    this.buffer,
    this.offsetInBytes,
    this.lengthInBytes,
    this._reservedBytes,
    this._page,
    this._quarantineFrames,
  );

  final gpu.DeviceBuffer buffer;
  final int offsetInBytes;
  final int lengthInBytes;
  final int _reservedBytes;
  final _GpuPersistentBufferPage _page;
  final int _quarantineFrames;
  bool _released = false;

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
/// Payloads up to 256 KiB are packed into 1 MiB host-visible pages. Payloads
/// from 256 KiB through 4 MiB use separate 8 MiB pages, keeping large
/// fill-extrusion uploads from fragmenting compact geometry pages. Freed ranges
/// sit in a four-frame quarantine before entering a page free-list, so submitted
/// draws cannot observe later overwrites. Larger payloads keep using dedicated
/// DeviceBuffers outside this allocator.
final class GpuPersistentBufferPool {
  GpuPersistentBufferPool({
    gpu.GpuContext? context,
    this.pageBytes = _defaultPageBytes,
    this.maxAllocationBytes = _defaultMaxAllocationBytes,
    this.largePageBytes = _defaultLargePageBytes,
    this.largeMaxAllocationBytes = _defaultLargeMaxAllocationBytes,
    this.alignmentBytes = _defaultAlignmentBytes,
    this.quarantineFrames = _defaultQuarantineFrames,
  }) : _context = context ?? gpu.gpuContext {
    if (pageBytes <= 0 ||
        maxAllocationBytes <= 0 ||
        maxAllocationBytes > pageBytes ||
        largePageBytes <= 0 ||
        largeMaxAllocationBytes <= maxAllocationBytes ||
        largeMaxAllocationBytes > largePageBytes ||
        alignmentBytes <= 0 ||
        quarantineFrames < 0) {
      throw ArgumentError('Invalid persistent GPU buffer pool configuration');
    }
  }

  final gpu.GpuContext _context;
  final int pageBytes;
  final int maxAllocationBytes;
  final int largePageBytes;
  final int largeMaxAllocationBytes;
  final int alignmentBytes;
  final int quarantineFrames;
  final List<_GpuPersistentBufferPage> _pages = [];
  final List<_GpuPersistentBufferPage> _largePages = [];

  int _writeCount = 0;
  int _writeBytes = 0;
  int _pageAllocationCount = 0;
  int _reusedRangeCount = 0;

  /// Packs [bytes] into a persistent page, or returns null for huge payloads.
  GpuPersistentBufferAllocation? allocate(Uint8List bytes, {required int frame}) {
    final byteLength = bytes.lengthInBytes;
    final tier = gpuPersistentBufferPoolTierForBytes(
      byteLength,
      smallMaxAllocationBytes: maxAllocationBytes,
      largeMaxAllocationBytes: largeMaxAllocationBytes,
    );
    if (tier == GpuPersistentBufferPoolTier.dedicated) return null;

    final pages = tier == GpuPersistentBufferPoolTier.small
        ? _pages
        : _largePages;
    final selectedPageBytes = tier == GpuPersistentBufferPoolTier.small
        ? pageBytes
        : largePageBytes;
    return _allocateInPages(
      bytes,
      frame: frame,
      pages: pages,
      selectedPageBytes: selectedPageBytes,
    );
  }

  GpuPersistentBufferAllocation _allocateInPages(
    Uint8List bytes, {
    required int frame,
    required List<_GpuPersistentBufferPage> pages,
    required int selectedPageBytes,
  }) {
    final byteLength = bytes.lengthInBytes;
    final reservedBytes = gpuPersistentBufferPoolReservedBytes(
      byteLength,
      alignmentBytes: alignmentBytes,
    );

    _GpuPersistentBufferPage? selected;
    int? offset;
    var reusedRange = false;
    for (final page in pages) {
      page.reclaim(frame);
      final allocation = page.allocate(reservedBytes);
      if (allocation == null) continue;
      selected = page;
      offset = allocation.offset;
      reusedRange = allocation.reusedRange;
      break;
    }
    if (selected == null) {
      selected = _GpuPersistentBufferPage(
        _context.createDeviceBuffer(
          gpu.StorageMode.hostVisible,
          selectedPageBytes,
        ),
        selectedPageBytes,
      );
      pages.add(selected);
      _pageAllocationCount += 1;
      final allocation = selected.allocate(reservedBytes)!;
      offset = allocation.offset;
    }

    final data = ByteData.sublistView(bytes);
    final success = selected.buffer.overwrite(
      data,
      destinationOffsetInBytes: offset!,
    );
    if (!success) {
      selected.release(offset, reservedBytes, readyFrame: frame);
      selected.reclaim(frame);
      throw StateError(
        'Failed to write persistent GPU buffer range '
        '(offset=$offset, length=$byteLength)',
      );
    }
    selected.buffer.flush(offsetInBytes: offset, lengthInBytes: byteLength);
    _writeCount += 1;
    _writeBytes += byteLength;
    if (reusedRange) _reusedRangeCount += 1;

    return GpuPersistentBufferAllocation._(
      selected.buffer,
      offset,
      byteLength,
      reservedBytes,
      selected,
      quarantineFrames,
    );
  }

  /// Advances quarantine and drops fully unused pages, retaining one per tier.
  void beginFrame(int frame) {
    _advancePages(_pages, frame);
    _advancePages(_largePages, frame);
  }

  void _advancePages(List<_GpuPersistentBufferPage> pages, int frame) {
    for (final page in pages) {
      page.reclaim(frame);
    }
    var keptSpare = false;
    pages.removeWhere((page) {
      if (!page.fullyFree) return false;
      if (!keptSpare) {
        keptSpare = true;
        page.reset();
        return false;
      }
      return true;
    });
  }

  /// Returns interval activity and resets only the interval counters.
  GpuPersistentBufferPoolSnapshot takeSnapshotAndReset() {
    final snapshot = GpuPersistentBufferPoolSnapshot(
      pageCount: _pages.length + _largePages.length,
      pageBytes:
          _pages.length * pageBytes + _largePages.length * largePageBytes,
      writeCount: _writeCount,
      writeBytes: _writeBytes,
      pageAllocationCount: _pageAllocationCount,
      reusedRangeCount: _reusedRangeCount,
    );
    _writeCount = 0;
    _writeBytes = 0;
    _pageAllocationCount = 0;
    _reusedRangeCount = 0;
    return snapshot;
  }

  void dispose() {
    _pages.clear();
    _largePages.clear();
    _writeCount = 0;
    _writeBytes = 0;
    _pageAllocationCount = 0;
    _reusedRangeCount = 0;
  }
}

final class _GpuBufferRange {
  _GpuBufferRange(this.offset, this.length);

  int offset;
  int length;
}

final class _GpuPendingBufferRange extends _GpuBufferRange {
  _GpuPendingBufferRange(super.offset, super.length, this.readyFrame);

  final int readyFrame;
}

final class _GpuPersistentBufferPage {
  _GpuPersistentBufferPage(this.buffer, this.lengthInBytes);

  final gpu.DeviceBuffer buffer;
  final int lengthInBytes;
  int _cursor = 0;
  int _liveAllocations = 0;
  final List<_GpuBufferRange> _freeRanges = [];
  final List<_GpuPendingBufferRange> _pendingRanges = [];

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
    _pendingRanges.add(_GpuPendingBufferRange(offset, length, readyFrame));
  }

  void reclaim(int frame) {
    if (_pendingRanges.isEmpty) {
      if (fullyFree) reset();
      return;
    }
    var changed = false;
    _pendingRanges.removeWhere((range) {
      if (range.readyFrame > frame) return false;
      _freeRanges.add(_GpuBufferRange(range.offset, range.length));
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

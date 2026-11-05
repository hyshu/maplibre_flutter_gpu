import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

/// Whether owned buffer capacities contribute to Android GC scheduling.
bool get gpuBufferAccountingEnabled =>
    defaultTargetPlatform == TargetPlatform.android &&
    const bool.fromEnvironment('MAPLIBRE_GPU_BUFFER_ACCOUNTING');

final _bufferAccounting = GpuBufferAccounting();

/// Accounts a buffer's capacity once, including storage shared by its views.
///
/// This changes GC scheduling only. The engine retains responsibility for
/// releasing buffer storage, including resources used by submitted commands.
gpu.DeviceBuffer accountGpuBuffer(gpu.DeviceBuffer buffer) {
  if (gpuBufferAccountingEnabled) {
    _bufferAccounting.track(buffer, buffer.sizeInBytes);
  }
  return buffer;
}

/// Associates external memory accounting with a buffer's Dart lifetime.
///
/// Keys are buffer identities, never individual views or cache entries. The
/// registry retains neither keys nor GPU resources. Accounting remains while
/// a key is reachable and is removed by GC after the key becomes unreachable.
/// Native commands can retain storage beyond the lifetime of its Dart wrapper.
final class GpuBufferAccounting {
  final _accounts = Expando<_BufferAccountingToken>();

  /// Accounts a positive capacity once when Android accounting is enabled.
  ///
  /// Returns whether a new attachment was made. Zero bytes are ignored.
  /// Negative sizes and changes to an already accounted capacity are errors.
  /// The caller must keep this registry alive for as long as its buffers.
  /// Cache eviction must not remove an attachment because other views can
  /// still reference the buffer.
  bool track(Object buffer, int sizeInBytes) {
    if (!gpuBufferAccountingEnabled) return false;
    RangeError.checkNotNegative(sizeInBytes, 'sizeInBytes');
    final existing = _accounts[buffer];
    if (existing != null) {
      if (existing.sizeInBytes != sizeInBytes) {
        throw ArgumentError('An accounted buffer cannot change capacity');
      }
      return false;
    }
    if (sizeInBytes == 0) return false;
    _accounts[buffer] = _BufferAccountingToken(sizeInBytes);

    return true;
  }
}

final class _BufferAccountingToken implements Finalizable {
  _BufferAccountingToken(this.sizeInBytes) {
    final token = malloc<Uint8>(1);
    try {
      _finalizer.attach(this, token.cast(), externalSize: sizeInBytes);
    } catch (_) {
      malloc.free(token);
      rethrow;
    }
  }

  // The callback owns only this token. It never accesses GPU storage.
  static final _finalizer = NativeFinalizer(malloc.nativeFree);
  final int sizeInBytes;
}

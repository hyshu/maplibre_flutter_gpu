import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../frame/draw_flags.dart';
import '../frame/vertex_repack.dart';
import '../native/draw_command.dart';
import '../native/byte_span.dart';
import '../native/vertex_repack.dart';

final class _NativeVertexAllocation implements Finalizable {
  _NativeVertexAllocation(this.length) : pointer = malloc<Uint8>(length) {
    _finalizer.attach(this, pointer.cast(), detach: this, externalSize: length);
  }

  static final _finalizer = NativeFinalizer(malloc.nativeFree);
  final int length;
  final Pointer<Uint8> pointer;

  void dispose() {
    _finalizer.detach(this);
    malloc.free(pointer);
  }
}

/// Owns bounded conversion storage for synchronous vertex uploads.
///
/// Source and converted bytes are borrowed only inside [consume]. A consumer
/// must copy them before returning and must not retain either view or pointer.
final class VertexUploadStaging {
  /// Selects one Android staging allocator when native conversion is available.
  VertexUploadStaging({
    NativeVertexRepack? nativeRepack,
    this.maxRetainedBytes = 4 * 1024 * 1024,
  }) : _nativeRepack = nativeVertexRepackingEnabled ? nativeRepack : null {
    RangeError.checkNotNegative(maxRetainedBytes, 'maxRetainedBytes');
    if (_nativeRepack == null &&
        defaultTargetPlatform == TargetPlatform.android) {
      _dartScratch = VertexRepackScratch(maxRetainedBytes: maxRetainedBytes);
    }
  }

  /// Maximum native or Dart staging allocation retained between uploads.
  final int maxRetainedBytes;
  final NativeVertexRepack? _nativeRepack;
  VertexRepackScratch? _dartScratch;
  _NativeVertexAllocation? _retained;
  var _inUse = false;
  var _clearPending = false;
  var _activeBytes = 0;

  /// Staging bytes retained between uploads.
  int get retainedBytes =>
      _retained?.length ?? _dartScratch?.retainedBytes ?? 0;

  /// Native destination bytes currently borrowed by an upload.
  int get activeBytes => _activeBytes;

  /// Converts a live native span and consumes it before releasing staging.
  ///
  /// The caller keeps the source allocation alive until this returns. Nested
  /// calls are rejected. Reclamation requested by the consumer is deferred
  /// until the consumer returns, including when conversion or upload throws.
  T consume<T>({
    required int sourceAddress,
    required int vertexCount,
    required int sourceStride,
    required int shader,
    required int flags,
    required T Function(Uint8List bytes) upload,
  }) {
    if (_inUse) throw StateError('Vertex staging is already in use');
    if (vertexCount < 0 ||
        vertexCount > 0xffffffff ||
        sourceStride <= 0 ||
        (vertexCount > 0 && sourceAddress == 0)) {
      throw RangeError('Invalid native vertex span');
    }
    const maxAddress = 0x7fffffffffffffff;
    if (vertexCount > maxAddress ~/ sourceStride) {
      throw RangeError('Native vertex span is too large');
    }
    final sourceLength = vertexCount * sourceStride;
    if (!nativeByteSpanFits(
      sourceAddress,
      sourceLength,
      addressBits: sizeOf<IntPtr>() * 8,
    )) {
      throw RangeError('Native vertex address range overflows');
    }
    final targetStride = gpuVertexStride(shader, flags);
    final targetLength = vertexCount * targetStride;
    _inUse = true;
    _NativeVertexAllocation? oneShot;
    try {
      final source = vertexCount == 0
          ? Uint8List(0)
          : Pointer<Uint8>.fromAddress(sourceAddress).asTypedList(sourceLength);
      if (vertexCount == 0 || sourceStride == targetStride) {
        return upload(source);
      }
      final nativeRepack = _nativeRepack;
      if (nativeRepack == null) {
        return upload(
          repackVertexDataForGpu(
            source,
            vertexCount: vertexCount,
            sourceStride: sourceStride,
            shader: shader,
            flags: flags,
            scratch: _dartScratch,
          ),
        );
      }
      final retained = _retained;
      if (retained != null &&
          nativeByteSpansOverlap(
            sourceAddress,
            sourceLength,
            retained.pointer.address,
            retained.length,
          )) {
        throw ArgumentError('Source must not alias retained vertex staging');
      }
      final _NativeVertexAllocation allocation;
      if (targetLength > maxRetainedBytes) {
        allocation = oneShot = _NativeVertexAllocation(targetLength);
      } else {
        if ((_retained?.length ?? 0) < targetLength) {
          _retained?.dispose();
          _retained = null;
          var capacity = 4096;
          while (capacity < targetLength) {
            capacity *= 2;
          }
          _retained = _NativeVertexAllocation(
            capacity > maxRetainedBytes ? maxRetainedBytes : capacity,
          );
        }
        allocation = _retained!;
      }
      _activeBytes = allocation.length;
      final destinationAddress = allocation.pointer.address;
      if (nativeByteSpansOverlap(
        sourceAddress,
        sourceLength,
        destinationAddress,
        targetLength,
      )) {
        throw ArgumentError('Source and destination must not overlap');
      }
      final layout = switch ((shader, sourceStride, targetStride)) {
        (ShaderType.fillExtrusion, 12, 24) => 1,
        (ShaderType.fillExtrusion, 44, 56) => 2,
        (ShaderType.fillOutlineTriangulated, 8, 24) => 3,
        (_, 8, 24) when isLineShader(shader) => 3,
        _ => 0,
      };
      final result = layout == 0
          ? 0
          : nativeRepack(
              layout,
              Pointer<Void>.fromAddress(sourceAddress),
              sourceLength,
              vertexCount,
              allocation.pointer.cast(),
              allocation.length,
            );
      if (result != 0 && result != 1) {
        throw StateError('Native vertex conversion rejected the source span');
      }
      final destination = allocation.pointer.asTypedList(targetLength);
      if (result == 0) {
        repackVertexDataForGpu(
          source,
          vertexCount: vertexCount,
          sourceStride: sourceStride,
          shader: shader,
          flags: flags,
          destination: destination,
        );
      }

      return upload(destination);
    } finally {
      oneShot?.dispose();
      _activeBytes = 0;
      _inUse = false;
      if (_clearPending) clear();
    }
  }

  /// Releases retained storage after any current synchronous upload finishes.
  void clear() {
    if (_inUse) {
      _clearPending = true;

      return;
    }
    _clearPending = false;
    _retained?.dispose();
    _retained = null;
    _dartScratch?.clear();
  }
}

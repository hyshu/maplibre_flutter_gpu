import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/gpu/command_resources.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/gpu/vertex_staging.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/native/vertex_repack.dart';

const _nativeEnabled = bool.fromEnvironment(
  'MAPLIBRE_NATIVE_REPACKING',
  defaultValue: true,
);

int _convert(
  int layout,
  Pointer<Void> source,
  int sourceBytes,
  int count,
  Pointer<Void> destination,
  int capacity,
) {
  if (layout == 3) {
    final input = ByteData.sublistView(
      source.cast<Uint8>().asTypedList(sourceBytes),
    );
    final output = ByteData.sublistView(
      destination.cast<Uint8>().asTypedList(capacity),
    );
    for (var vertex = 0; vertex < count; vertex++) {
      for (var field = 0; field < 6; field++) {
        final value = field < 2
            ? input.getInt16(vertex * 8 + field * 2, Endian.little)
            : input.getUint8(vertex * 8 + field + 2);
        output.setFloat32(
          vertex * 24 + field * 4,
          value.toDouble(),
          Endian.little,
        );
      }
    }
    return 1;
  }
  final (shader, stride, flags) = switch (layout) {
    1 => (ShaderType.fillExtrusion, 12, 0),
    2 => (
      ShaderType.fillExtrusion,
      44,
      DrawCommandFlags.fillExtrusionDataDriven,
    ),
    4 => (ShaderType.line, 8, 0),
    _ => throw StateError('Unexpected native layout'),
  };
  repackVertexDataForGpu(
    source.cast<Uint8>().asTypedList(sourceBytes),
    vertexCount: count,
    sourceStride: stride,
    shader: shader,
    flags: flags,
    destination: destination.cast<Uint8>().asTypedList(capacity),
  );

  return 1;
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'native capability requires Android, enabled flag and optional symbol',
    () {
      expect(nativeVertexRepackingEnabled, _nativeEnabled);
      expect(lookupNativeVertexRepack(DynamicLibrary.process()), isNull);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(nativeVertexRepackingEnabled, isFalse);
      expect(lookupNativeVertexRepack(DynamicLibrary.process()), isNull);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform conversion preserves old-library fallback', () {
      debugDefaultTargetPlatformOverride = platform;
      final source = calloc<Uint8>(12);
      addTearDown(() => calloc.free(source));
      source.asTypedList(12).fillRange(0, 12, 3);
      var calls = 0;
      int native(
        int l,
        Pointer<Void> s,
        int n,
        int c,
        Pointer<Void> d,
        int cap,
      ) {
        calls++;

        return _convert(l, s, n, c, d, cap);
      }

      for (final converter in <NativeVertexRepack?>[null, native]) {
        final staging = VertexUploadStaging(nativeRepack: converter);
        addTearDown(staging.clear);
        final result = staging.consume(
          sourceAddress: source.address,
          vertexCount: 1,
          sourceStride: 12,
          shader: ShaderType.fillExtrusion,
          flags: 0,
          upload: Uint8List.fromList,
        );
        expect(
          result,
          orderedEquals(
            repackVertexDataForGpu(
              source.asTypedList(12),
              vertexCount: 1,
              sourceStride: 12,
              shader: ShaderType.fillExtrusion,
              flags: 0,
            ),
          ),
        );
      }
      expect(
        calls,
        platform == TargetPlatform.android && _nativeEnabled ? 1 : 0,
      );
    });
  }

  test(
    'native storage is reused, fallback shares it, and trim waits for upload',
    () {
      if (!_nativeEnabled) return;
      final source = calloc<Uint8>(132);
      addTearDown(() => calloc.free(source));
      source.asTypedList(132).fillRange(0, 132, 17);
      final destinations = <int>[];
      var reject = false;
      int native(
        int l,
        Pointer<Void> s,
        int n,
        int c,
        Pointer<Void> d,
        int cap,
      ) {
        destinations.add(d.address);
        if (reject) {
          d.cast<Uint8>().asTypedList(cap).fillRange(0, cap, 0xff);

          return 0;
        }
        return _convert(l, s, n, c, d, cap);
      }

      final staging = VertexUploadStaging(
        nativeRepack: native,
        maxRetainedBytes: 169,
      );
      addTearDown(staging.clear);
      Uint8List consume({bool trim = false}) => staging.consume(
        sourceAddress: source.address,
        vertexCount: 3,
        sourceStride: 44,
        shader: ShaderType.fillExtrusion,
        flags: DrawCommandFlags.fillExtrusionDataDriven,
        upload: (bytes) {
          expect(staging.activeBytes, 169);
          final copied = Uint8List.fromList(bytes);
          if (trim) {
            staging.clear();
            expect(staging.retainedBytes, 169);
            expect(bytes, orderedEquals(copied));
          }

          return copied;
        },
      );
      final expected = consume();
      reject = true;
      expect(consume(), orderedEquals(expected));
      expect(destinations[1], destinations[0]);
      expect(consume(trim: true), orderedEquals(expected));
      expect(staging.retainedBytes, 0);
      expect(staging.activeBytes, 0);
    },
  );

  test(
    'unsupported layouts use the native allocation without invoking converter',
    () {
      if (!_nativeEnabled) return;
      final source = calloc<Uint8>(8);
      addTearDown(() => calloc.free(source));
      source.asTypedList(8).fillRange(0, 8, 1);
      final staging = VertexUploadStaging(
        nativeRepack: (_, _, _, _, _, _) {
          throw StateError('Unsupported layout reached native');
        },
      );
      addTearDown(staging.clear);
      final output = staging.consume(
        sourceAddress: source.address,
        vertexCount: 2,
        sourceStride: 4,
        shader: ShaderType.fill,
        flags: 0,
        upload: (bytes) {
          expect(staging.activeBytes, greaterThan(0));

          return Uint8List.fromList(bytes);
        },
      );
      expect(output.length, 16);
      expect(Float32List.sublistView(output), everyElement(257.0));
    },
  );

  test('oversize errors release active storage and reject nested uploads', () {
    if (!_nativeEnabled) return;
    final source = calloc<Uint8>(44);
    addTearDown(() => calloc.free(source));
    var status = 1;
    final staging = VertexUploadStaging(
      maxRetainedBytes: 55,
      nativeRepack: (l, s, n, c, d, cap) =>
          status == 1 ? _convert(l, s, n, c, d, cap) : status,
    );
    addTearDown(staging.clear);
    void consume(void Function(Uint8List) upload) => staging.consume(
      sourceAddress: source.address,
      vertexCount: 1,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      flags: DrawCommandFlags.fillExtrusionDataDriven,
      upload: upload,
    );
    expect(
      () => consume((bytes) {
        expect(staging.activeBytes, 56);
        expect(staging.retainedBytes, 0);
        expect(() => consume((_) {}), throwsStateError);
        staging.clear();
        expect(bytes.length, 56);
        throw StateError('Upload failed');
      }),
      throwsStateError,
    );
    expect(staging.activeBytes, 0);
    expect(staging.retainedBytes, 0);
    consume((bytes) => expect(bytes, everyElement(0)));
    status = -1;
    var uploaded = false;
    expect(() => consume((_) => uploaded = true), throwsStateError);
    expect(uploaded, isFalse);
    expect(staging.activeBytes, 0);
  });

  test('GPU-ready and empty spans allocate nothing and borrow the source', () {
    final source = calloc<Uint8>(24);
    addTearDown(() => calloc.free(source));
    final staging = VertexUploadStaging(
      nativeRepack: (_, _, _, _, _, _) {
        throw StateError('Bypass reached native');
      },
    );
    addTearDown(staging.clear);
    staging.consume(
      sourceAddress: source.address,
      vertexCount: 1,
      sourceStride: 24,
      shader: ShaderType.line,
      flags: DrawCommandFlags.lineGpuReady,
      upload: (bytes) {
        source.value = 41;
        expect(bytes.first, 41);
        expect(staging.activeBytes, 0);
      },
    );
    staging.consume(
      sourceAddress: 0,
      vertexCount: 0,
      sourceStride: 12,
      shader: ShaderType.fillExtrusion,
      flags: 0,
      upload: (bytes) => expect(bytes, isEmpty),
    );
    expect(staging.retainedBytes, 0);
  });

  test(
    'native-backed cache uploads own bytes across reuse and reclamation',
    () {
      final source = calloc<Uint8>(12);
      addTearDown(() => calloc.free(source));
      var calls = 0;
      final cache = _CopyingCache((l, s, n, c, d, cap) {
        calls++;

        return _convert(l, s, n, c, d, cap);
      });
      addTearDown(cache.dispose);
      final resources = GpuCommandResources(cache);
      _CopiedEntry upload(int id) => resources.cachedVertexBuffer(
        id,
        1,
        source.address,
        1,
        12,
        ShaderType.fillExtrusion,
        0,
      ) as _CopiedEntry;
      source.asTypedList(12).fillRange(0, 12, 3);
      final first = upload(1);
      final expected = Uint8List.fromList(first.bytes);
      source.asTypedList(12).fillRange(0, 12, 7);
      expect(upload(1), same(first));
      final second = upload(2);
      expect(first.bytes, orderedEquals(expected));
      expect(second.bytes, isNot(orderedEquals(expected)));
      cache.reduceMemoryUse();
      source.asTypedList(12).fillRange(0, 12, 11);
      upload(3);
      expect(first.bytes, orderedEquals(expected));
      expect(calls, _nativeEnabled ? 3 : 0);
    },
  );

  test(
    'constant outline uses line conversion while DD outline stays in Dart',
    () {
      final source = calloc<Uint8>(32 * 5);
      addTearDown(() => calloc.free(source));
      final layouts = <int>[];
      final staging = VertexUploadStaging(
        nativeRepack: (l, s, n, c, d, cap) {
          layouts.add(l);

          return _convert(l, s, n, c, d, cap);
        },
      );
      addTearDown(staging.clear);
      const packed = bool.fromEnvironment('MAPLIBRE_PACKED_LINE_VERTICES');
      for (final (stride, flags, targetStride) in [
        (8, 0, packed ? 12 : 24),
        (32, DrawCommandFlags.fillOutlineColorDataDriven, 48),
      ]) {
        final bytes = source.asTypedList(stride * 5);
        for (var index = 0; index < bytes.length; index++) {
          bytes[index] = (index * 53 + 17) & 255;
        }
        final input = ByteData.sublistView(bytes);
        input
          ..setInt16(0, -32768, Endian.little)
          ..setInt16(2, 32767, Endian.little)
          ..setUint8(4, 0)
          ..setUint8(5, 127)
          ..setUint8(6, 128)
          ..setUint8(7, 255);
        final expected = Uint8List(targetStride * 5);
        final output = ByteData.sublistView(expected);
        for (var vertex = 0; vertex < 5; vertex++) {
          if (targetStride == 12) {
            for (var chunk = 0; chunk < 3; chunk++) {
              var value = 0;
              var factor = 1;
              for (var byte = 0; byte < (chunk == 2 ? 2 : 3); byte++) {
                value +=
                    input.getUint8(vertex * stride + chunk * 3 + byte) * factor;
                factor *= 256;
              }
              output.setFloat32(
                vertex * targetStride + chunk * 4,
                value.toDouble(),
                Endian.little,
              );
            }
            continue;
          }
          for (var field = 0; field < 6; field++) {
            final value = field < 2
                ? input.getInt16(vertex * stride + field * 2, Endian.little)
                : input.getUint8(vertex * stride + field + 2);
            output.setFloat32(
              vertex * targetStride + field * 4,
              value.toDouble(),
              Endian.little,
            );
          }
          for (var byte = 8; byte < stride; byte++) {
            output.setUint8(
              vertex * targetStride + byte + 16,
              input.getUint8(vertex * stride + byte),
            );
          }
        }
        final result = staging.consume(
          sourceAddress: source.address,
          vertexCount: 5,
          sourceStride: stride,
          shader: ShaderType.fillOutlineTriangulated,
          flags: flags,
          upload: Uint8List.fromList,
        );
        expect(result, orderedEquals(expected));
        expect(layouts, _nativeEnabled ? [packed ? 4 : 3] : isEmpty);
      }
    },
  );

  test('retained staging cannot become its own source during growth', () {
    if (!_nativeEnabled) return;
    final source = calloc<Uint8>(44);
    addTearDown(() => calloc.free(source));
    var destinationAddress = 0;
    final staging = VertexUploadStaging(
      nativeRepack: (l, s, n, c, d, cap) {
        destinationAddress = d.address;

        return _convert(l, s, n, c, d, cap);
      },
    );
    addTearDown(staging.clear);
    void consume(int address, int count) => staging.consume(
      sourceAddress: address,
      vertexCount: count,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      flags: DrawCommandFlags.fillExtrusionDataDriven,
      upload: (_) {},
    );
    consume(source.address, 1);
    expect(staging.retainedBytes, 4096);
    expect(() => consume(destinationAddress, 100), throwsArgumentError);
    expect(staging.retainedBytes, 4096);
    expect(staging.activeBytes, 0);
    consume(source.address, 1);
  });

  test('invalid spans fail before native views or consumers are reached', () {
    final staging = VertexUploadStaging(
      nativeRepack: (_, _, _, _, _, _) {
        fail('Invalid input reached native conversion');
      },
    );
    addTearDown(staging.clear);
    for (final (address, count, stride) in [
      (1, 4, (1 << 62) + 1),
      (-4, 1, 12),
      (0, 1, 12),
      (1, -1, 12),
      (1, 0x100000000, 12),
      (1, 1, 0),
    ]) {
      expect(
        () => staging.consume(
          sourceAddress: address,
          vertexCount: count,
          sourceStride: stride,
          shader: ShaderType.fillExtrusion,
          flags: 0,
          upload: (_) => fail('Invalid input reached upload'),
        ),
        throwsRangeError,
      );
    }
    expect(staging.activeBytes, 0);
    expect(staging.retainedBytes, 0);
  });

  test(
    'empty native spans ignore tagged pointer bits without dereferencing',
    () {
      final staging = VertexUploadStaging(
        nativeRepack: (_, _, _, _, _, _) {
          fail('Empty input reached native conversion');
        },
      );
      addTearDown(staging.clear);
      for (final address in [0, -1, 0xb400000000001000]) {
        staging.consume(
          sourceAddress: address,
          vertexCount: 0,
          sourceStride: 12,
          shader: ShaderType.fillExtrusion,
          flags: 0,
          upload: (bytes) => expect(bytes, isEmpty),
        );
      }
      expect(staging.retainedBytes, 0);
    },
  );

  const libraryPath = String.fromEnvironment(
    'MAPLIBRE_VERTEX_REPACK_TEST_LIBRARY',
  );
  if (libraryPath.isNotEmpty) {
    test(
      'production C ABI matches Dart conversion at unaligned source addresses',
      () {
        final native = lookupNativeVertexRepack(
          DynamicLibrary.open(libraryPath),
        );
        if (!_nativeEnabled) {
          expect(native, isNull);

          return;
        }
        expect(native, isNotNull);
        final staging = VertexUploadStaging(nativeRepack: native);
        addTearDown(staging.clear);
        for (final (shader, stride, flags) in [
          (ShaderType.fillExtrusion, 12, 0),
          (
            ShaderType.fillExtrusion,
            44,
            DrawCommandFlags.fillExtrusionDataDriven,
          ),
          (ShaderType.line, 8, 0),
          (ShaderType.fillOutlineTriangulated, 8, 0),
        ]) {
          final owner = calloc<Uint8>(stride * 257 + 1);
          final source = owner + 1;
          try {
            final bytes = source.asTypedList(stride * 257);
            for (var i = 0; i < bytes.length; i++) {
              bytes[i] = (i * 53 + 17) & 255;
            }
            final expected = repackVertexDataForGpu(
              bytes,
              vertexCount: 257,
              sourceStride: stride,
              shader: shader,
              flags: flags,
            );
            final result = staging.consume(
              sourceAddress: source.address,
              vertexCount: 257,
              sourceStride: stride,
              shader: shader,
              flags: flags,
              upload: Uint8List.fromList,
            );
            expect(result, orderedEquals(expected));
          } finally {
            calloc.free(owner);
          }
        }
      },
    );
  }
}

class _CopyingCache extends GpuResourceCache {
  _CopyingCache(NativeVertexRepack converter)
    : super(nativeVertexRepack: converter);

  @override
  GpuBufferEntry uploadCachedBuffer(
    Uint8List bytes, {
    bool isFillExtrusion = false,
  }) => _CopiedEntry(Uint8List.fromList(bytes));
}

class _CopiedEntry extends Fake implements GpuBufferEntry {
  _CopiedEntry(this.bytes);

  final Uint8List bytes;

  @override
  var lastUsed = 0;

  @override
  int get lengthInBytes => bytes.lengthInBytes;

  @override
  void releasePooledAllocation(int frame) {}
}

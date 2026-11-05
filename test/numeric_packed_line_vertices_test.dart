import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/pipeline_key.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache_keys.dart';
import 'package:maplibre_flutter_gpu/src/gpu/vertex_staging.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/native/vertex_repack.dart';

const _packedEnabled = bool.fromEnvironment('MAPLIBRE_PACKED_LINE_VERTICES');
const _nativeEnabled = bool.fromEnvironment(
  'MAPLIBRE_NATIVE_REPACKING',
  defaultValue: true,
);
const _nativeLibrary = String.fromEnvironment(
  'MAPLIBRE_VERTEX_REPACK_TEST_LIBRARY',
);

const _variants = [
  (
    ShaderType.line,
    RenderPipelineKey.line,
    RenderPipelineKey.linePacked,
    RenderPipelineKey.lineDataDriven,
  ),
  (
    ShaderType.lineSDF,
    RenderPipelineKey.lineSdf,
    RenderPipelineKey.lineSdfPacked,
    RenderPipelineKey.lineSdfDataDriven,
  ),
  (
    ShaderType.lineGradient,
    RenderPipelineKey.lineGradient,
    RenderPipelineKey.lineGradientPacked,
    RenderPipelineKey.lineGradientDataDriven,
  ),
  (
    ShaderType.linePattern,
    RenderPipelineKey.linePattern,
    RenderPipelineKey.linePatternPacked,
    RenderPipelineKey.linePatternDataDriven,
  ),
  (
    ShaderType.fillOutlineTriangulated,
    RenderPipelineKey.fillOutlineTriangulated,
    RenderPipelineKey.fillOutlineTriangulatedPacked,
    RenderPipelineKey.fillOutlineTriangulatedDataDriven,
  ),
];

Uint8List _pack(
  Uint8List source, {
  Uint8List? destination,
  int shader = ShaderType.line,
}) => repackVertexDataForGpu(
  source,
  vertexCount: source.length ~/ 8,
  sourceStride: 8,
  shader: shader,
  flags: 0,
  destination: destination,
);

// Division recovers bytes independently of the encoder's shifts and masks.
Uint8List _decode(Uint8List packed) {
  final data = ByteData.sublistView(packed);
  final restored = Uint8List(packed.length ~/ 12 * 8);
  for (var vertex = 0; vertex < restored.length ~/ 8; vertex++) {
    for (var chunk = 0; chunk < 3; chunk++) {
      final value = data.getFloat32(vertex * 12 + chunk * 4, Endian.little);
      expect(value.isFinite, isTrue);
      expect(value, value.floorToDouble());
      expect(value, inInclusiveRange(0, chunk == 2 ? 65535 : 16777215));
      var remaining = value.toInt();
      for (var byte = 0; byte < (chunk == 2 ? 2 : 3); byte++) {
        restored[vertex * 8 + chunk * 3 + byte] = remaining % 256;
        remaining ~/= 256;
      }
      expect(remaining, 0);
    }
  }
  return restored;
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('flag and platform select only constant native line layouts', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final enabled = _packedEnabled && platform == TargetPlatform.android;
      for (final (shader, originalKey, packedKey, ddKey) in _variants) {
        final outline = shader == ShaderType.fillOutlineTriangulated;
        expect(lineUsesPackedFloatVertices(shader, 0), enabled);
        expect(gpuVertexStride(shader, 0), enabled ? 12 : 24);
        expect(
          pipelineKeyFor(shader: shader, flags: 0),
          enabled ? packedKey : originalKey,
        );
        for (final flag in [
          DrawCommandFlags.crossTileMerged,
          DrawCommandFlags.lineGpuReady,
        ]) {
          expect(lineUsesPackedFloatVertices(shader, flag), isFalse);
          expect(gpuVertexStride(shader, flag), 24);
          expect(pipelineKeyFor(shader: shader, flags: flag), originalKey);
        }
        for (var bit = outline ? 20 : 12; bit <= (outline ? 21 : 19); bit++) {
          final flags = 1 << bit;
          expect(lineUsesPackedFloatVertices(shader, flags), isFalse);
          expect(gpuVertexStride(shader, flags), outline ? 48 : 120);
          expect(pipelineKeyFor(shader: shader, flags: flags), ddKey);
        }
      }
      for (final shader in [
        ShaderType.fill,
        ShaderType.fillOutline,
        ShaderType.fillExtrusion,
        ShaderType.circle,
        ShaderType.raster,
      ]) {
        expect(lineUsesPackedFloatVertices(shader, 0), isFalse);
      }
      expect(lineVertexStride(0), 8);
      expect(fillOutlineVertexStride(0), 8);
      expect(lineVertexStride(DrawCommandFlags.lineGpuReady), 24);
      expect(lineVertexStride(DrawCommandFlags.lineWidthDataDriven), 88);
      expect(
        lineVertexStride(
          DrawCommandFlags.lineWidthDataDriven | DrawCommandFlags.lineGpuReady,
        ),
        120,
      );
      expect(
        fillOutlineVertexStride(DrawCommandFlags.fillOutlineColorDataDriven),
        32,
      );
    }
  });

  for (final (shader, _, _, _) in _variants) {
    test('shader $shader preserves every byte at unaligned source offsets', () {
      for (var offset = 0; offset <= 4; offset++) {
        final storage = Uint8List(offset + 8 * 257);
        final source = Uint8List.sublistView(storage, offset);
        for (var index = 0; index < source.length; index++) {
          source[index] = (index * 131 + index ~/ 7 + 255) % 256;
        }
        final output = _pack(source, shader: shader);
        expect(output.length, 12 * 257);
        expect(_decode(output), orderedEquals(source));
      }
    }, skip: !_packedEnabled);

    test('shader $shader uses layout four and exact old-binary fallback', () {
      final source = calloc<Uint8>(8 * 257);
      addTearDown(() => calloc.free(source));
      final input = source.asTypedList(8 * 257);
      for (var index = 0; index < input.length; index++) {
        input[index] = (index * 37 + index ~/ 3 + 128) % 256;
      }
      for (final converter in <NativeVertexRepack?>[
        null,
        (_, _, _, _, _, _) => 0,
        if (_nativeLibrary.isNotEmpty)
          lookupNativeVertexRepack(DynamicLibrary.open(_nativeLibrary)),
      ]) {
        var calls = 0;
        final staging = VertexUploadStaging(
          nativeRepack: converter == null
              ? null
              : (layout, source, length, count, destination, capacity) {
                  expect(layout, 4);
                  calls++;

                  return converter(
                    layout,
                    source,
                    length,
                    count,
                    destination,
                    capacity,
                  );
                },
        );
        addTearDown(staging.clear);
        final output = staging.consume(
          sourceAddress: source.address,
          vertexCount: 257,
          sourceStride: 8,
          shader: shader,
          flags: 0,
          upload: Uint8List.fromList,
        );
        expect(_decode(output), orderedEquals(input));
        expect(output, orderedEquals(_pack(input, shader: shader)));
        expect(calls, converter != null && _nativeEnabled ? 1 : 0);
      }
    }, skip: !_packedEnabled);
  }

  test('cache identity distinguishes numeric packed and expanded buffers', () {
    GpuVertexBufferCacheKey key(int stride) => (
      bufferId: 17,
      bufferVersion: 1,
      dataAddress: 128,
      vertexCount: 4,
      sourceStride: 8,
      shader: ShaderType.line,
      gpuStride: stride,
    );
    expect(
      gpuCanonicalVertexBufferCacheKey(key(12)),
      isNot(gpuCanonicalVertexBufferCacheKey(key(24))),
    );
  });

  test(
    'Dart encoding preserves bytes for unaligned views and independent outputs',
    () {
      for (var offset = 0; offset <= 4; offset++) {
        for (final count in [0, 1, 7, 257]) {
          final storage = Uint8List(offset + count * 8 + 5);
          final source = Uint8List.sublistView(
            storage,
            offset,
            offset + count * 8,
          );
          for (var index = 0; index < source.length; index++) {
            source[index] = (index * 79 + index ~/ 7 + 255) % 256;
          }
          final output = _pack(source);
          expect(output.length, count * 12);
          expect(_decode(output), orderedEquals(source));
          final before = Uint8List.fromList(output);
          source.fillRange(0, source.length, 0);
          _pack(source);
          expect(output, orderedEquals(before));
        }
      }
    },
    skip: !_packedEnabled,
  );

  test(
    'every signed position value and byte extreme survives float32 storage',
    () {
      final source = Uint8List(65536 * 8);
      final sourceData = ByteData.sublistView(source);
      for (var value = 0; value <= 65535; value++) {
        final offset = value * 8;
        sourceData.setUint16(offset, value, Endian.little);
        sourceData.setUint16(offset + 2, 65535 - value, Endian.little);
        source[offset + 4] = value % 256;
        source[offset + 5] = value ~/ 256;
        source[offset + 6] = 0;
        source[offset + 7] = 255;
      }
      final restored = _decode(_pack(source));
      expect(restored, orderedEquals(source));
      final restoredData = ByteData.sublistView(restored);
      for (var value = 0; value <= 65535; value++) {
        expect(
          restoredData.getInt16(value * 8, Endian.little),
          value < 32768 ? value : value - 65536,
        );
        expect(
          restoredData.getInt16(value * 8 + 2, Endian.little),
          value > 32767 ? 65535 - value : -1 - value,
        );
      }
      final extremes = Uint8List(8)..fillRange(0, 8, 255);
      expect(
        Float32List.sublistView(_pack(extremes)),
        orderedEquals([16777215.0, 16777215.0, 65535.0]),
      );
      expect(
        Float32List.sublistView(
          _pack(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
        ),
        orderedEquals([197121.0, 394500.0, 2055.0]),
      );
    },
    skip: !_packedEnabled,
  );

  test('explicit destination keeps adjacent bytes and rejects overlap', () {
    final source = Uint8List.fromList(List.generate(24, (index) => index + 1));
    final storage = Uint8List(48)..fillRange(0, 48, 0xa5);
    final destination = Uint8List.sublistView(storage, 4, 44);
    final output = _pack(source, destination: destination);
    expect(output.length, 36);
    expect(output.buffer, destination.buffer);
    expect(output.offsetInBytes, 4);
    expect(_decode(output), orderedEquals(source));
    expect(storage.sublist(0, 4), everyElement(0xa5));
    expect(storage.sublist(40), everyElement(0xa5));
    expect(
      () => _pack(source, destination: Uint8List(35)),
      throwsArgumentError,
    );
    expect(
      () => _pack(source, destination: Uint8List.sublistView(storage, 1)),
      throwsArgumentError,
    );
    expect(
      () => _pack(
        Uint8List.sublistView(storage, 4, 28),
        destination: destination,
      ),
      throwsArgumentError,
    );
  }, skip: !_packedEnabled);

  test(
    'layout four success and old-binary fallback share scoped native storage',
    () {
      final source = calloc<Uint8>(16);
      addTearDown(() => calloc.free(source));
      source
          .asTypedList(16)
          .setAll(0, List.generate(16, (index) => index * 17));
      var status = 1;
      final addresses = <int>[];
      final staging = VertexUploadStaging(
        nativeRepack: (layout, input, inputBytes, count, output, capacity) {
          expect(layout, 4);
          expect(input.address, source.address);
          expect(inputBytes, 16);
          expect(count, 2);
          expect(capacity, greaterThanOrEqualTo(24));
          addresses.add(output.address);
          final outputData = ByteData.sublistView(
            output.cast<Uint8>().asTypedList(capacity),
          );
          if (status == 0) {
            output
                .cast<Uint8>()
                .asTypedList(capacity)
                .fillRange(0, capacity, 0xff);

            return 0;
          }
          final inputData = source.asTypedList(16);
          for (var vertex = 0; vertex < count; vertex++) {
            for (var chunk = 0; chunk < 3; chunk++) {
              var value = 0;
              var factor = 1;
              for (var byte = 0; byte < (chunk == 2 ? 2 : 3); byte++) {
                value += inputData[vertex * 8 + chunk * 3 + byte] * factor;
                factor *= 256;
              }
              outputData.setFloat32(
                vertex * 12 + chunk * 4,
                value.toDouble(),
                Endian.little,
              );
            }
          }
          return 1;
        },
      );
      addTearDown(staging.clear);
      Uint8List consume() => staging.consume(
        sourceAddress: source.address,
        vertexCount: 2,
        sourceStride: 8,
        shader: ShaderType.line,
        flags: 0,
        upload: (bytes) {
          expect(staging.activeBytes, greaterThanOrEqualTo(bytes.length));
          expect(_decode(bytes), orderedEquals(source.asTypedList(16)));

          return Uint8List.fromList(bytes);
        },
      );
      final native = consume();
      status = 0;
      final fallback = consume();
      expect(fallback, orderedEquals(native));
      expect(fallback, orderedEquals(_pack(source.asTypedList(16))));
      expect(addresses, hasLength(2));
      expect(addresses[0], addresses[1]);
      expect(staging.activeBytes, 0);
    },
    skip: !_packedEnabled || !_nativeEnabled,
  );

  test('actual optional ABI emits identical twelve-byte records', () {
    final native = lookupNativeVertexRepack(
      DynamicLibrary.open(_nativeLibrary),
    );
    expect(native, isNotNull);
    final source = calloc<Uint8>(8 * 257 + 4);
    addTearDown(() => calloc.free(source));
    for (var offset = 0; offset <= 3; offset++) {
      final input = source + offset;
      final bytes = input.asTypedList(8 * 257);
      for (var index = 0; index < bytes.length; index++) {
        bytes[index] = (index * 131 + 255) % 256;
      }
      var calls = 0;
      final staging = VertexUploadStaging(
        nativeRepack: (layout, source, length, count, destination, capacity) {
          expect(layout, 4);
          final result = native!(
            layout,
            source,
            length,
            count,
            destination,
            capacity,
          );
          expect(result, 1);
          calls++;

          return result;
        },
      );
      addTearDown(staging.clear);
      final output = staging.consume(
        sourceAddress: input.address,
        vertexCount: 257,
        sourceStride: 8,
        shader: ShaderType.line,
        flags: 0,
        upload: Uint8List.fromList,
      );
      expect(calls, 1);
      expect(output, orderedEquals(_pack(bytes)));
      expect(_decode(output), orderedEquals(bytes));
    }
  }, skip: !_packedEnabled || !_nativeEnabled || _nativeLibrary.isEmpty);
}

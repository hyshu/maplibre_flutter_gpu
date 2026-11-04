import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/gpu/command_resources.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

Uint8List repackExtrusion(Uint8List source, {VertexRepackScratch? scratch}) =>
    repackVertexDataForGpu(
      source,
      vertexCount: source.length ~/ 12,
      sourceStride: 12,
      shader: ShaderType.fillExtrusion,
      flags: 0,
      scratch: scratch,
    );

void main() {
  test('scratch output matches owned output across layouts and alignment', () {
    final scratch = VertexRepackScratch();
    const layouts = [
      (shader: ShaderType.fillExtrusion, stride: 12, flags: 0),
      (
        shader: ShaderType.fillExtrusion,
        stride: 44,
        flags: DrawCommandFlags.fillExtrusionDataDriven,
      ),
      (shader: ShaderType.line, stride: 8, flags: 0),
      (
        shader: ShaderType.line,
        stride: 88,
        flags: DrawCommandFlags.lineColorDataDriven,
      ),
      (shader: ShaderType.fill, stride: 4, flags: 0),
      (
        shader: ShaderType.fill,
        stride: 28,
        flags: DrawCommandFlags.fillColorDataDriven,
      ),
      (shader: ShaderType.fillOutlineTriangulated, stride: 8, flags: 0),
      (
        shader: ShaderType.fillOutlineTriangulated,
        stride: 32,
        flags: DrawCommandFlags.fillOutlineColorDataDriven,
      ),
      (shader: ShaderType.raster, stride: 8, flags: 0),
    ];
    for (final layout in layouts) {
      for (final offset in [0, 1]) {
        for (final count in [13, 2, 0]) {
          final storage = Uint8List(layout.stride * count + offset);
          final source = Uint8List.sublistView(storage, offset);
          for (var index = 0; index < source.length; index++) {
            source[index] = (index * 53 + count * 17) & 0xff;
          }
          Uint8List convert(VertexRepackScratch? staging) =>
              repackVertexDataForGpu(
                source,
                vertexCount: count,
                sourceStride: layout.stride,
                shader: layout.shader,
                flags: layout.flags,
                scratch: staging,
              );
          final owned = convert(null);
          final borrowed = convert(scratch);
          expect(
            borrowed,
            orderedEquals(owned),
            reason: '$layout/$offset/$count',
          );
          borrowed.fillRange(0, borrowed.length, 0xff);
          expect(convert(scratch), orderedEquals(owned));
        }
      }
    }
  });

  test('default repacks stay owned while scratch results are borrowed', () {
    final scratch = VertexRepackScratch();
    final source = Uint8List(24)..fillRange(0, 24, 3);
    final owned = repackExtrusion(source);
    final ownedCopy = Uint8List.fromList(owned);
    final borrowed = repackExtrusion(source, scratch: scratch);
    source.fillRange(0, source.length, 7);
    final next = repackExtrusion(source, scratch: scratch);
    expect(borrowed, orderedEquals(next));
    expect(borrowed, isNot(orderedEquals(ownedCopy)));
    expect(owned, orderedEquals(ownedCopy));
  });

  test('oversize outputs do not grow scratch or alias retained output', () {
    final scratch = VertexRepackScratch(maxRetainedBytes: 96);
    final first = repackExtrusion(Uint8List(24), scratch: scratch);
    expect(scratch.retainedBytes, 96);
    final large = repackExtrusion(Uint8List(60), scratch: scratch);
    expect(large.length, 120);
    expect(scratch.retainedBytes, 96);
    large.fillRange(0, large.length, 0xff);
    expect(first, everyElement(0));
    final source = Uint8List(24)..fillRange(0, 24, 7);
    repackExtrusion(source, scratch: scratch);
    expect(large, everyElement(0xff));
    final beforeClear = Uint8List.fromList(first);
    scratch.clear();
    expect(scratch.retainedBytes, 0);
    repackExtrusion(Uint8List(24), scratch: scratch);
    expect(first, orderedEquals(beforeClear));
  });

  test('matching layouts bypass scratch and retain the source view', () {
    final scratch = VertexRepackScratch();
    final source = Uint8List(24);
    expect(
      repackVertexDataForGpu(
        source,
        vertexCount: 1,
        sourceStride: 24,
        shader: ShaderType.fillExtrusion,
        flags: 0,
        scratch: scratch,
      ),
      same(source),
    );
    expect(scratch.retainedBytes, 0);
  });

  test('unaligned retention limits preserve aligned output views', () {
    final scratch = VertexRepackScratch(maxRetainedBytes: 25);
    final source = Uint8List(12)..fillRange(0, 12, 3);
    final owned = repackExtrusion(source);
    final borrowed = repackExtrusion(source, scratch: scratch);
    expect(borrowed, orderedEquals(owned));
    expect(scratch.retainedBytes, 25);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform uploads own their data before later repacks and trim', () {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final cache = _CopyingResourceCache();
      addTearDown(cache.dispose);
      final resources = GpuCommandResources(cache);
      final native = calloc<Uint8>(24);
      addTearDown(() => calloc.free(native));
      final source = native.asTypedList(24);
      GpuBufferEntry upload(int id) => resources.cachedVertexBuffer(
        id,
        1,
        native.address,
        2,
        12,
        ShaderType.fillExtrusion,
        0,
      );
      source.fillRange(0, source.length, 3);
      final first = upload(1) as _CopiedEntry;
      final firstExpected = Uint8List.fromList(first.bytes);
      source.fillRange(0, source.length, 7);
      final second = upload(2) as _CopiedEntry;
      expect(first.bytes, orderedEquals(firstExpected));
      expect(second.bytes, isNot(orderedEquals(firstExpected)));
      expect(upload(1), same(first));
      expect(cache.inputs, hasLength(2));
      if (platform == TargetPlatform.android) {
        expect(cache.inputs.first, orderedEquals(second.bytes));
      } else {
        expect(cache.inputs.first, orderedEquals(firstExpected));
      }
      final lastInput = cache.inputs.last;
      final beforeTrim = Uint8List.fromList(lastInput);
      cache.reduceMemoryUse();
      source.fillRange(0, source.length, 11);
      upload(3);
      expect(lastInput, orderedEquals(beforeTrim));
      expect(first.bytes, orderedEquals(firstExpected));
    });
  }
}

class _CopyingResourceCache extends GpuResourceCache {
  final inputs = <Uint8List>[];

  @override
  GpuBufferEntry uploadCachedBuffer(
    Uint8List bytes, {
    bool isFillExtrusion = false,
  }) {
    inputs.add(bytes);

    return _CopiedEntry(Uint8List.fromList(bytes));
  }
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

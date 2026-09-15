import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/command_decoder.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';

class _UnusedResourceCache extends Fake implements GpuResourceCache {}

void main() {
  late GpuCommandDecoder decoder;
  late Pointer<Uint8> commands;

  setUp(() {
    decoder = GpuCommandDecoder(_UnusedResourceCache());
    commands = calloc<Uint8>(DrawCommandAbi.size * 2);
  });

  tearDown(() {
    decoder.dispose();
    calloc.free(commands);
  });

  FrameCommandMetadata metadata({int count = 1, int? stride}) => (
    commands: commands.cast<Void>(),
    commandCount: count,
    commandStride: stride ?? DrawCommandAbi.size,
    clearColor: null,
  );

  test('stable native command blocks reuse borrowed typed views', () {
    final first = decoder.commandView(metadata(), shouldLog: false)!;
    final again = decoder.commandView(metadata(), shouldLog: false)!;

    expect(identical(first.commandBytes, again.commandBytes), isTrue);
    expect(identical(first.commandData, again.commandData), isTrue);
    commands[DrawCommandAbi.layerIndex] = 7;
    expect(
      again.commandData.getUint32(DrawCommandAbi.layerIndex, Endian.little),
      7,
    );

    final resized = decoder.commandView(metadata(count: 2), shouldLog: false)!;
    expect(resized.commandBytes.length, DrawCommandAbi.size * 2);
    expect(identical(first.commandBytes, resized.commandBytes), isFalse);
  });

  test('invalid native blocks discard their previous borrowed views', () {
    for (final invalid in <FrameCommandMetadata>[
      metadata(count: 0),
      metadata(stride: DrawCommandAbi.size - 1),
      (
        commands: nullptr,
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
        clearColor: null,
      ),
    ]) {
      final first = decoder.commandView(metadata(), shouldLog: false)!;

      expect(decoder.commandView(invalid, shouldLog: false), isNull);
      final restored = decoder.commandView(metadata(), shouldLog: false)!;
      expect(identical(first.commandBytes, restored.commandBytes), isFalse);
      expect(restored.commandCount, 1);
    }
  });

  test('topology reset reuses entries and clears command uniform ranges', () {
    final first = decoder.acquireDrawEntry(
      0,
      ShaderType.fill,
      DrawModeType.triangles,
      0,
      3,
      4,
      6,
      null,
      null,
      null,
      TextureFilterType.linear,
      2,
      StencilModeType.clippingTest,
      1,
    );
    decoder.entries.add(first);
    first.drawableUniformOffset = 256;
    first.propsUniformLength = 64;
    first.fillExtrusionOpacity = 0.5;

    decoder.resetEntries();
    expect(decoder.entries, isEmpty);
    final reused = decoder.acquireDrawEntry(
      DrawCommandAbi.size,
      ShaderType.line,
      DrawModeType.triangles,
      0,
      8,
      7,
      9,
      null,
      null,
      null,
      TextureFilterType.nearest,
      4,
      StencilModeType.clippingTest,
      2,
    );

    expect(identical(first, reused), isTrue);
    expect(reused.commandOffset, DrawCommandAbi.size);
    expect(reused.shader, ShaderType.line);
    expect(reused.layer, 8);
    expect(reused.vertexCount, 7);
    expect(reused.indexCount, 9);
    expect(reused.stencilReference, 4);
    expect(reused.subLayerIndex, 2);
    expect(reused.drawableUniformOffset, 0);
    expect(reused.propsUniformLength, 0);
    expect(reused.fillExtrusionOpacity, 1);
  });
}

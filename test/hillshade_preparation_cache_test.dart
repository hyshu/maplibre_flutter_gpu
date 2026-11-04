import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/hillshade_preparation_cache.dart';
import 'package:maplibre_flutter_gpu/src/frame/uniform_packer.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/compact_command.dart';

TestCommand _command({
  int drawableSize = 64,
  int propsSize = 0,
  int tilePropsSize = 32,
}) {
  final command = TestCommand(
    drawableSize: drawableSize,
    propsSize: propsSize,
    tilePropsSize: tilePropsSize,
    sections:
        CommandPayloadSections.texture |
        CommandPayloadSections.renderTarget |
        CommandPayloadSections.stencil,
  );
  command.data
    ..setUint32(DrawCommandAbi.shaderType, ShaderType.hillshadePrepare, .little)
    ..setUint32(DrawCommandAbi.drawMode, DrawModeType.triangles, .little)
    ..setUint32(DrawCommandAbi.vertexCount, 4, .little)
    ..setUint32(DrawCommandAbi.indexCount, 6, .little)
    ..setUint32(DrawCommandAbi.vertexStride, 8, .little)
    ..setUint32(DrawCommandAbi.bufferId, 11, .little)
    ..setUint32(DrawCommandAbi.bufferVersion, 2, .little)
    ..setUint64(DrawCommandAbi.vertexData, 0xb400000000001000, .little)
    ..setUint64(DrawCommandAbi.indexData, 0xb400000000002000, .little);
  final texture = command.textureOffset;
  command.payloadData
    ..setUint64(texture + CommandTextureAbi.data, 0xb400000000003000, .little)
    ..setUint32(texture + CommandTextureAbi.width, 258, .little)
    ..setUint32(texture + CommandTextureAbi.height, 258, .little)
    ..setUint32(texture + CommandTextureAbi.id, 31, .little)
    ..setUint32(texture + CommandTextureAbi.version, 1, .little)
    ..setUint32(texture + CommandTextureAbi.channels, 4, .little)
    ..setUint32(
      texture + CommandTextureAbi.filter,
      TextureFilterType.nearest,
      .little,
    );
  if (drawableSize == 64 && tilePropsSize == 32) {
    for (var i = 0; i < 16; i++) {
      command.payloadData.setFloat32(
        command.drawableOffset + i * 4,
        i % 5 == 0 ? 1 : 0,
        .little,
      );
    }
    final values = [6553.6, 25.6, 0.1, 10000.0, 258.0, 258.0, 12.0, 14.0];
    for (var i = 0; i < values.length; i++) {
      command.payloadData.setFloat32(
        command.tilePropsOffset + i * 4,
        values[i],
        .little,
      );
    }
  }

  return command;
}

HillshadePreparationResources? _resources(TestCommand command) =>
    HillshadePreparationResources.capture(command.data, 0, command.reader);

ByteData _pack(TestCommand command) {
  final storage = Uint8List(256);
  final bytes = Uint8List.sublistView(storage, 7, 247);
  final data = ByteData.sublistView(bytes);
  packCommandUniforms(
    payload: command.reader,
    destination: bytes,
    destinationData: data,
    shader: ShaderType.hillshadePrepare,
    flags: 0,
    drawableOffset: 16,
    drawableLength: 64,
    propsOffset: 80,
    propsLength: 0,
    tilePropsOffset: 128,
    tilePropsLength: 32,
    devicePixelRatio: 2,
    textureWidth: 258,
    textureHeight: 258,
  );

  return data;
}

HillshadePreparationKey _key({
  TestCommand? command,
  ByteData? uniforms,
  int target = 10,
  int width = 256,
  int height = 256,
}) {
  final source = command ?? _command();

  return HillshadePreparationKey.capture(
    targetId: target,
    width: width,
    height: height,
    resources: _resources(source)!,
    uniforms: uniforms ?? _pack(source),
    drawableOffset: 16,
    drawableLength: 64,
    propsLength: 0,
    tilePropsOffset: 128,
    tilePropsLength: 32,
  )!;
}

void main() {
  test('compiled setting is restricted to Android', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const enabled = bool.fromEnvironment(
      'MAPLIBRE_CACHE_HILLSHADE_PREPARATION',
      defaultValue: true,
    );
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        hillshadePreparationCachingEnabled,
        enabled && platform == TargetPlatform.android,
        reason: platform.name,
      );
    }
  });

  test('keys own copied uniforms and native scalar identities', () {
    final command = _command();
    final uniforms = _pack(command);
    final captured = _key(command: command, uniforms: uniforms);
    expect(captured.matches(_key()), isTrue);

    command.bytes.fillRange(0, command.bytes.length, 0);
    command.payload.fillRange(0, command.payload.length, 0);
    uniforms.buffer.asUint8List().fillRange(0, 256, 0xff);
    expect(captured.matches(_key()), isTrue);
  });

  test('every versioned geometry and DEM input can invalidate a key', () {
    final original = _key();
    for (final mutate in <void Function(TestCommand)>[
      (c) => c.data.setUint32(DrawCommandAbi.bufferId, 12, .little),
      (c) => c.data.setUint32(DrawCommandAbi.bufferVersion, 3, .little),
      (c) => c.data.setUint64(DrawCommandAbi.vertexData, 0x4000, .little),
      (c) => c.data.setUint64(DrawCommandAbi.indexData, 0x5000, .little),
      (c) => c.payloadData.setUint32(
        c.textureOffset + CommandTextureAbi.id,
        32,
        .little,
      ),
      (c) => c.payloadData.setUint32(
        c.textureOffset + CommandTextureAbi.version,
        2,
        .little,
      ),
      (c) => c.payloadData.setUint32(
        c.textureOffset + CommandTextureAbi.width,
        514,
        .little,
      ),
      (c) => c.payloadData.setUint32(
        c.textureOffset + CommandTextureAbi.height,
        514,
        .little,
      ),
      (c) => c.payloadData.setUint32(
        c.textureOffset + CommandTextureAbi.filter,
        TextureFilterType.linear,
        .little,
      ),
    ]) {
      final command = _command();
      mutate(command);
      expect(original.matches(_key(command: command)), isFalse);
    }
    expect(original.matches(_key(target: 11)), isFalse);
    expect(original.matches(_key(width: 512)), isFalse);
    expect(original.matches(_key(height: 512)), isFalse);

    final relocated = _command();
    relocated.payloadData.setUint64(
      relocated.textureOffset + CommandTextureAbi.data,
      0x6000,
      .little,
    );
    expect(original.matches(_key(command: relocated)), isTrue);
  });

  test('exact packed blocks include edge bytes and opaque float bits', () {
    for (final offset in [16, 79, 128, 159]) {
      final uniforms = _pack(_command());
      final original = _key(uniforms: uniforms);
      uniforms.setUint8(offset, uniforms.getUint8(offset) ^ 1);
      expect(original.matches(_key(uniforms: uniforms)), isFalse);
    }
    for (final bits in [0x7fc00001, 0x7fc00002, 0x80000000]) {
      final uniforms = _pack(_command());
      uniforms.setUint32(128, bits, .little);
      final original = _key(uniforms: uniforms);
      expect(original.matches(_key(uniforms: uniforms)), isTrue);
      uniforms.setUint32(128, 0, .little);
      expect(original.matches(_key(uniforms: uniforms)), isFalse);
    }
    final uniforms = _pack(_command());
    final original = _key(uniforms: uniforms);
    uniforms.setUint8(100, 255);
    expect(original.matches(_key(uniforms: uniforms)), isTrue);
  });

  test('unsupported commands cannot become cached preparation inputs', () {
    for (final (field, value) in [
      (DrawCommandAbi.shaderType, ShaderType.heatmap),
      (DrawCommandAbi.shaderType, ShaderType.hillshade),
      (DrawCommandAbi.drawMode, DrawModeType.lines),
      (DrawCommandAbi.flags, 1),
      (DrawCommandAbi.vertexCount, 8),
      (DrawCommandAbi.indexCount, 12),
      (DrawCommandAbi.vertexStride, 16),
      (DrawCommandAbi.bufferId, 0),
      (DrawCommandAbi.bufferVersion, 0),
    ]) {
      final command = _command();
      command.data.setUint32(field, value, .little);
      expect(_resources(command), isNull, reason: 'field $field');
    }
    for (final field in [DrawCommandAbi.vertexData, DrawCommandAbi.indexData]) {
      final command = _command();
      command.data.setUint64(field, 0, .little);
      expect(_resources(command), isNull);
    }
    for (final (field, value) in [
      (CommandTextureAbi.id, 0),
      (CommandTextureAbi.version, 0),
      (CommandTextureAbi.width, 0),
      (CommandTextureAbi.height, 0),
      (CommandTextureAbi.channels, 1),
    ]) {
      final command = _command();
      command.payloadData.setUint32(
        command.textureOffset + field,
        value,
        .little,
      );
      expect(_resources(command), isNull);
    }
    expect(_resources(_command(drawableSize: 80)), isNull);
    expect(_resources(_command(propsSize: 16)), isNull);
    expect(_resources(_command(tilePropsSize: 16)), isNull);
    final clipped = _command();
    clipped.payloadData.setUint32(
      clipped.stencilOffset + CommandStencilAbi.mode,
      StencilModeType.clippingTest,
      .little,
    );
    expect(_resources(clipped), isNull);
  });

  test('invalid packed block ranges decline reuse', () {
    for (final (
          drawableOffset,
          drawableLength,
          propsLength,
          tileOffset,
          tileLength,
        )
        in [
          (-1, 64, 0, 128, 32),
          (177, 64, 0, 128, 32),
          (16, 80, 0, 128, 32),
          (16, 64, 16, 128, 32),
          (16, 64, 0, -1, 32),
          (16, 64, 0, 209, 32),
          (16, 64, 0, 128, 16),
        ]) {
      expect(
        HillshadePreparationKey.capture(
          targetId: 10,
          width: 256,
          height: 256,
          resources: _resources(_command())!,
          uniforms: _pack(_command()),
          drawableOffset: drawableOffset,
          drawableLength: drawableLength,
          propsLength: propsLength,
          tilePropsOffset: tileOffset,
          tilePropsLength: tileLength,
        ),
        isNull,
      );
    }
  });

  test(
    'pending, failed and cancelled writes never produce reusable contents',
    () {
      final cache = HillshadePreparationCache()..replaceTarget(10);
      final key = _key();
      expect(cache.canReuse(key), isFalse);
      final pending = cache.beginWrite(key);
      expect(cache.canReuse(key), isFalse);
      cache.complete(pending, false);
      expect(cache.canReuse(key), isFalse);
      cache.complete(pending, true);
      expect(cache.canReuse(key), isFalse);

      final cancelled = cache.beginWrite(key);
      cache.cancel(cancelled);
      cache.complete(cancelled, true);
      expect(cache.canReuse(key), isFalse);

      final successful = cache.beginWrite(key);
      cache.complete(successful, true);
      expect(cache.canReuse(_key()), isTrue);
      expect(cache.canReuse(_key(width: 512)), isFalse);
    },
  );

  test('only the latest write can publish or invalidate a target', () {
    final cache = HillshadePreparationCache()..replaceTarget(10);
    final original = _key();
    final changed = _key(width: 512);
    final older = cache.beginWrite(original);
    final latest = cache.beginWrite(changed);
    cache.complete(older, true);
    expect(cache.canReuse(original), isFalse);
    expect(cache.canReuse(changed), isFalse);
    cache.complete(latest, true);
    expect(cache.canReuse(changed), isTrue);
    cache.complete(older, false);
    cache.cancel(older);
    expect(cache.canReuse(changed), isTrue);

    final failedReplacement = cache.beginWrite(original);
    expect(cache.canReuse(changed), isFalse);
    cache.complete(failedReplacement, false);
    expect(cache.canReuse(changed), isFalse);
  });

  test(
    'replacement, removal, unsupported work and trim reject old callbacks',
    () {
      for (final invalidate in <void Function(HillshadePreparationCache)>[
        (cache) => cache.replaceTarget(10),
        (cache) {
          cache.retainTargets({20});
          cache.replaceTarget(10);
        },
        (cache) => cache.invalidate(10),
        (cache) {
          cache.clear();
          cache.replaceTarget(10);
        },
      ]) {
        final cache = HillshadePreparationCache()..replaceTarget(10);
        final key = _key();
        final old = cache.beginWrite(key);
        invalidate(cache);
        cache.complete(old, true);
        expect(cache.canReuse(key), isFalse);
        final current = cache.beginWrite(key);
        cache.complete(current, true);
        cache.complete(old, false);
        expect(cache.canReuse(key), isTrue);
      }
    },
  );

  test(
    'independent active targets retain only their own completed contents',
    () {
      final cache = HillshadePreparationCache()
        ..replaceTarget(10)
        ..replaceTarget(20);
      final first = _key();
      final second = _key(target: 20);
      cache.complete(cache.beginWrite(first), true);
      cache.complete(cache.beginWrite(second), true);
      cache.retainTargets({20});
      expect(cache.canReuse(first), isFalse);
      expect(cache.canReuse(second), isTrue);
      cache.clear();
      expect(cache.canReuse(second), isFalse);
    },
  );

  test(
    'diagnostics count decisions and accepted submissions independently',
    () {
      final cache = HillshadePreparationCache(diagnostics: true)
        ..replaceTarget(10);
      final key = _key();
      expect(cache.canReuse(key), isFalse);
      final write = cache.beginWrite(key);
      cache.recordSubmission();
      expect(cache.canReuse(key), isFalse);
      cache.complete(write, true);
      expect(cache.canReuse(key), isTrue);
      final failed = cache.beginWrite(_key(width: 512));
      cache.recordSubmission();
      cache.complete(failed, false);
      expect(cache.takeSnapshot(), (
        eligible: 3,
        reused: 1,
        rendered: 2,
        invalidated: 1,
        pending: 1,
        completionFailures: 1,
      ));
      expect(cache.takeSnapshot()!.eligible, 0);
      expect(HillshadePreparationCache().takeSnapshot(), isNull);
    },
  );
}

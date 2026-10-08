import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/prepared_graph.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/compact_command.dart';

void main() {
  TestCommand command() {
    final data = TestCommand();
    data.data
      ..setUint32(DrawCommandAbi.shaderType, ShaderType.fill, .little)
      ..setUint32(DrawCommandAbi.drawMode, DrawModeType.triangles, .little)
      ..setUint64(DrawCommandAbi.vertexData, 1, .little)
      ..setUint32(DrawCommandAbi.vertexCount, 4, .little)
      ..setUint32(DrawCommandAbi.vertexStride, 4, .little)
      ..setUint64(DrawCommandAbi.indexData, 2, .little)
      ..setUint32(DrawCommandAbi.indexCount, 6, .little)
      ..setUint32(DrawCommandAbi.layerIndex, 7, .little)
      ..setUint32(DrawCommandAbi.bufferId, 11, .little)
      ..setUint32(DrawCommandAbi.bufferVersion, 3, .little)
      ..setInt32(DrawCommandAbi.subLayerIndex, 2, .little);
    data.payloadData
      ..setUint32(
        data.textureOffset + CommandTextureAbi.filter,
        TextureFilterType.linear,
        .little,
      )
      ..setUint32(
        data.stencilOffset + CommandStencilAbi.mode,
        StencilModeType.disabled,
        .little,
      )
      ..setFloat32(data.drawableOffset, 1, .little)
      ..setFloat32(data.drawableOffset + 20, 1, .little);

    return data;
  }

  PreparedGraphKey capture(TestCommand data, {bool active = true}) => .capture(
    commandBytes: data.bytes,
    payloadBytes: data.payload,
    commandCount: 1,
    commandStride: DrawCommandAbi.size,
    activeCommandOffsets: active ? const [0] : const [],
  );

  bool matches(PreparedGraphKey key, TestCommand data) => key.matches(
    commandBytes: data.bytes,
    payloadBytes: data.payload,
    commandCount: 1,
    commandStride: DrawCommandAbi.size,
  );

  test('dynamic uniforms and stencil references preserve graph identity', () {
    final data = command();
    final key = capture(data);

    data.payloadData
      ..setFloat32(data.drawableOffset, 4, .little)
      ..setFloat32(data.propsOffset, 0.5, .little)
      ..setUint32(
        data.stencilOffset + CommandStencilAbi.reference,
        19,
        .little,
      );

    expect(matches(key, data), isTrue);
  });

  test('geometry and resource changes preserve graph identity', () {
    final data = command();
    final key = capture(data);

    data.data
      ..setUint64(DrawCommandAbi.vertexData, 101, .little)
      ..setUint32(DrawCommandAbi.vertexCount, 8, .little)
      ..setUint64(DrawCommandAbi.indexData, 202, .little)
      ..setUint32(DrawCommandAbi.indexCount, 12, .little)
      ..setUint32(DrawCommandAbi.bufferId, 33, .little)
      ..setUint32(DrawCommandAbi.bufferVersion, 9, .little);
    data.payloadData
      ..setUint32(data.textureOffset + CommandTextureAbi.channels, 4, .little)
      ..setUint64(data.textureOffset + CommandTextureAbi.data, 303, .little)
      ..setUint32(data.textureOffset + CommandTextureAbi.width, 64, .little)
      ..setUint32(data.textureOffset + CommandTextureAbi.height, 32, .little)
      ..setUint32(data.textureOffset + CommandTextureAbi.id, 44, .little)
      ..setUint32(data.textureOffset + CommandTextureAbi.version, 5, .little)
      ..setUint32(
        data.textureOffset + CommandTextureAbi.filter,
        TextureFilterType.nearest,
        .little,
      );

    expect(matches(key, data), isTrue);
  });

  test('pipeline and ordering changes invalidate the graph', () {
    final data = command();
    final key = capture(data);

    data.data.setUint32(DrawCommandAbi.flags, 1 << 2, .little);
    expect(matches(key, data), isFalse);

    data.data
      ..setUint32(DrawCommandAbi.flags, 0, .little)
      ..setUint32(DrawCommandAbi.layerIndex, 8, .little);
    expect(matches(key, data), isFalse);

    data.data
      ..setUint32(DrawCommandAbi.layerIndex, 7, .little)
      ..setInt32(DrawCommandAbi.subLayerIndex, 3, .little);
    expect(matches(key, data), isFalse);
  });

  test('placement admission changes invalidate the graph', () {
    final data = command();
    final key = capture(data);

    data.payloadData
      ..setFloat32(data.drawableOffset, 0, .little)
      ..setFloat32(data.drawableOffset + 20, 0, .little);

    expect(matches(key, data), isFalse);
  });

  test('payload relocation preserves graph identity', () {
    final data = command();
    final key = capture(data);
    final relocated = combineTestCommands([command(), data]);

    expect(
      key.matches(
        commandBytes: relocated.commands.sublist(DrawCommandAbi.size),
        payloadBytes: relocated.payload,
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
      ),
      isTrue,
    );
  });

  test('truncated payload prevents graph reuse', () {
    final data = command();
    final key = capture(data);

    expect(
      key.matches(
        commandBytes: data.bytes,
        payloadBytes: data.payload.sublist(0, data.payload.length - 1),
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
      ),
      isFalse,
    );
  });

  test('post-admission drops prevent unsafe graph reuse', () {
    final data = command();
    final key = capture(data, active: false);

    expect(key.reusable, isFalse);
    expect(matches(key, data), isFalse);
  });

  test('prepared graph retains stable entries and partitions', () {
    final data = command();
    final entries = [1, 2];
    final partitions = [
      [1],
      [2],
    ];
    final graph = PreparedGraph<int, List<int>>(
      key: capture(data),
      entries: entries,
      partitions: partitions,
      uniformAlignment: 256,
      uniformCursor: 512,
      hasMapGlobalUniform: true,
      commandCount: 1,
      lastFillExtrusionLayerIndex: null,
    );

    expect(identical(graph.entries, entries), isTrue);
    expect(identical(graph.partitions, partitions), isTrue);
    expect(graph.uniformCursor, 512);
  });

  test('prepared graph template cache promotes an exact topology match', () {
    final data = command();
    final key = capture(data);
    final cache = PreparedGraphTemplateCache<String>(capacity: 2)
      ..remember(key: key, value: 'fill');

    data.data
      ..setUint64(DrawCommandAbi.vertexData, 100, .little)
      ..setUint32(DrawCommandAbi.bufferVersion, 9, .little);

    final match = cache.takeMatching(
      commandBytes: data.bytes,
      payloadBytes: data.payload,
      commandCount: 1,
      commandStride: DrawCommandAbi.size,
    );

    expect(match?.value, 'fill');
    expect(identical(match?.key, key), isTrue);
    expect(cache.length, 0);
  });

  test('template cache deduplicates the same exact topology', () {
    final first = capture(command());
    final second = capture(command());
    final cache = PreparedGraphTemplateCache<String>(capacity: 2)
      ..remember(key: first, value: 'first')
      ..remember(key: second, value: 'second');

    expect(cache.length, 1);
    expect(
      cache
          .takeMatching(
            commandBytes: command().bytes,
            payloadBytes: command().payload,
            commandCount: 1,
            commandStride: DrawCommandAbi.size,
          )
          ?.value,
      'second',
    );
  });

  test('prepared graph template cache is bounded and ignores unsafe keys', () {
    final drawable = command();
    final dropped = command();
    dropped.payloadData
      ..setFloat32(dropped.drawableOffset, 0, .little)
      ..setFloat32(dropped.drawableOffset + 20, 0, .little);
    final cache = PreparedGraphTemplateCache<String>(capacity: 1)
      ..remember(key: capture(drawable), value: 'draw')
      ..remember(key: capture(dropped, active: false), value: 'drop')
      ..remember(key: capture(command(), active: false), value: 'unsafe');

    expect(cache.length, 1);
    expect(
      cache.takeMatching(
        commandBytes: drawable.bytes,
        payloadBytes: drawable.payload,
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
      ),
      isNull,
    );
    expect(
      cache
          .takeMatching(
            commandBytes: dropped.bytes,
            payloadBytes: dropped.payload,
            commandCount: 1,
            commandStride: DrawCommandAbi.size,
          )
          ?.value,
      'drop',
    );
  });

  test('template cache applies capacity across structural families', () {
    final first = command();
    final second = command()
      ..data.setUint32(DrawCommandAbi.layerIndex, 8, .little);
    final cache = PreparedGraphTemplateCache<String>(capacity: 1)
      ..remember(key: capture(first), value: 'first')
      ..remember(key: capture(second), value: 'second');

    expect(cache.length, 1);
    expect(
      cache.takeMatching(
        commandBytes: first.bytes,
        payloadBytes: first.payload,
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
      ),
      isNull,
    );
    expect(
      cache
          .takeMatching(
            commandBytes: second.bytes,
            payloadBytes: second.payload,
            commandCount: 1,
            commandStride: DrawCommandAbi.size,
          )
          ?.value,
      'second',
    );
  });

  test(
    'prepared graph template cache applies capacity across command counts',
    () {
      final one = command();
      final second = command()
        ..data.setUint32(DrawCommandAbi.layerIndex, 8, .little);
      final two = combineTestCommands([one, second]);
      final twoKey = PreparedGraphKey.capture(
        commandBytes: two.commands,
        payloadBytes: two.payload,
        commandCount: 2,
        commandStride: DrawCommandAbi.size,
        activeCommandOffsets: [0, DrawCommandAbi.size],
      );
      final cache = PreparedGraphTemplateCache<String>(capacity: 1)
        ..remember(key: capture(one), value: 'one')
        ..remember(key: twoKey, value: 'two');

      expect(cache.length, 1);
      expect(
        cache.takeMatching(
          commandBytes: one.bytes,
          payloadBytes: one.payload,
          commandCount: 1,
          commandStride: DrawCommandAbi.size,
        ),
        isNull,
      );
      expect(
        cache
            .takeMatching(
              commandBytes: two.commands,
              payloadBytes: two.payload,
              commandCount: 2,
              commandStride: DrawCommandAbi.size,
            )
            ?.value,
        'two',
      );
      expect(cache.length, 0);
    },
  );

  test(
    'prepared graph template cache rejects a non-positive capacity',
    () => expect(
      () => PreparedGraphTemplateCache<void>(capacity: 0),
      throwsRangeError,
    ),
  );

  test('prepared graph timing metrics aggregate hits and rebuilds', () {
    final metrics = PreparedGraphTimingMetrics()
      ..record(reused: true, micros: 100)
      ..record(reused: true, micros: 300)
      ..record(reused: false, micros: 1200);

    final snapshot = metrics.takeSnapshotAndReset();

    expect(snapshot.hitCount, 2);
    expect(snapshot.rebuildCount, 1);
    expect(snapshot.sampleCount, 3);
    expect(snapshot.hitRate, closeTo(2 / 3, 0.000001));
    expect(snapshot.averageHitMicros, 200);
    expect(snapshot.averageRebuildMicros, 1200);
  });

  test('prepared graph timing snapshots reset the logging interval', () {
    final metrics = PreparedGraphTimingMetrics()
      ..record(reused: true, micros: 75);

    metrics.takeSnapshotAndReset();
    final empty = metrics.takeSnapshotAndReset();

    expect(empty.sampleCount, 0);
    expect(empty.hitRate, 0);
    expect(empty.averageHitMicros, isNull);
    expect(empty.averageRebuildMicros, isNull);
  });
}

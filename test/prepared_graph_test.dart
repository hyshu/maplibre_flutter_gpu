import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/prepared_graph.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  ByteData command() {
    final data = ByteData(DrawCommandAbi.size);
    data
      ..setUint32(DrawCommandAbi.shaderType, ShaderType.fill, Endian.little)
      ..setUint32(
        DrawCommandAbi.drawMode,
        DrawModeType.triangles,
        Endian.little,
      )
      ..setUint64(DrawCommandAbi.vertexData, 1, Endian.little)
      ..setUint32(DrawCommandAbi.vertexCount, 4, Endian.little)
      ..setUint32(DrawCommandAbi.vertexStride, 4, Endian.little)
      ..setUint64(DrawCommandAbi.indexData, 2, Endian.little)
      ..setUint32(DrawCommandAbi.indexCount, 6, Endian.little)
      ..setUint32(DrawCommandAbi.layerIndex, 7, Endian.little)
      ..setUint32(DrawCommandAbi.bufferId, 11, Endian.little)
      ..setUint32(DrawCommandAbi.bufferVersion, 3, Endian.little)
      ..setUint32(
        DrawCommandAbi.texFilter,
        TextureFilterType.linear,
        Endian.little,
      )
      ..setInt32(DrawCommandAbi.subLayerIndex, 2, Endian.little)
      ..setUint32(
        DrawCommandAbi.stencilMode,
        StencilModeType.disabled,
        Endian.little,
      )
      ..setFloat32(DrawCommandAbi.drawableUBO, 1, Endian.little)
      ..setFloat32(DrawCommandAbi.drawableUBO + 20, 1, Endian.little);

    return data;
  }

  PreparedGraphKey capture(ByteData data, {bool active = true}) =>
      PreparedGraphKey.capture(
        commandBytes: data.buffer.asUint8List(),
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
        activeCommandOffsets: active ? const <int>[0] : const <int>[],
      );

  bool matches(PreparedGraphKey key, ByteData data) => key.matches(
    commandBytes: data.buffer.asUint8List(),
    commandCount: 1,
    commandStride: DrawCommandAbi.size,
  );

  test('dynamic uniforms and stencil references preserve graph identity', () {
    final data = command();
    final key = capture(data);

    data
      ..setFloat32(DrawCommandAbi.drawableUBO, 4, Endian.little)
      ..setFloat32(DrawCommandAbi.propsUBO, 0.5, Endian.little)
      ..setUint32(DrawCommandAbi.stencilReference, 19, Endian.little);

    expect(matches(key, data), isTrue);
  });

  test('geometry and resource changes preserve graph identity', () {
    final data = command();
    final key = capture(data);

    data
      ..setUint64(DrawCommandAbi.vertexData, 101, Endian.little)
      ..setUint32(DrawCommandAbi.vertexCount, 8, Endian.little)
      ..setUint64(DrawCommandAbi.indexData, 202, Endian.little)
      ..setUint32(DrawCommandAbi.indexCount, 12, Endian.little)
      ..setUint32(DrawCommandAbi.bufferId, 33, Endian.little)
      ..setUint32(DrawCommandAbi.bufferVersion, 9, Endian.little)
      ..setUint32(DrawCommandAbi.texChannels, 4, Endian.little)
      ..setUint64(DrawCommandAbi.texData, 303, Endian.little)
      ..setUint32(DrawCommandAbi.texWidth, 64, Endian.little)
      ..setUint32(DrawCommandAbi.texHeight, 32, Endian.little)
      ..setUint32(DrawCommandAbi.texId, 44, Endian.little)
      ..setUint32(DrawCommandAbi.texVersion, 5, Endian.little)
      ..setUint32(
        DrawCommandAbi.texFilter,
        TextureFilterType.nearest,
        Endian.little,
      );

    expect(matches(key, data), isTrue);
  });

  test('pipeline and ordering changes invalidate the graph', () {
    final data = command();
    final key = capture(data);

    data.setUint32(DrawCommandAbi.flags, 1 << 2, Endian.little);
    expect(matches(key, data), isFalse);

    data
      ..setUint32(DrawCommandAbi.flags, 0, Endian.little)
      ..setUint32(DrawCommandAbi.layerIndex, 8, Endian.little);
    expect(matches(key, data), isFalse);

    data
      ..setUint32(DrawCommandAbi.layerIndex, 7, Endian.little)
      ..setInt32(DrawCommandAbi.subLayerIndex, 3, Endian.little);
    expect(matches(key, data), isFalse);
  });

  test('placement admission changes invalidate the graph', () {
    final data = command();
    final key = capture(data);

    data
      ..setFloat32(DrawCommandAbi.drawableUBO, 0, Endian.little)
      ..setFloat32(DrawCommandAbi.drawableUBO + 20, 0, Endian.little);

    expect(matches(key, data), isFalse);
  });

  test('post-admission drops prevent unsafe graph reuse', () {
    final data = command();
    final key = capture(data, active: false);

    expect(key.reusable, isFalse);
    expect(matches(key, data), isFalse);
  });

  test('prepared graph retains stable entries and partitions', () {
    final data = command();
    final entries = <int>[1, 2];
    final partitions = <List<int>>[
      <int>[1],
      <int>[2],
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

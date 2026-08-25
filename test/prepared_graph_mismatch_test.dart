import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/prepared_graph.dart';
import 'package:maplibre_flutter_gpu/src/gpu/prepared_graph_metrics.dart';
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

  PreparedGraphTopologyMismatchReason? changed(
    void Function(ByteData data) mutate,
  ) {
    final data = command();
    final key = capture(data);
    mutate(data);
    return key.firstMismatch(
      commandBytes: data.buffer.asUint8List(),
      commandCount: 1,
      commandStride: DrawCommandAbi.size,
    );
  }

  test('prepared graph classifies every stable command-field mismatch', () {
    expect(
      changed(
        (data) => data.setUint32(
          DrawCommandAbi.shaderType,
          ShaderType.line,
          Endian.little,
        ),
      ),
      PreparedGraphTopologyMismatchReason.shader,
    );
    expect(
      changed(
        (data) => data.setUint32(
          DrawCommandAbi.drawMode,
          DrawModeType.triangles + 1,
          Endian.little,
        ),
      ),
      PreparedGraphTopologyMismatchReason.drawMode,
    );
    expect(
      changed(
        (data) => data.setUint32(DrawCommandAbi.flags, 1 << 2, Endian.little),
      ),
      PreparedGraphTopologyMismatchReason.flags,
    );
    expect(
      changed(
        (data) => data.setUint32(DrawCommandAbi.layerIndex, 8, Endian.little),
      ),
      PreparedGraphTopologyMismatchReason.layer,
    );
    expect(
      changed(
        (data) => data.setInt32(DrawCommandAbi.subLayerIndex, 3, Endian.little),
      ),
      PreparedGraphTopologyMismatchReason.subLayer,
    );
    expect(
      changed(
        (data) => data.setUint32(
          DrawCommandAbi.stencilMode,
          StencilModeType.clippingTest,
          Endian.little,
        ),
      ),
      PreparedGraphTopologyMismatchReason.stencil,
    );
    expect(
      changed(
        (data) => data
          ..setFloat32(DrawCommandAbi.drawableUBO, 0, Endian.little)
          ..setFloat32(DrawCommandAbi.drawableUBO + 20, 0, Endian.little),
      ),
      PreparedGraphTopologyMismatchReason.admission,
    );
  });

  test('prepared graph classifies command-block mismatches', () {
    final data = command();
    final key = capture(data);

    expect(
      key.firstMismatch(
        commandBytes: data.buffer.asUint8List(),
        commandCount: 2,
        commandStride: DrawCommandAbi.size,
      ),
      PreparedGraphTopologyMismatchReason.commandCount,
    );
    expect(
      key.firstMismatch(
        commandBytes: data.buffer.asUint8List(),
        commandCount: 1,
        commandStride: DrawCommandAbi.size + 4,
      ),
      PreparedGraphTopologyMismatchReason.commandStride,
    );
    expect(
      key.firstMismatch(
        commandBytes: Uint8List(DrawCommandAbi.size - 1),
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
      ),
      PreparedGraphTopologyMismatchReason.commandBytes,
    );
    expect(
      capture(command(), active: false).firstMismatch(
        commandBytes: command().buffer.asUint8List(),
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
      ),
      PreparedGraphTopologyMismatchReason.nonReusable,
    );
  });

  test('template probing preserves the active graph mismatch reason', () {
    final original = command();
    final activeKey = capture(original);
    final current = command()
      ..setUint32(DrawCommandAbi.layerIndex, 8, Endian.little);

    final droppedTemplate = command()
      ..setUint32(DrawCommandAbi.layerIndex, 8, Endian.little)
      ..setFloat32(DrawCommandAbi.drawableUBO, 0, Endian.little)
      ..setFloat32(DrawCommandAbi.drawableUBO + 20, 0, Endian.little);
    final cache = PreparedGraphTemplateCache<String>()
      ..remember(
        key: capture(droppedTemplate, active: false),
        value: 'dropped',
      );

    expect(
      activeKey.matches(
        commandBytes: current.buffer.asUint8List(),
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
      ),
      isFalse,
    );
    expect(
      cache.takeMatching(
        commandBytes: current.buffer.asUint8List(),
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
      ),
      isNull,
    );

    final metrics = PreparedGraphDetailedTimingMetrics()
      ..recordRebuild(
        totalMicros: 1000,
        reason: PreparedGraphRebuildReason.topologyMismatch,
        validationMicros: 50,
        decodeMicros: 900,
        captureMicros: 50,
      );
    final snapshot = metrics.takeSnapshotAndReset();

    expect(snapshot.topologyMismatchRebuildCount, 1);
    expect(
      snapshot.topologyMismatchCount(PreparedGraphTopologyMismatchReason.layer),
      1,
    );
    expect(
      snapshot.topologyMismatchCount(
        PreparedGraphTopologyMismatchReason.admission,
      ),
      0,
    );
  });

  test(
    'topology mismatch without a pending diagnosis is counted as unknown',
    () {
      PreparedGraphTopologyDiagnostics.clearPendingMismatch();
      final metrics = PreparedGraphDetailedTimingMetrics()
        ..recordRebuild(
          totalMicros: 100,
          reason: PreparedGraphRebuildReason.topologyMismatch,
          decodeMicros: 90,
          captureMicros: 10,
        );
      final snapshot = metrics.takeSnapshotAndReset();

      expect(
        snapshot.topologyMismatchCount(
          PreparedGraphTopologyMismatchReason.unknown,
        ),
        1,
      );
    },
  );
}

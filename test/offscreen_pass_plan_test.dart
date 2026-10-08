import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/offscreen_pass_plan.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/gpu/command_decoder.dart';
import 'package:maplibre_flutter_gpu/src/gpu/draw_entry.dart';
import 'package:maplibre_flutter_gpu/src/gpu/prepared_graph.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/gpu/style_layer_partition.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';

import 'support/compact_command.dart';

DrawEntry entry(
  int shader, {
  int target = 1,
  int width = 400,
  int height = 300,
  int layer = 0,
  int flags = 0,
}) => DrawEntry(0, shader, 0, flags, layer, 0, 0, null, null, null, 1, 0, 0)
  ..renderTargetId = target
  ..renderTargetWidth = width
  ..renderTargetHeight = height;

class _UnusedResourceCache extends Fake implements GpuResourceCache {}

class _ObservedEntries extends ListBase<OffscreenPlanningEntryView> {
  _ObservedEntries(this._entries);

  final List<OffscreenPlanningEntryView> _entries;
  final indicesRead = <int>[];
  var lengthReads = 0;

  @override
  int get length {
    lengthReads++;

    return _entries.length;
  }

  @override
  set length(int value) => throw UnsupportedError('Read-only entries');

  @override
  OffscreenPlanningEntryView operator [](int index) {
    indicesRead.add(index);

    return _entries[index];
  }

  @override
  void operator []=(int index, OffscreenPlanningEntryView value) =>
      throw UnsupportedError('Read-only entries');
}

void main() {
  test('captured ordinary topology plans without touching entries', () {
    final entries = [
      entry(ShaderType.background),
      entry(ShaderType.fill),
      entry(ShaderType.line),
    ];
    final topology = OffscreenPassTopology.capture(entries);
    final observed = _ObservedEntries(entries);
    expect(topology.plan(observed), isEmpty);
    expect(topology.compositeIndices, isEmpty);
    expect(observed.indicesRead, isEmpty);
    expect(observed.lengthReads, 0);
  });

  test('cached mixed topology reads only offscreen entries', () {
    final entries = [
      entry(ShaderType.background),
      entry(ShaderType.renderTarget),
      entry(ShaderType.heatmap),
      entry(ShaderType.fill),
      entry(
        ShaderType.renderTarget,
        target: 2,
        flags: DrawCommandFlags.renderTargetRgba8,
      ),
      entry(ShaderType.hillshadePrepare, target: 2),
      entry(ShaderType.line),
      entry(ShaderType.heatmapTexture),
      entry(ShaderType.hillshade, target: 2, layer: 1),
      entry(ShaderType.circle),
      entry(ShaderType.hillshade, target: 2, layer: 2),
    ];
    final topology = OffscreenPassTopology.capture(entries);
    final observed = _ObservedEntries(entries);
    expect(topology.plan(observed), [
      (
        kind: OffscreenPassKind.heatmap,
        targetId: 1,
        width: 400,
        height: 300,
        start: 2,
        end: 3,
      ),
      (
        kind: OffscreenPassKind.hillshade,
        targetId: 2,
        width: 400,
        height: 300,
        start: 5,
        end: 6,
      ),
    ]);
    expect(observed.indicesRead.toSet(), {1, 2, 4, 5, 7, 8, 10});
    expect(topology.compositeIndices, [7, 8, 10]);
    expect(() => topology.compositeIndices.add(9), throwsUnsupportedError);
    expect(() => topology.compositeIndices[0] = 9, throwsUnsupportedError);
  });

  test('cached topology refreshes target identity and dimensions', () {
    final entries = [
      entry(ShaderType.renderTarget),
      entry(ShaderType.heatmap),
      entry(ShaderType.renderTarget, target: 2),
      entry(ShaderType.heatmapTexture),
      entry(ShaderType.heatmapTexture, target: 2),
      entry(ShaderType.heatmapTexture, target: 2),
    ];
    final topology = OffscreenPassTopology.capture(entries);
    final original = topology.plan(entries);
    for (final item in entries) {
      item
        ..renderTargetId += 10
        ..renderTargetWidth = 800
        ..renderTargetHeight = 600;
    }
    expect(topology.plan(entries), [
      (
        kind: OffscreenPassKind.heatmap,
        targetId: 11,
        width: 800,
        height: 600,
        start: 1,
        end: 2,
      ),
      (
        kind: OffscreenPassKind.heatmap,
        targetId: 12,
        width: 800,
        height: 600,
        start: 3,
        end: 3,
      ),
    ]);
    expect(topology.compositeIndices, [3, 4, 5]);
    expect(original.first.targetId, 1);
    expect(original.first.width, 400);
    expect(original.first.height, 300);
  });

  test('cached topology rejects refreshed target mismatches', () {
    for (final invalidate in <void Function(List<DrawEntry>)>[
      (entries) => entries[0].renderTargetId = 0,
      (entries) => entries[0].renderTargetWidth = 0,
      (entries) => entries[0].renderTargetHeight = 0,
      (entries) => entries[1].renderTargetId = 2,
      (entries) => entries[1].renderTargetWidth = 800,
      (entries) => entries[1].renderTargetHeight = 600,
      (entries) => entries[2].renderTargetId = 1,
      (entries) => entries[4].renderTargetId = 3,
      (entries) => entries[4].renderTargetId = 2,
    ]) {
      final entries = [
        entry(ShaderType.renderTarget),
        entry(ShaderType.heatmap),
        entry(
          ShaderType.renderTarget,
          target: 2,
          flags: DrawCommandFlags.renderTargetRgba8,
        ),
        entry(ShaderType.hillshadePrepare, target: 2),
        entry(ShaderType.heatmapTexture),
        entry(ShaderType.hillshade, target: 2),
      ];
      final topology = OffscreenPassTopology.capture(entries);
      expect(topology.plan(entries), hasLength(2));
      invalidate(entries);
      expect(() => topology.plan(entries), throwsStateError);
    }
  });

  test('preparation must stay adjacent to its clear', () {
    for (final interveningShader in [
      ShaderType.background,
      ShaderType.heatmapTexture,
    ]) {
      final entries = [
        entry(ShaderType.renderTarget),
        entry(interveningShader),
        entry(ShaderType.heatmap),
      ];
      expect(
        () => OffscreenPassTopology.capture(entries).plan(entries),
        throwsStateError,
      );
    }
  });

  test('density targets retain empty clears and independent draw ranges', () {
    final entries = [
      entry(ShaderType.renderTarget),
      entry(ShaderType.heatmap),
      entry(ShaderType.heatmap),
      entry(ShaderType.renderTarget, target: 2),
      entry(ShaderType.background),
      entry(ShaderType.heatmapTexture),
      entry(ShaderType.heatmapTexture, target: 2),
    ];
    expect(planOffscreenPasses(entries), [
      (
        kind: OffscreenPassKind.heatmap,
        targetId: 1,
        width: 400,
        height: 300,
        start: 1,
        end: 3,
      ),
      (
        kind: OffscreenPassKind.heatmap,
        targetId: 2,
        width: 400,
        height: 300,
        start: 4,
        end: 4,
      ),
    ]);
  });

  test('mixed targets retain format and shared hillshade composition', () {
    final entries = [
      entry(ShaderType.renderTarget),
      entry(ShaderType.heatmap),
      entry(
        ShaderType.renderTarget,
        target: 2,
        flags: DrawCommandFlags.renderTargetRgba8,
      ),
      entry(ShaderType.hillshadePrepare, target: 2),
      entry(ShaderType.heatmapTexture),
      entry(ShaderType.hillshade, target: 2, layer: 1),
      entry(ShaderType.hillshade, target: 2, layer: 2),
    ];
    expect(planOffscreenPasses(entries), [
      (
        kind: OffscreenPassKind.heatmap,
        targetId: 1,
        width: 400,
        height: 300,
        start: 1,
        end: 2,
      ),
      (
        kind: OffscreenPassKind.hillshade,
        targetId: 2,
        width: 400,
        height: 300,
        start: 3,
        end: 4,
      ),
    ]);
  });

  test('invalid offscreen dependencies fail before rendering', () {
    for (final entries in <List<DrawEntry>>[
      [entry(ShaderType.heatmap)],
      [entry(ShaderType.hillshadePrepare)],
      [entry(ShaderType.hillshade)],
      [entry(ShaderType.renderTarget), entry(ShaderType.hillshadePrepare)],
      [entry(ShaderType.renderTarget), entry(ShaderType.hillshade)],
      [
        entry(
          ShaderType.renderTarget,
          flags: DrawCommandFlags.renderTargetRgba8,
        ),
        entry(ShaderType.heatmap),
      ],
      [
        entry(
          ShaderType.renderTarget,
          flags: DrawCommandFlags.renderTargetRgba8,
        ),
        entry(ShaderType.heatmapTexture),
      ],
      [
        entry(
          ShaderType.renderTarget,
          flags: DrawCommandFlags.renderTargetRgba8,
        ),
        entry(ShaderType.hillshadePrepare, target: 2),
      ],
      [
        entry(
          ShaderType.renderTarget,
          flags: DrawCommandFlags.renderTargetRgba8,
        ),
        entry(ShaderType.hillshadePrepare, width: 800),
      ],
      [entry(ShaderType.heatmapTexture)],
      [entry(ShaderType.renderTarget, target: 0)],
      [entry(ShaderType.renderTarget, width: 0)],
      [entry(ShaderType.renderTarget), entry(ShaderType.renderTarget)],
      [entry(ShaderType.renderTarget), entry(ShaderType.heatmap, target: 2)],
      [entry(ShaderType.renderTarget), entry(ShaderType.heatmap, width: 800)],
    ]) {
      expect(() => planOffscreenPasses(entries), throwsStateError);
    }
  });

  test('only map composition enters its style stratum', () {
    final background = entry(ShaderType.background);
    final composite = entry(ShaderType.heatmapTexture, layer: 3);
    final foreground = entry(ShaderType.hillshade, layer: 4);
    final partitions = <List<DrawEntry>>[[], []];
    partitionDrawEntriesByStyleLayerRanges(
      entries: [
        entry(ShaderType.renderTarget),
        entry(ShaderType.heatmap),
        entry(ShaderType.hillshadePrepare),
        background,
        composite,
        foreground,
      ],
      ranges: [
        (minimumLayerIndex: null, maximumLayerIndex: 2),
        (minimumLayerIndex: 2, maximumLayerIndex: null),
      ],
      partitions: partitions,
      clippingMaskPartitions: [false, false],
      stencilClearPartitions: [false, false],
    );
    expect(partitions, [
      [background],
      [composite, foreground],
    ]);
  });

  test(
    'retained empty target refreshes identity and dimensions without geometry',
    () {
      final command = TestCommand(
        drawableSize: 0,
        propsSize: 0,
        sections: CommandPayloadSections.renderTarget,
      );
      final data = command.data
        ..setUint32(
          DrawCommandAbi.shaderType,
          ShaderType.renderTarget,
          .little,
        );
      command.payloadData
        ..setUint32(
          command.renderTargetOffset + CommandRenderTargetAbi.id,
          2,
          .little,
        )
        ..setUint32(
          command.renderTargetOffset + CommandRenderTargetAbi.width,
          800,
          .little,
        )
        ..setUint32(
          command.renderTargetOffset + CommandRenderTargetAbi.height,
          600,
          .little,
        );
      final key = PreparedGraphKey.capture(
        commandBytes: command.bytes,
        payloadBytes: command.payload,
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
        activeCommandOffsets: [0],
      );
      expect(key.reusable, isTrue);
      final target = entry(ShaderType.renderTarget);
      final resources = _UnusedResourceCache();
      final decoder = GpuCommandDecoder(resources);
      addTearDown(decoder.dispose);
      expect(
        decoder.refreshEntries(
          [target],
          data,
          command.reader,
          shouldLog: false,
        ),
        isTrue,
      );
      expect(target.renderTargetId, 2);
      expect(target.renderTargetWidth, 800);
      expect(target.renderTargetHeight, 600);
      expect(target.vertexBuffer, isNull);
      command.payloadData.setUint32(
        command.renderTargetOffset + CommandRenderTargetAbi.width,
        1000,
        .little,
      );
      expect(
        key.matches(
          commandBytes: command.bytes,
          payloadBytes: command.payload,
          commandCount: 1,
          commandStride: DrawCommandAbi.size,
        ),
        isTrue,
      );
      expect(
        decoder.refreshEntries(
          [target],
          data,
          command.reader,
          shouldLog: false,
        ),
        isTrue,
      );
      expect(target.renderTargetWidth, 1000);
    },
  );
}

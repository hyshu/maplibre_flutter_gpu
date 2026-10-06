import 'dart:typed_data';

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

DrawEntry entry(
  int shader, {
  int target = 1,
  int width = 400,
  int layer = 0,
  int flags = 0,
}) => DrawEntry(0, shader, 0, flags, layer, 0, 0, null, null, null, 1, 0, 0)
  ..renderTargetId = target
  ..renderTargetWidth = width
  ..renderTargetHeight = 300;

class _UnusedResourceCache extends Fake implements GpuResourceCache {}

void main() {
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
      final bytes = Uint8List(DrawCommandAbi.size);
      final data = ByteData.sublistView(bytes)
        ..setUint32(DrawCommandAbi.shaderType, ShaderType.renderTarget, .little)
        ..setUint32(DrawCommandAbi.renderTargetId, 2, .little)
        ..setUint32(DrawCommandAbi.renderTargetWidth, 800, .little)
        ..setUint32(DrawCommandAbi.renderTargetHeight, 600, .little);
      final key = PreparedGraphKey.capture(
        commandBytes: bytes,
        commandCount: 1,
        commandStride: DrawCommandAbi.size,
        activeCommandOffsets: [0],
      );
      expect(key.reusable, isTrue);
      final target = entry(ShaderType.renderTarget);
      final resources = _UnusedResourceCache();
      final decoder = GpuCommandDecoder(resources);
      addTearDown(decoder.dispose);
      expect(decoder.refreshEntries([target], data, shouldLog: false), isTrue);
      expect(target.renderTargetId, 2);
      expect(target.renderTargetWidth, 800);
      expect(target.renderTargetHeight, 600);
      expect(target.vertexBuffer, isNull);
      data.setUint32(DrawCommandAbi.renderTargetWidth, 1000, .little);
      expect(
        key.matches(
          commandBytes: bytes,
          commandCount: 1,
          commandStride: DrawCommandAbi.size,
        ),
        isTrue,
      );
      expect(decoder.refreshEntries([target], data, shouldLog: false), isTrue);
      expect(target.renderTargetWidth, 1000);
    },
  );
}

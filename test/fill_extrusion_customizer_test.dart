import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/fill_extrusion/fill_extrusion_geometry.dart';
import 'package:maplibre_flutter_gpu/src/fill_extrusion/fill_extrusion_renderer.dart';
import 'package:maplibre_flutter_gpu/src/gpu/draw_entry.dart';
import 'package:maplibre_flutter_gpu/src/gpu/fill_extrusion_customizer.dart';
import 'package:maplibre_flutter_gpu/src/gpu/pipeline_registry.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/compact_command.dart';

class _Buffer extends Fake implements GpuBufferEntry {
  _Buffer(Uint8List bytes) : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;

  @override
  int get lengthInBytes => bytes.lengthInBytes;
}

class _Pipeline extends Fake implements ResolvedPipeline {
  _Pipeline(this.fillExtrusionMaterial);

  @override
  final FillExtrusionMaterial fillExtrusionMaterial;
}

class _Material extends FillExtrusionMaterial {
  final attributeTiles = <FillExtrusionTile>[];

  @override
  gpu.Shader get fragmentShader => throw StateError('No GPU in this test');

  @override
  int get customAttributeCount => 1;

  @override
  Float32List customAttributes(FillExtrusionTile tile) {
    attributeTiles.add(tile);

    return Float32List.fromList([
      for (var vertex = 0; vertex < tile.vertexCount; vertex += 1)
        tile.positions[vertex * 3 + 2] + (tile.parts.first.featureId as int),
    ]);
  }
}

class _Renderer extends FillExtrusionRenderer {
  _Renderer(this.notifier) : super(repaint: notifier);

  final ChangeNotifier notifier;
  final added = <FillExtrusionTile>[];
  final removed = <FillExtrusionTileKey>[];
  final visited = <FillExtrusionPart>[];
  bool Function(FillExtrusionPart)? visibility;

  @override
  FillExtrusionMaterial? material;

  @override
  bool isVisible(FillExtrusionPart part) {
    visited.add(part);

    return visibility?.call(part) ?? true;
  }

  @override
  void didAddTile(FillExtrusionTile tile) => added.add(tile);

  @override
  void didRemoveTile(FillExtrusionTileKey key) => removed.add(key);
}

class _Resources {
  final uploads = <_Buffer>[];
  final pipelines = <_Pipeline>[];

  late final customizer = FillExtrusionCustomizer.withResources(
    createPipeline: (material, dataDriven, custom) {
      final pipeline = _Pipeline(material);
      pipelines.add(pipeline);

      return pipeline;
    },
    uploadBuffer: (bytes) {
      final buffer = _Buffer(bytes);
      uploads.add(buffer);

      return buffer;
    },
  );
}

class _Frame {
  _Frame({bool dataDriven = false})
    : stride = dataDriven
          ? fillExtrusionDataDrivenVertexStride
          : fillExtrusionConstantVertexStride {
    vertices = calloc<Uint8>(3 * stride);
    indices = calloc<Uint16>(3);
    parts = calloc<Uint8>(CommandFillExtrusionPartAbi.size);
    layerId = 'buildings'.toNativeUtf8();
    vertexData = ByteData.sublistView(vertices.asTypedList(3 * stride));
    partData = ByteData.sublistView(
      parts.asTypedList(CommandFillExtrusionPartAbi.size),
    );
    for (var vertex = 0; vertex < 3; vertex += 1) {
      final offset = vertex * stride;
      vertexData
        ..setInt16(offset, vertex * 10, .little)
        ..setInt16(offset + 2, vertex == 2 ? 10 : 0, .little)
        ..setUint16(offset + 4, vertex == 1 ? 0 : 1, .little);
      if (dataDriven) {
        vertexData
          ..setFloat32(offset + 12, 2, .little)
          ..setFloat32(offset + 16, 6, .little)
          ..setFloat32(offset + 20, 10, .little)
          ..setFloat32(offset + 24, 30, .little);
      }
      indices[vertex] = vertex;
    }
    partData
      ..setUint32(CommandFillExtrusionPartAbi.vertexCount, 3, .little)
      ..setUint32(CommandFillExtrusionPartAbi.indexCount, 3, .little)
      ..setUint32(
        CommandFillExtrusionPartAbi.idType,
        FillExtrusionFeatureIdType.unsigned,
        .little,
      );
    featureId = 1;
    command.data
      ..setUint64(DrawCommandAbi.vertexData, vertices.address, .little)
      ..setUint64(DrawCommandAbi.indexData, indices.address, .little)
      ..setUint32(DrawCommandAbi.vertexCount, 3, .little)
      ..setUint32(DrawCommandAbi.indexCount, 3, .little)
      ..setUint32(DrawCommandAbi.vertexStride, stride, .little)
      ..setUint32(DrawCommandAbi.bufferId, 5, .little)
      ..setUint32(DrawCommandAbi.bufferVersion, 1, .little);
    final offset = command.fillExtrusionFeaturesOffset;
    command.payloadData
      ..setUint64(
        offset + CommandFillExtrusionFeaturesAbi.parts,
        parts.address,
        .little,
      )
      ..setUint64(
        offset + CommandFillExtrusionFeaturesAbi.layerId,
        layerId.address,
        .little,
      )
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.layerIdLength,
        9,
        .little,
      )
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.partCount,
        1,
        .little,
      )
      ..setUint32(
        offset + CommandFillExtrusionFeaturesAbi.partStride,
        CommandFillExtrusionPartAbi.size,
        .little,
      );
    metadataId = 1;
    height = 10;
    command.payloadData.setFloat32(command.propsOffset + 44, 2, .little);
  }

  final int stride;
  late final Pointer<Uint8> vertices;
  late final Pointer<Uint16> indices;
  late final Pointer<Uint8> parts;
  late final Pointer<Utf8> layerId;
  late final ByteData vertexData;
  late final ByteData partData;
  final command = TestCommand(
    drawableSize: 96,
    propsSize: 64,
    sections: CommandPayloadSections.fillExtrusionFeatures,
  );
  final nativeIndices = _Buffer(Uint8List(6));
  final entry = DrawEntry(
    0,
    ShaderType.fillExtrusion,
    DrawModeType.triangles,
    0,
    2,
    3,
    3,
    null,
    null,
    null,
    0,
    0,
    StencilModeType.disabled,
  );

  set featureId(int value) =>
      partData.setUint64(CommandFillExtrusionPartAbi.idValue, value, .little);

  set metadataId(int value) => command.payloadData.setUint64(
    command.fillExtrusionFeaturesOffset +
        CommandFillExtrusionFeaturesAbi.metadataId,
    value,
    .little,
  );

  set tileX(int value) => command.payloadData.setInt32(
    command.fillExtrusionFeaturesOffset + CommandFillExtrusionFeaturesAbi.tileX,
    value,
    .little,
  );

  set height(double value) =>
      command.payloadData.setFloat32(command.propsOffset + 48, value, .little);

  void apply(FillExtrusionCustomizer customizer) {
    entry
      ..indexCount = 3
      ..indexBuffer = nativeIndices;
    customizer.apply([entry], command.data, command.reader);
  }

  void dispose() {
    calloc.free(vertices);
    calloc.free(indices);
    calloc.free(parts);
    calloc.free(layerId);
  }
}

void main() {
  late _Resources resources;
  late FillExtrusionCustomizer customizer;
  late _Frame frame;
  late ChangeNotifier repaint;
  late _Renderer renderer;

  setUp(() {
    resources = _Resources();
    customizer = resources.customizer;
    frame = _Frame();
    repaint = ChangeNotifier();
    renderer = _Renderer(repaint);
  });

  tearDown(() {
    customizer.dispose();
    repaint.dispose();
    frame.dispose();
  });

  test('a cached null selection activates when the builder changes', () {
    customizer.updateBuilder((_) => null);
    frame.apply(customizer);
    expect(renderer.added, isEmpty);

    expect(customizer.updateBuilder((_) => renderer), isTrue);
    expect(customizer.needsReapply, isTrue);
    frame.apply(customizer);
    expect(renderer.added, hasLength(1));
    final revision = customizer.repaintRevision;
    repaint.notifyListeners();
    expect(customizer.repaintRevision, revision + 1);
    expect(customizer.needsReapply, isTrue);
  });

  test('the same renderer keeps its tiles across builder changes', () {
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    final tile = renderer.added.single;

    expect(customizer.updateBuilder((_) => renderer), isFalse);
    frame.apply(customizer);
    expect(renderer.added, [tile]);
    expect(renderer.removed, isEmpty);
  });

  test('layer indices re-evaluate renderer and null selections', () {
    final indices = <int>[];
    customizer.updateBuilder((layer) {
      indices.add(layer.index);

      return layer.index == 2 ? renderer : null;
    });
    frame.apply(customizer);
    expect(renderer.added, hasLength(1));

    frame.entry.layer = 3;
    frame.apply(customizer);
    expect(renderer.removed, [renderer.added.single.key]);
    expect(frame.entry.fillExtrusionCustomization, isNull);

    frame.entry.layer = 2;
    frame.apply(customizer);
    expect(indices, [2, 3, 2]);
    expect(renderer.added, hasLength(2));
    expect(frame.entry.fillExtrusionCustomization, isNotNull);
  });

  test('layer mutations re-evaluate while preserving unchanged renderers', () {
    FillExtrusionRenderer? selected = renderer;
    var builds = 0;
    customizer.updateBuilder((_) {
      builds += 1;

      return selected;
    });
    frame.apply(customizer);
    customizer.layersChanged();
    frame.apply(customizer);
    expect(builds, 2);
    expect(renderer.added, hasLength(1));
    expect(renderer.removed, isEmpty);

    selected = null;
    customizer.layersChanged();
    frame.apply(customizer);
    expect(builds, 3);
    expect(renderer.removed, hasLength(1));
    expect(frame.entry.fillExtrusionCustomization, isNull);
  });

  test('removing a material clears the retained draw streams on repaint', () {
    renderer.material = _Material();
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    expect(frame.entry.customPipeline, isNotNull);
    expect(frame.entry.materialVertexBuffer, isNotNull);
    expect(frame.entry.customVertexBuffer, isNotNull);

    renderer.material = null;
    repaint.notifyListeners();
    customizer.reapply([frame.entry]);
    expect(frame.entry.customPipeline, isNull);
    expect(frame.entry.materialVertexBuffer, isNull);
    expect(frame.entry.customVertexBuffer, isNull);
    expect(frame.entry.indexBuffer, same(frame.nativeIndices));
    expect(frame.entry.indexCount, 3);
    expect(customizer.needsReapply, isFalse);
  });

  test('metadata refreshes identifiers without copying geometry again', () {
    final material = _Material();
    renderer
      ..material = material
      ..visibility = (part) => part.featureId != 2;
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    final original = renderer.added.single;
    final vertexBuffer = frame.entry.materialVertexBuffer;
    final customBuffer = frame.entry.customVertexBuffer;
    expect(frame.entry.indexCount, 3);

    frame
      ..metadataId = 2
      ..featureId = 2;
    frame.vertexData.setInt16(0, 500, .little);
    frame.apply(customizer);
    final updated = renderer.added.last;
    expect(renderer.added, hasLength(2));
    expect(original.parts.single.featureId, 1);
    expect(updated.parts.single.featureId, 2);
    expect(updated.indices, same(original.indices));
    expect(updated.positions[0], 0, reason: 'the owned vertices are reused');
    expect(frame.entry.materialVertexBuffer, same(vertexBuffer));
    expect(frame.entry.customVertexBuffer, isNot(same(customBuffer)));
    expect(material.attributeTiles, [original, updated]);
    expect(frame.entry.indexCount, 0);
    expect(renderer.visited.map((part) => part.featureId), [1, 2]);

    frame.apply(customizer);
    expect(renderer.added, hasLength(2));
    expect(material.attributeTiles, hasLength(2));
  });

  test(
    'constant height changes replace snapshots and keep material vertices',
    () {
      final material = _Material();
      renderer.material = material;
      customizer.updateBuilder((_) => renderer);
      frame.apply(customizer);
      final original = renderer.added.single;
      final vertexBuffer = frame.entry.materialVertexBuffer;
      final customBuffer = frame.entry.customVertexBuffer;
      expect(original.positions[2], 10);

      frame.height = 40;
      frame.apply(customizer);
      final updated = renderer.added.last;
      expect(renderer.added, hasLength(2));
      expect(original.positions[2], 10);
      expect(updated.positions[2], 40);
      expect(updated.indices, same(original.indices));
      expect(frame.entry.materialVertexBuffer, same(vertexBuffer));
      expect(frame.entry.customVertexBuffer, isNot(same(customBuffer)));
      expect(material.attributeTiles, [original, updated]);
    },
  );

  test('data-driven height interpolation refreshes retained snapshots', () {
    frame.dispose();
    frame = _Frame(dataDriven: true);
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    final original = renderer.added.single;
    expect(original.positions[2], 10);
    expect(original.positions[5], 2);

    frame.command.payloadData
      ..setFloat32(frame.command.drawableOffset + 88, 0.5, .little)
      ..setFloat32(frame.command.drawableOffset + 92, 0.75, .little);
    frame.apply(customizer);
    expect(renderer.added, hasLength(2));
    expect(original.positions[2], 10);
    expect(renderer.added.last.positions[2], 25);
    expect(renderer.added.last.positions[5], 4);
    expect(renderer.added.last.indices, same(original.indices));
  });

  test('changed part ranges invalidate material normal vertices', () {
    renderer.material = _Material();
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    final vertexBuffer = frame.entry.materialVertexBuffer;

    frame.metadataId = 2;
    frame.partData.setUint32(
      CommandFillExtrusionPartAbi.vertexCount,
      2,
      .little,
    );
    frame.apply(customizer);
    expect(frame.entry.materialVertexBuffer, isNot(same(vertexBuffer)));
  });

  test('disabling customization restores the native draw on replay', () {
    renderer
      ..material = _Material()
      ..visibility = (_) => false;
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    expect(frame.entry.indexCount, 0);

    expect(customizer.updateBuilder(null), isTrue);
    customizer.reapply([frame.entry]);
    expect(frame.entry.indexCount, 3);
    expect(frame.entry.indexBuffer, same(frame.nativeIndices));
    expect(frame.entry.customPipeline, isNull);
    expect(renderer.removed, hasLength(1));
    final revision = customizer.repaintRevision;
    repaint.notifyListeners();
    expect(customizer.repaintRevision, revision);
  });

  test('the byte budget evicts the least recently rendered tile', () {
    final second = _Frame()..tileX = 1;
    final third = _Frame()..tileX = 2;
    addTearDown(second.dispose);
    addTearDown(third.dispose);
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    final tileBytes = customizer.retainedBytes;
    customizer.updateMemoryBudget(tileBytes * 2);
    second.apply(customizer);
    frame.apply(customizer);
    third.apply(customizer);

    expect(renderer.removed, [renderer.added[1].key]);
    expect(customizer.retainedBytes, tileBytes * 2);
    expect(customizer.memoryBudgetBytes, tileBytes * 2);
  });

  test('shrinking the byte budget immediately releases inactive tiles', () {
    final second = _Frame()..tileX = 1;
    addTearDown(second.dispose);
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    final first = renderer.added.single;
    second.apply(customizer);

    customizer.updateMemoryBudget(0);
    expect(renderer.removed, [first.key]);
    expect(customizer.retainedBytes, greaterThan(0));
    customizer.reapply([second.entry]);
    expect(second.entry.fillExtrusionCustomization, isNotNull);
    expect(second.entry.indexBuffer, same(second.nativeIndices));

    customizer.apply([], frame.command.data, frame.command.reader);
    expect(renderer.removed, renderer.added.map((tile) => tile.key));
    expect(customizer.retainedBytes, 0);
  });

  test('memory pressure releases inactive tiles and keeps replay working', () {
    final second = _Frame()..tileX = 1;
    addTearDown(second.dispose);
    renderer.material = _Material();
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    final first = renderer.added.single;
    second.apply(customizer);
    final vertices = second.entry.materialVertexBuffer;
    final custom = second.entry.customVertexBuffer;
    final bytes = customizer.retainedBytes;

    customizer.reduceMemoryUse();
    customizer.reduceMemoryUse();
    expect(renderer.removed, [first.key]);
    expect(customizer.retainedBytes, lessThan(bytes));
    final revision = customizer.repaintRevision;
    repaint.notifyListeners();
    expect(customizer.repaintRevision, revision + 1);
    customizer.reapply([second.entry]);
    expect(second.entry.materialVertexBuffer, same(vertices));
    expect(second.entry.customVertexBuffer, same(custom));

    frame.apply(customizer);
    expect(renderer.added, hasLength(3));
    expect(renderer.added.last.key, first.key);
    expect(renderer.added.last, isNot(same(first)));
  });

  test('the budget counts lazy geometry and material GPU streams', () {
    renderer.material = _Material();
    customizer.updateBuilder((_) => renderer);
    frame.apply(customizer);
    final tile = renderer.added.single as DecodedFillExtrusionTile;
    final sourceBytes = 3 * fillExtrusionConstantVertexStride + 6;
    final decodedBytes = 3 * (3 * 4 + 2 * 4 + 4 + 1);
    final materialBytes = 3 * fillExtrusionMaterialConstantFloats * 4;
    final customBytes = 3 * fillExtrusionCustomAttributeFloats * 4;

    expect(tile.retainedByteLength, sourceBytes + decodedBytes);
    expect(
      customizer.retainedBytes,
      sourceBytes + decodedBytes + materialBytes + customBytes,
    );
  });

  test('negative byte budgets are rejected without changing the limit', () {
    final budget = customizer.memoryBudgetBytes;

    expect(() => customizer.updateMemoryBudget(-1), throwsRangeError);
    expect(customizer.memoryBudgetBytes, budget);
  });
}

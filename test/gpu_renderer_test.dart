import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/renderer.dart';
import 'package:maplibre_flutter_gpu/src/gpu/draw_entry.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/labels/label_source.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';
import 'package:maplibre_flutter_gpu/src/frame/vertex_repack.dart';
import 'package:maplibre_flutter_gpu/src/gpu/resource_cache.dart';
import 'package:maplibre_flutter_gpu/src/frame/gpu_state.dart';

import 'support/source_files.dart';

void main() {
  test('style layer range uses inclusive lower and exclusive upper bounds', () {
    expect(layerIndexInRange(4), isTrue);
    expect(layerIndexInRange(4, minimumLayerIndex: 4), isTrue);
    expect(layerIndexInRange(4, maximumLayerIndex: 5), isTrue);
    expect(
      layerIndexInRange(4, minimumLayerIndex: 4, maximumLayerIndex: 5),
      isTrue,
    );
    expect(layerIndexInRange(3, minimumLayerIndex: 4), isFalse);
    expect(layerIndexInRange(5, maximumLayerIndex: 5), isFalse);
  });

  test('ordered stratum lookup preserves gaps and half-open bounds', () {
    const ranges = [
      (minimumLayerIndex: null, maximumLayerIndex: 3),
      (minimumLayerIndex: 4, maximumLayerIndex: 8),
      (minimumLayerIndex: 9, maximumLayerIndex: null),
    ];

    expect(gpuStyleLayerRangeIndex(0, ranges), 0);
    expect(gpuStyleLayerRangeIndex(2, ranges), 0);
    expect(gpuStyleLayerRangeIndex(3, ranges), isNull);
    expect(gpuStyleLayerRangeIndex(4, ranges), 1);
    expect(gpuStyleLayerRangeIndex(7, ranges), 1);
    expect(gpuStyleLayerRangeIndex(8, ranges), isNull);
    expect(gpuStyleLayerRangeIndex(9, ranges), 2);
    expect(gpuStyleLayerRangeIndex(100, ranges), 2);
  });

  test('stencil setup follows consumers across style partitions', () {
    DrawEntry entry(int command, int shader, int layer, int stencilMode) =>
        .new(
          command,
          shader,
          DrawModeType.triangles,
          0,
          layer,
          3,
          3,
          null,
          null,
          null,
          TextureFilterType.nearest,
          0,
          stencilMode,
        );
    final entries = [
      entry(0, ShaderType.clippingMask, 84, StencilModeType.clippingMask),
      entry(1, ShaderType.fill, 5, StencilModeType.clippingTest),
      entry(2, ShaderType.fillExtrusion, 84, StencilModeType.fillExtrusion),
    ];
    const ranges = [
      (minimumLayerIndex: null, maximumLayerIndex: 61),
      (minimumLayerIndex: 63, maximumLayerIndex: null),
    ];
    final partitions = [<DrawEntry>[], <DrawEntry>[]];
    final clippingMaskPartitions = [false, false];
    final stencilClearPartitions = [false, false];

    partitionDrawEntriesByStyleLayerRanges(
      entries: entries,
      ranges: ranges,
      partitions: partitions,
      clippingMaskPartitions: clippingMaskPartitions,
      stencilClearPartitions: stencilClearPartitions,
    );

    expect(partitions[0].map((entry) => entry.commandOffset), [0, 1]);
    expect(partitions[1].map((entry) => entry.commandOffset), [2]);
  });

  test('stencil clear does not create control-only partitions', () {
    DrawEntry entry(int command, int layer, int stencilMode) => .new(
      command,
      ShaderType.fill,
      DrawModeType.triangles,
      0,
      layer,
      3,
      3,
      null,
      null,
      null,
      TextureFilterType.nearest,
      0,
      stencilMode,
    );
    final entries = [
      entry(0, 84, StencilModeType.clear),
      entry(1, 5, StencilModeType.clippingTest),
    ];
    const ranges = [
      (minimumLayerIndex: null, maximumLayerIndex: 61),
      (minimumLayerIndex: 63, maximumLayerIndex: null),
    ];
    final partitions = [<DrawEntry>[], <DrawEntry>[]];
    final clippingMaskPartitions = [false, false];
    final stencilClearPartitions = [false, false];

    partitionDrawEntriesByStyleLayerRanges(
      entries: entries,
      ranges: ranges,
      partitions: partitions,
      clippingMaskPartitions: clippingMaskPartitions,
      stencilClearPartitions: stencilClearPartitions,
    );

    expect(partitions[0].map((entry) => entry.commandOffset), [0, 1]);
    expect(partitions[1], isEmpty);
  });

  test('stencil clear remains ordered before fill extrusion', () {
    final entries = [
      DrawEntry(
        0,
        ShaderType.clippingMask,
        DrawModeType.triangles,
        0,
        84,
        0,
        0,
        null,
        null,
        null,
        TextureFilterType.nearest,
        0,
        StencilModeType.clear,
      ),
      DrawEntry(
        1,
        ShaderType.fillExtrusion,
        DrawModeType.triangles,
        0,
        84,
        3,
        3,
        null,
        null,
        null,
        TextureFilterType.nearest,
        1,
        StencilModeType.fillExtrusion,
      ),
    ];
    const ranges = [(minimumLayerIndex: 63, maximumLayerIndex: null)];
    final partitions = [<DrawEntry>[]];
    final clippingMaskPartitions = [false];
    final stencilClearPartitions = [false];

    partitionDrawEntriesByStyleLayerRanges(
      entries: entries,
      ranges: ranges,
      partitions: partitions,
      clippingMaskPartitions: clippingMaskPartitions,
      stencilClearPartitions: stencilClearPartitions,
    );

    expect(partitions.single.map((entry) => entry.commandOffset), [0, 1]);
  });

  test('stratum ranges validate binary-search ordering', () {
    expect(
      gpuStyleLayerRangesAreOrdered(const [
        (minimumLayerIndex: null, maximumLayerIndex: 3),
        (minimumLayerIndex: 4, maximumLayerIndex: 8),
        (minimumLayerIndex: 9, maximumLayerIndex: null),
      ]),
      isTrue,
    );
    expect(
      gpuStyleLayerRangesAreOrdered(const [
        (minimumLayerIndex: null, maximumLayerIndex: 8),
        (minimumLayerIndex: 4, maximumLayerIndex: null),
      ]),
      isFalse,
    );
    expect(
      gpuStyleLayerRangesAreOrdered(const [
        (minimumLayerIndex: null, maximumLayerIndex: null),
        (minimumLayerIndex: 4, maximumLayerIndex: 8),
      ]),
      isFalse,
    );
    expect(gpuStyleLayerRangesAreOrdered(const []), isFalse);
  });

  test('command layers report occupied style ranges', () {
    const layers = {1, 4, 8};

    expect(commandLayersIntersectRange(layers, maximumLayerIndex: 1), isFalse);
    expect(
      commandLayersIntersectRange(
        layers,
        minimumLayerIndex: 2,
        maximumLayerIndex: 8,
      ),
      isTrue,
    );
    expect(commandLayersIntersectRange(layers, minimumLayerIndex: 9), isFalse);
  });

  test('geographic callback runs only in its global style range', () {
    expect(
      threeDimensionalCallbackInLayerRange(
        4,
        minimumLayerIndex: 3,
        maximumLayerIndex: 6,
      ),
      isTrue,
    );
    expect(
      threeDimensionalCallbackInLayerRange(4, maximumLayerIndex: 3),
      isFalse,
    );
    expect(
      threeDimensionalCallbackInLayerRange(4, minimumLayerIndex: 6),
      isFalse,
    );
    expect(
      threeDimensionalCallbackInLayerRange(null, maximumLayerIndex: 6),
      isFalse,
    );
    expect(
      threeDimensionalCallbackInLayerRange(null, minimumLayerIndex: 6),
      isTrue,
    );
  });

  test(
    'clipping runs restore stable sublayer order without crossing barriers',
    () {
      final data = ByteData(DrawCommandAbi.size * 6);
      DrawEntry entry(int index, int layer, int stencilMode, int subLayer) {
        final offset = index * DrawCommandAbi.size;
        data.setInt32(
          offset + DrawCommandAbi.subLayerIndex,
          subLayer,
          Endian.little,
        );

        return .new(
          offset,
          ShaderType.fill,
          DrawModeType.triangles,
          0,
          layer,
          3,
          3,
          null,
          null,
          null,
          TextureFilterType.nearest,
          0,
          stencilMode,
        );
      }

      final entries = [
        entry(0, 9, StencilModeType.clippingTest, 1),
        entry(1, 9, StencilModeType.clippingTest, 2),
        entry(2, 9, StencilModeType.clippingTest, 1),
        entry(3, 9, StencilModeType.clippingTest, 2),
        entry(4, 9, StencilModeType.clippingMask, -1),
        entry(5, 9, StencilModeType.clippingTest, 0),
      ];

      sortClippingRunsBySubLayer(entries, data);

      expect(
        entries.map((entry) => entry.commandOffset ~/ DrawCommandAbi.size),
        [0, 2, 1, 3, 4, 5],
      );
    },
  );

  test('clipping order survives release of native command bytes', () {
    DrawEntry entry(int command, int stencilMode, int subLayer) => .new(
      command,
      ShaderType.fill,
      DrawModeType.triangles,
      0,
      5,
      3,
      3,
      null,
      null,
      null,
      TextureFilterType.nearest,
      0,
      stencilMode,
      subLayerIndex: subLayer,
    );
    final entries = [
      entry(0, StencilModeType.clippingTest, 2),
      entry(1, StencilModeType.clippingTest, 0),
      entry(2, StencilModeType.clippingMask, -1),
      entry(3, StencilModeType.clippingTest, 1),
    ];

    sortClippingRunsBySubLayer(entries);

    expect(entries.map((entry) => entry.commandOffset), [1, 0, 2, 3]);
  });

  test('fixed GPU state descriptors are reused', () {
    expect(
      identical(
        stencilConfigFor(StencilModeType.disabled),
        stencilConfigFor(StencilModeType.disabled),
      ),
      isTrue,
    );
    expect(
      identical(
        premultipliedAlphaBlendEquation(),
        premultipliedAlphaBlendEquation(),
      ),
      isTrue,
    );
    expect(
      identical(
        samplerOptionsFor(ShaderType.raster, TextureFilterType.linear),
        samplerOptionsFor(ShaderType.raster, TextureFilterType.linear),
      ),
      isTrue,
    );
  });

  test('MapLibre alpha blending uses premultiplied source colors', () {
    final blend = premultipliedAlphaBlendEquation();

    expect(blend.colorBlendOperation, gpu.BlendOperation.add);
    expect(blend.sourceColorBlendFactor, gpu.BlendFactor.one);
    expect(
      blend.destinationColorBlendFactor,
      gpu.BlendFactor.oneMinusSourceAlpha,
    );
    expect(blend.alphaBlendOperation, gpu.BlendOperation.add);
    expect(blend.sourceAlphaBlendFactor, gpu.BlendFactor.one);
    expect(
      blend.destinationAlphaBlendFactor,
      gpu.BlendFactor.oneMinusSourceAlpha,
    );
  });

  test('draws reuse buffer-owned vertex and index views', () {
    expect(SourceFiles.renderer, contains('late final view = gpu.BufferView('));
    final pass = SourceFiles.passExecutorOnly;
    expect(pass, contains('entry.vertexBuffer!.view'));
    expect(pass, contains('entry.indexBuffer!.view'));
    expect(pass, contains('pass.drawIndexed(entry.indexCount);'));
    expect(pass, isNot(contains('pass.draw();')));
    expect(pass, isNot(contains('gpu.BufferView(')));
  });

  test('frame-global uniforms bind once per pipeline run', () {
    final renderer = SourceFiles.renderer;
    expect(renderer, contains('binder.bindRunConstants('));
    expect(renderer, contains('propsAreRunConstant: _runHasConstantProps('));
    expect(renderer, contains('bindProps: !propsAreRunConstant'));
    expect(
      RegExp(r'pass\.bindUniform\(vertexGlobal, views\.global\);')
          .allMatches(renderer)
          .length,
      1,
    );
  });

  test('uniform views follow the bounded HostBuffer ring', () {
    final renderer = SourceFiles.renderer;
    expect(renderer, contains('_uniformBufferRingSize = 4'));
    expect(renderer, contains('views.matches(this, buffer, mapGlobalOffset)'));
    expect(
      renderer,
      contains('uniformLength <= _uniformHost!.blockLengthInBytes'),
      reason: 'one-shot oversize buffers must not be retained by draw entries',
    );
    expect(renderer, contains('final views = entry.uniformViews('));
  });

  test('all style strata share one prepared uniform upload', () {
    final renderer = SourceFiles.renderer;

    expect(renderer, contains('gpu.HostBuffer? _uniformHost'));
    expect(renderer, contains('GpuPreparedFrame prepareFrame({'));
    expect(renderer, contains('int renderPreparedFrame({'));
    expect(renderer, isNot(contains('_transientUniforms')));
    expect(
      RegExp(r'_uploadUniforms\(uniformLength\)').allMatches(renderer).length,
      1,
    );
  });

  test('replaying one preparation resets shared depth state', () {
    final renderer = SourceFiles.renderer;
    final replay = renderer.indexOf('void beginFrameReplay()');
    final replayEnd = renderer.indexOf('void _beginPreparedFrame(', replay);
    final reset = renderer.indexOf(
      '_sharedDepthStencilInitialized = false;',
      replay,
    );

    expect(replay, greaterThanOrEqualTo(0));
    expect(replayEnd, greaterThan(replay));
    expect(reset, greaterThan(replay));
    expect(
      renderer.substring(replay, replayEnd),
      isNot(contains('_resourceCacheNeedsEviction = true')),
    );
    expect(renderer, contains('if (advanceResourceFrame) beginFrameReplay();'));
    expect(
      renderer,
      contains('if (evictResourceCaches) _resourceCache.evictCaches();'),
    );
  });

  test('uniform packing needs no frame-wide or per-command pre-clear', () {
    final renderer = SourceFiles.renderer;
    expect(renderer, isNot(contains('clearCommandUniformRanges(')));
    expect(
      renderer,
      isNot(contains('_uniformBytes.fillRange(0, uniformLength, 0)')),
    );
  });

  test('stable native command buffers reuse typed views', () {
    final renderer = SourceFiles.renderer;
    expect(renderer, contains('_commandViewAddress != commandViewAddress'));
    expect(renderer, contains('_commandViewLength != commandViewLength'));
    expect(
      RegExp(r'commandsPointer\.cast<Uint8>\(\)\.asTypedList\(')
          .allMatches(renderer)
          .length,
      1,
    );
    expect(
      RegExp(r'ByteData\.sublistView\(_commandBytes\)')
          .allMatches(renderer)
          .length,
      1,
    );
    expect(renderer, contains('_clearCommandViews();'));
  });

  test('line dash atlas repeats horizontally', () {
    final dash = lineSamplerOptions(ShaderType.lineSDF);
    final gradient = lineSamplerOptions(ShaderType.lineGradient);
    final pattern = lineSamplerOptions(ShaderType.linePattern);

    expect(dash.widthAddressMode, gpu.SamplerAddressMode.repeat);
    expect(dash.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(gradient.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(pattern.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
  });

  test('raster sampler follows exported nearest or linear filter', () {
    final nearest = rasterSamplerOptions(TextureFilterType.nearest);
    final linear = rasterSamplerOptions(TextureFilterType.linear);
    final unknown = rasterSamplerOptions(99);

    expect(nearest.minFilter, gpu.MinMagFilter.nearest);
    expect(nearest.magFilter, gpu.MinMagFilter.nearest);
    expect(linear.minFilter, gpu.MinMagFilter.linear);
    expect(linear.magFilter, gpu.MinMagFilter.linear);
    expect(unknown.minFilter, gpu.MinMagFilter.linear);
    expect(nearest.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(nearest.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
  });

  test('map global uniforms preserve logical and physical viewport sizes', () {
    final values = mapGlobalUniformValues(
      logicalWidth: 333,
      logicalHeight: 211,
      physicalWidth: 499,
      physicalHeight: 316,
    );

    expect(values.unitsX, 166.5);
    expect(values.unitsY, -105.5);
    expect(values.worldWidth, 499);
    expect(values.worldHeight, 316);
  });

  test('uniform offsets honor backend alignment', () {
    expect(alignUniformOffset(0, 256), 0);
    expect(alignUniformOffset(1, 256), 256);
    expect(alignUniformOffset(255, 256), 256);
    expect(alignUniformOffset(256, 256), 256);
    expect(alignUniformOffset(257, 256), 512);
    expect(alignUniformOffset(17, 24), 24);
  });

  test('GPU vertex strides expand integer attributes to numeric floats', () {
    expect(gpuVertexStride(ShaderType.fill, 0), 8);
    expect(gpuVertexStride(ShaderType.fill, 1 << 2), 32);
    expect(
      gpuVertexStride(ShaderType.fill, DrawCommandFlags.crossTileMerged),
      8,
    );
    expect(gpuVertexStride(ShaderType.background, 0), 8);
    expect(
      gpuVertexStride(ShaderType.background, DrawCommandFlags.crossTileMerged),
      8,
    );
    expect(gpuVertexStride(ShaderType.circle, 0), 8);
    expect(gpuVertexStride(ShaderType.circle, 1 << 5), 80);
    expect(gpuVertexStride(ShaderType.fillExtrusion, 0), 24);
    expect(gpuVertexStride(ShaderType.fillExtrusion, 1 << 1), 56);
    expect(
      gpuVertexStride(
        ShaderType.fillExtrusion,
        DrawCommandFlags.fillExtrusionDataDriven |
            DrawCommandFlags.fillExtrusionGpuReady,
      ),
      56,
    );
    expect(gpuVertexStride(ShaderType.line, 0), 24);
    expect(gpuVertexStride(ShaderType.line, DrawCommandFlags.lineGpuReady), 24);
    expect(gpuVertexStride(ShaderType.linePattern, 1 << 19), 120);
    expect(gpuVertexStride(ShaderType.fillOutlineTriangulated, 0), 24);
    expect(gpuVertexStride(ShaderType.fillOutlineTriangulated, 1 << 20), 48);
    expect(gpuVertexStride(ShaderType.raster, 0), 16);
  });

  test('packed fill positions expand to numeric floats', () {
    final source = Uint8List(8);
    final input = ByteData.sublistView(source);
    input
      ..setInt16(0, -32768, Endian.little)
      ..setInt16(2, 32767, Endian.little)
      ..setInt16(4, 7, Endian.little)
      ..setInt16(6, -9, Endian.little);

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 2,
      sourceStride: 4,
      shader: ShaderType.fill,
      flags: 0,
    );

    expect(identical(result, source), isFalse);
    final output = ByteData.sublistView(result);
    expect(
      [
        for (var offset = 0; offset < 16; offset += 4)
          output.getFloat32(offset, Endian.little),
      ],
      [-32768.0, 32767.0, 7.0, -9.0],
    );
  });

  test('packed constant line expands to numeric floats', () {
    final source = Uint8List(8);
    final input = ByteData.sublistView(source);
    input
      ..setInt16(0, -2, Endian.little)
      ..setInt16(2, 4095, Endian.little)
      ..setUint8(4, 0)
      ..setUint8(5, 127)
      ..setUint8(6, 128)
      ..setUint8(7, 255);

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 8,
      shader: ShaderType.line,
      flags: 0,
    );

    expect(identical(result, source), isFalse);
    final output = ByteData.sublistView(result);
    expect(
      [
        for (var offset = 0; offset < 24; offset += 4)
          output.getFloat32(offset, Endian.little),
      ],
      [-2.0, 4095.0, 0.0, 127.0, 128.0, 255.0],
    );
  });

  test(
    'raster preserves signed positions and unsigned texture coordinates',
    () {
      final rasterSource = Uint8List(8);
      final rasterInput = ByteData.sublistView(rasterSource);
      rasterInput
        ..setInt16(0, -32768, Endian.little)
        ..setInt16(2, 32767, Endian.little)
        ..setUint16(4, 32768, Endian.little)
        ..setUint16(6, 65535, Endian.little);
      final raster = repackVertexDataForGpu(
        rasterSource,
        vertexCount: 1,
        sourceStride: 8,
        shader: ShaderType.raster,
        flags: 0,
      );
      final rasterOutput = ByteData.sublistView(raster);
      expect(
        [
          for (var offset = 0; offset < 16; offset += 4)
            rasterOutput.getFloat32(offset, Endian.little),
        ],
        [-32768.0, 32767.0, 32768.0, 65535.0],
      );
    },
  );

  test('packed extrusion layouts expand compact fields', () {
    final constant = Uint8List(12);
    final constantData = ByteData.sublistView(constant);
    constantData
      ..setInt16(0, -3, Endian.little)
      ..setInt16(2, -2, Endian.little)
      ..setUint16(4, 65535, Endian.little)
      ..setUint16(6, 32768, Endian.little)
      ..setInt16(8, -1, Endian.little)
      ..setInt16(10, 2, Endian.little);

    final dd = Uint8List(88);
    final ddData = ByteData.sublistView(dd);
    for (var vertex = 0; vertex < 2; vertex++) {
      final offset = vertex * 44;
      ddData
        ..setInt16(offset, -3 - vertex, Endian.little)
        ..setInt16(offset + 2, 4 + vertex, Endian.little)
        ..setUint16(offset + 4, 32768 + vertex, Endian.little)
        ..setUint16(offset + 6, 65535 - vertex, Endian.little)
        ..setInt16(offset + 8, -1 - vertex, Endian.little)
        ..setInt16(offset + 10, 2 + vertex, Endian.little);
      for (var payload = 12; payload < 44; payload += 4) {
        ddData.setFloat32(
          offset + payload,
          vertex * 10 + payload / 4,
          Endian.little,
        );
      }
    }

    final constantResult = repackVertexDataForGpu(
      constant,
      vertexCount: 1,
      sourceStride: 12,
      shader: ShaderType.fillExtrusion,
      flags: 0,
    );
    final ddResult = repackVertexDataForGpu(
      dd,
      vertexCount: 2,
      sourceStride: 44,
      shader: ShaderType.fillExtrusion,
      flags: DrawCommandFlags.fillExtrusionDataDriven,
    );

    expect(identical(constantResult, constant), isFalse);
    expect(identical(ddResult, dd), isFalse);
    final constantOutput = ByteData.sublistView(constantResult);
    expect(
      [
        for (var offset = 0; offset < 24; offset += 4)
          constantOutput.getFloat32(offset, Endian.little),
      ],
      [-3.0, -2.0, 65535.0, 32768.0, -1.0, 2.0],
    );
    expect(ddResult.lengthInBytes, 112);
    final ddOutput = ByteData.sublistView(ddResult);
    expect(
      [
        for (var offset = 0; offset < 24; offset += 4)
          ddOutput.getFloat32(offset, Endian.little),
      ],
      [-3.0, 4.0, 32768.0, 65535.0, -1.0, 2.0],
    );
    expect(ddResult.sublist(24, 56), orderedEquals(dd.sublist(12, 44)));
  });

  test('DD line preserves float ranges and expands ushort4 patterns', () {
    final source = Uint8List(88);
    final input = ByteData.sublistView(source);
    input
      ..setInt16(0, -17, Endian.little)
      ..setInt16(2, 42, Endian.little)
      ..setUint8(4, 1)
      ..setUint8(5, 2)
      ..setUint8(6, 3)
      ..setUint8(7, 4);
    for (var offset = 8; offset < 72; offset += 4) {
      input.setFloat32(offset, offset / 8, Endian.little);
    }
    const patternFrom = [0, 1, 32768, 65535];
    const patternTo = [65535, 32767, 2, 0];
    for (var i = 0; i < 4; i++) {
      input
        ..setUint16(72 + i * 2, patternFrom[i], Endian.little)
        ..setUint16(80 + i * 2, patternTo[i], Endian.little);
    }

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 88,
      shader: ShaderType.linePattern,
      flags: 1 << 19,
    );
    final output = ByteData.sublistView(result);

    expect(result.lengthInBytes, 120);
    expect(
      [
        for (var offset = 0; offset < 24; offset += 4)
          output.getFloat32(offset, Endian.little),
      ],
      [-17.0, 42.0, 1.0, 2.0, 3.0, 4.0],
    );
    expect(result.sublist(24, 88), orderedEquals(source.sublist(8, 72)));
    expect([
      for (var offset = 88; offset < 104; offset += 4)
        output.getFloat32(offset, Endian.little),
    ], patternFrom.map((value) => value.toDouble()));
    expect([
      for (var offset = 104; offset < 120; offset += 4)
        output.getFloat32(offset, Endian.little),
    ], patternTo.map((value) => value.toDouble()));
  });

  test('render target uses MapLibre premultiplied clear color', () {
    final clear = frameClearValue((
      red: 0.1,
      green: 0.2,
      blue: 0.3,
      alpha: 0.4,
    ));
    final fallback = frameClearValue(null);

    expect(clear.x, closeTo(0.1, 1e-6));
    expect(clear.y, closeTo(0.2, 1e-6));
    expect(clear.z, closeTo(0.3, 1e-6));
    expect(clear.w, closeTo(0.4, 1e-6));
    expect([fallback.x, fallback.y, fallback.z, fallback.w], [0, 0, 0, 0]);
  });

  test(
    'GPU cache retires superseded generations before generic LRU entries',
    () {
      expect(
        gpuCacheEntryExpired(frame: 10, lastUsed: 10, superseded: true),
        isFalse,
      );
      expect(
        gpuCacheEntryExpired(frame: 13, lastUsed: 10, superseded: true),
        isFalse,
      );
      expect(
        gpuCacheEntryExpired(frame: 14, lastUsed: 10, superseded: true),
        isTrue,
      );
      expect(
        gpuCacheEntryExpired(frame: 69, lastUsed: 10, superseded: false),
        isFalse,
      );
      expect(
        gpuCacheEntryExpired(frame: 70, lastUsed: 10, superseded: false),
        isTrue,
      );
      expect(
        gpuCacheEntryExpired(
          frame: 70,
          lastUsed: 10,
          superseded: false,
          unusedRetentionFrames: 600,
        ),
        isFalse,
      );
      expect(
        gpuCacheEntryExpired(
          frame: 610,
          lastUsed: 10,
          superseded: false,
          unusedRetentionFrames: 600,
        ),
        isTrue,
      );
    },
  );

  test('GPU cache byte budget evicts oldest inactive entries only', () {
    final victims = gpuCacheBudgetVictims(
      {
        'old-small': (lastUsed: 1, bytes: 4),
        'old-large': (lastUsed: 1, bytes: 8),
        'recent': (lastUsed: 2, bytes: 4),
        'current': (lastUsed: 3, bytes: 100),
      },
      currentFrame: 3,
      maxBytes: 104,
    );

    expect(victims, ['old-large', 'old-small']);
    expect(victims, isNot(contains('current')));
  });

  test('GPU cache retries a budget blocked by current-frame entries', () {
    final entries = {'current': (lastUsed: 3, bytes: 200)};

    expect(
      gpuCacheBudgetVictims(entries, currentFrame: 3, maxBytes: 96),
      isEmpty,
    );
    expect(gpuCacheBudgetNeedsRetry(residentBytes: 200, maxBytes: 96), isTrue);
    expect(gpuCacheBudgetVictims(entries, currentFrame: 4, maxBytes: 96), [
      'current',
    ]);
  });

  test('GPU cache expiry maintenance follows frames-in-flight cadence', () {
    expect(gpuCacheExpiryMaintenanceDue(0), isTrue);
    expect(gpuCacheExpiryMaintenanceDue(1), isFalse);
    expect(gpuCacheExpiryMaintenanceDue(3), isFalse);
    expect(gpuCacheExpiryMaintenanceDue(4), isTrue);
    expect(gpuCacheExpiryMaintenanceDue(8), isTrue);
  });

  test('GPU cache eviction keeps the latest-used version per id', () {
    final cache = {
      (1, 1): (lastUsed: 10),
      (1, 2): (lastUsed: 12),
      (2, 1): (lastUsed: 10),
      (2, 2): (lastUsed: 10),
      (3, 1): (lastUsed: -46),
    };

    evictExpiredCacheVersions(
      cache,
      frame: 14,
      idOf: (key) => key.$1,
      versionOf: (key) => key.$2,
      lastUsedOf: (value) => value.lastUsed,
    );

    expect(cache.keys, {(1, 2), (2, 2)});
  });

  test('GPU cache supports longer retention for extrusion entries', () {
    final cache = {
      (1, 1): (lastUsed: 10, unusedRetentionFrames: 60),
      (2, 1): (lastUsed: 10, unusedRetentionFrames: 600),
    };

    evictExpiredCacheVersions(
      cache,
      frame: 70,
      idOf: (key) => key.$1,
      versionOf: (key) => key.$2,
      lastUsedOf: (value) => value.lastUsed,
      unusedRetentionFramesOf: (value) => value.unusedRetentionFrames,
    );

    expect(cache.keys, [(2, 1)]);
  });

  test('symbol screen offsets stay independent from map projection', () {
    expect(
      symbolScreenPosition(const Offset(120, 80), 3.5, -6.25),
      const Offset(123.5, 73.75),
    );
    expect(
      symbolScreenPosition(const Offset(240, 160), 3.5, -6.25),
      const Offset(243.5, 153.75),
    );
  });
}

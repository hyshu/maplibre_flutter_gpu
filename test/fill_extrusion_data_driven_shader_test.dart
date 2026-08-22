import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';

void main() {
  test('fill extrusion DD accepts packed and legacy expanded transport layouts', () {
    expect(fillExtrusionVertexStride(0), 12);

    const baseOrHeight = DrawCommandFlags.fillExtrusionDataDriven;
    expect(fillExtrusionVertexStride(baseOrHeight), 44);
    expect(fillExtrusionDataDrivenMask(baseOrHeight), 0);

    const color = DrawCommandFlags.fillExtrusionColorDataDriven;
    expect(fillExtrusionVertexStride(baseOrHeight | color), 44);
    expect(fillExtrusionDataDrivenMask(baseOrHeight | color), 1);

    const expanded = DrawCommandFlags.fillExtrusionGpuReady;
    expect(fillExtrusionVertexStride(baseOrHeight | expanded), 56);
    expect(fillExtrusionVertexStride(baseOrHeight | color | expanded), 56);
    expect(fillExtrusionUsesExpandedGpuLayout(baseOrHeight | expanded), isTrue);
  });

  test('fill extrusion depth prepass follows MapLibre opacity contract', () {
    expect(fillExtrusionNeedsDepthPrepass(0), isTrue);
    expect(fillExtrusionNeedsDepthPrepass(0.75), isTrue);
    expect(fillExtrusionNeedsDepthPrepass(1), isFalse);
    expect(fillExtrusionNeedsDepthPrepass(double.nan), isTrue);
  });

  test('packed fill extrusion DD shader preserves MapLibre color evaluation', () {
    final manifest = jsonDecode(
      File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['FillExtrusionDDVertex']['file'], 'fill_extrusion_dd.vert');
    expect(
      manifest['FillExtrusionExpandedDDVertex']['file'],
      'fill_extrusion_dd_expanded.vert',
    );
    expect(
      manifest['FillExtrusionDepthFragment']['file'],
      'fill_extrusion_depth.frag',
    );

    final vertex = File('shaders/fill_extrusion_dd.vert').readAsStringSync();
    final expanded = File('shaders/fill_extrusion_dd_expanded.vert')
        .readAsStringSync();
    expect(vertex, contains('layout(location = 0) in uvec3 a_layout_packed;'));
    expect(vertex, contains('layout(location = 1) in vec2 a_base_range;'));
    expect(vertex, contains('layout(location = 2) in vec2 a_height_range;'));
    expect(vertex, contains('layout(location = 3) in vec4 a_color_range;'));
    expect(vertex, contains('uint data_driven_mask;'));
    expect(vertex, contains('unpack_short2(a_layout_packed.x)'));
    expect(vertex, contains('unpack_ushort2(a_layout_packed.y)'));
    expect(
      vertex,
      contains('unpack_short2(a_layout_packed.z) / 16384.0'),
    );
    expect(vertex, contains('unpack_float(encoded_color.x) / 255.0'));
    expect(
      vertex,
      contains('color = mix(min_color, max_color, drawable.color_t);'),
    );
    expect(vertex, contains('color = props.color;'));
    expect(
      vertex,
      contains('unpack_float(floor(a_decimals_ed.x / 2.0)) / 128.0'),
    );
    expect(vertex, contains('if (normal.z == 0.0)'));
    expect(expanded, contains('layout(location = 0) in vec2 a_pos;'));
  });

  test('packed FE pipeline pins the 12/44-byte vertex offsets', () {
    final registry = File('lib/src/gpu/pipeline_registry.dart')
        .readAsStringSync();

    expect(registry, contains('format: gpu.VertexFormat.uint32x3'));
    expect(registry, contains('strideInBytes: 12'));
    expect(registry, contains('strideInBytes: 44'));
    expect(registry, contains('offsetInBytes: 12'));
    expect(registry, contains('offsetInBytes: 20'));
    expect(registry, contains('offsetInBytes: 28'));
    expect(registry, contains("vertex: 'FillExtrusionExpandedDDVertex'"));
  });

  test('renderer restores shared depth prepass and read-only color pass', () {
    final depth = File('shaders/fill_extrusion_depth.frag').readAsStringSync();
    final renderer = SourceFiles.renderer;

    expect(depth, contains('frag_color = vec4(0.0);'));
    expect(renderer, contains('gpu.StorageMode.devicePrivate'));
    expect(renderer, contains('depthStoreAction: gpu.StoreAction.store'));
    expect(renderer, contains('binder.depthPipelineFor(first)'));
    expect(renderer, contains('es[layerEnd].layer == first.layer'));
    expect(renderer, contains('depthWrite: true'));
    expect(
      renderer,
      contains('mainDepthStencilTexture != null && needsDepthPrepass'),
    );
    expect(
      renderer,
      contains('depthWrite: mainDepthStencilTexture != null && !needsDepthPrepass'),
    );
  });

  test('renderer prewarms every fill-extrusion pipeline variant', () {
    final registry = File('lib/src/gpu/pipeline_registry.dart')
        .readAsStringSync();
    final renderer = SourceFiles.renderer;

    expect(renderer, contains('_pipelines.prewarmFillExtrusionPipelines();'));
    final prewarmStart = registry.indexOf('void prewarmFillExtrusionPipelines');
    final prewarm = registry.substring(
      prewarmStart,
      registry.indexOf('\n  }', prewarmStart),
    );
    for (final key in <String>[
      'RenderPipelineKey.fillExtrusion',
      'RenderPipelineKey.fillExtrusionDepth',
      'RenderPipelineKey.fillExtrusionDataDriven',
      'RenderPipelineKey.fillExtrusionDataDrivenDepth',
      'RenderPipelineKey.fillExtrusionExpandedDataDriven',
      'RenderPipelineKey.fillExtrusionExpandedDataDrivenDepth',
    ]) {
      expect(prewarm, contains('this[$key];'), reason: key);
    }
  });

  test('native FE color flag and UBO mask offset are explicit', () {
    final flags = File(
      'vendor/maplibre-native/include/mbgl/command_export/draw_command.hpp',
    ).readAsStringSync();
    final drawable = File(
      'vendor/maplibre-native/src/mbgl/command_export/drawable.cpp',
    ).readAsStringSync();

    expect(flags, contains('FillExtrusionColorDataDriven = 1u << 4'));
    expect(
      drawable,
      contains('offsetof(shaders::FillExtrusionDrawableUBO, pad1) == 108'),
    );
    expect(RendererUboAbi.fillExtrusionDataDrivenMaskOffset, 108);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';

void main() {
  test('fill extrusion DD flags select the GPU-ready 56-byte layout', () {
    expect(fillExtrusionVertexStride(0), 12);

    const baseOrHeight = 1 << 1;
    expect(fillExtrusionVertexStride(baseOrHeight), 56);
    expect(fillExtrusionDataDrivenMask(baseOrHeight), 0);

    const color = 1 << 4;
    expect(fillExtrusionVertexStride(baseOrHeight | color), 56);
    expect(fillExtrusionDataDrivenMask(baseOrHeight | color), 1);
  });

  test('fill extrusion depth prepass follows MapLibre opacity contract', () {
    expect(fillExtrusionNeedsDepthPrepass(0), isTrue);
    expect(fillExtrusionNeedsDepthPrepass(0.75), isTrue);
    expect(fillExtrusionNeedsDepthPrepass(1), isFalse);
    expect(fillExtrusionNeedsDepthPrepass(double.nan), isTrue);
  });

  test('fill extrusion DD shader preserves MapLibre color evaluation', () {
    final manifest = jsonDecode(
      File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['FillExtrusionDDVertex']['file'], 'fill_extrusion_dd.vert');
    expect(
      manifest['FillExtrusionDepthFragment']['file'],
      'fill_extrusion_depth.frag',
    );

    final vertex = File('shaders/fill_extrusion_dd.vert').readAsStringSync();
    expect(vertex, contains('layout(location = 0) in vec2 a_pos;'));
    expect(
      vertex,
      contains('layout(location = 1) in vec4 a_decimals_ed_normal;'),
    );
    expect(vertex, contains('layout(location = 4) in vec4 a_color_range;'));
    expect(vertex, contains('uint data_driven_mask;'));
    expect(vertex, contains('unpack_float(encoded_color.x) / 255.0'));
    expect(
      vertex,
      contains('color = mix(min_color, max_color, drawable.color_t);'),
    );
    expect(vertex, contains('color = props.color;'));
    expect(vertex, contains('normal2d = a_decimals_ed_normal.zw / 16384.0'));
    expect(
      vertex,
      contains('unpack_float(floor(a_decimals_ed_normal.x / 2.0)) / 128.0'),
    );
    expect(vertex, contains('if (normal.z == 0.0)'));
  });

  test('renderer restores shared depth prepass and read-only color pass', () {
    final depth = File('shaders/fill_extrusion_depth.frag').readAsStringSync();
    final renderer = SourceFiles.renderer;

    expect(depth, contains('frag_color = vec4(0.0);'));
    expect(renderer, contains('gpu.StorageMode.devicePrivate'));
    expect(renderer, contains('depthStoreAction: gpu.StoreAction.store'));
    expect(renderer, contains('binder.depthPipelineFor(first)'));
    // The prepass reuses the color pipeline's vertex shader with a transparent
    // fragment, so the two keys must stay paired.
    expect(
      renderer,
      contains(
        RegExp(
          r'\? RenderPipelineKey\.fillExtrusionDataDrivenDepth'
          r'\s*: RenderPipelineKey\.fillExtrusionDepth',
        ),
      ),
    );
    expect(renderer, contains('es[layerEnd].layer == first.layer'));
    expect(renderer, contains('depthWrite: true'));
    expect(
      renderer,
      contains('mainDepthStencilTexture != null && needsDepthPrepass'),
    );
    expect(
      renderer,
      contains(
        'depthWrite: mainDepthStencilTexture != null && !needsDepthPrepass',
      ),
    );
  });

  test('renderer prewarms every fill-extrusion pipeline variant', () {
    final registry = File('lib/src/gpu/pipeline_registry.dart')
        .readAsStringSync();
    final renderer = SourceFiles.renderer;

    expect(renderer, contains('_pipelines.prewarmFillExtrusionPipelines();'));
    expect(registry, contains('void prewarmFillExtrusionPipelines()'));
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
    // Byte-level coverage lives in uniform_packer_test.dart.
  });
}

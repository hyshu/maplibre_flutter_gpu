import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';

void main() {
  test('fill-outline flags select the 32-byte triangulated DD layout', () {
    expect(fillOutlineUsesDataDrivenPipeline(0), isFalse);
    expect(fillOutlineVertexStride(0), 8);

    expect(fillOutlineUsesDataDrivenPipeline(1 << 20), isTrue);
    expect(fillOutlineDataDrivenMask(1 << 20), 1);
    expect(fillOutlineVertexStride(1 << 20), 32);

    expect(fillOutlineUsesDataDrivenPipeline(1 << 21), isTrue);
    expect(fillOutlineDataDrivenMask(1 << 21), 2);
    expect(fillOutlineVertexStride(1 << 21), 32);

    const both = (1 << 20) | (1 << 21);
    expect(fillOutlineDataDrivenMask(both), 3);
    expect(fillOutlineVertexStride(both), 32);
    expect(fillOutlineUsesDataDrivenPipeline(1 << 19), isFalse);
    expect(fillOutlineDataDrivenMask(both | (1 << 2) | (1 << 30)), 3);
  });

  test('triangulated DD shaders preserve the normalized vertex ABI', () {
    final manifest = jsonDecode(
      File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(
      manifest['FillOutlineTriangulatedDDVertex']['file'],
      'fill_outline_triangulated_dd.vert',
    );
    expect(
      manifest['FillOutlineTriangulatedDDFragment']['file'],
      'fill_outline_triangulated_dd.frag',
    );

    final vertex = File('shaders/fill_outline_triangulated_dd.vert')
        .readAsStringSync();
    expect(vertex, contains('layout(location = 0) in vec2 a_pos_normal;'));
    expect(vertex, contains('layout(location = 1) in vec4 a_data;'));
    expect(
      vertex,
      contains('layout(location = 2) in vec4 a_outline_color_range;'),
    );
    expect(vertex, contains('layout(location = 3) in vec2 a_opacity_range;'));
    expect(vertex, contains('float u_outline_color_t;'));
    expect(vertex, contains('float u_opacity_t;'));
    expect(vertex, contains('uint data_driven_mask;'));
  });

  test('outline color and opacity independently select DD or constants', () {
    final vertex = File('shaders/fill_outline_triangulated_dd.vert')
        .readAsStringSync();
    final fragment = File('shaders/fill_outline_triangulated_dd.frag')
        .readAsStringSync();

    expect(vertex, contains('unpack_float(encoded_color.x) / 255.0'));
    expect(vertex, contains('(props.data_driven_mask & 1u) != 0u'));
    expect(
      vertex,
      contains(
        'v_outline_color = mix(min_color, max_color, u_outline_color_t);',
      ),
    );
    expect(vertex, contains('v_outline_color = props.outline_color;'));
    expect(vertex, contains('(props.data_driven_mask & 2u) != 0u'));
    expect(
      vertex,
      contains('mix(a_opacity_range.x, a_opacity_range.y, u_opacity_t)'),
    );
    expect(vertex, contains(': props.opacity;'));
    expect(
      fragment,
      contains('frag_color = v_outline_color * (alpha * v_opacity);'),
    );
  });

  test('DD and fixed triangulated outlines use the same AA equations', () {
    final fixedVertex = File('shaders/fill_outline_triangulated.vert')
        .readAsStringSync();
    final fixedFragment = File('shaders/fill_outline_triangulated.frag')
        .readAsStringSync();
    final ddVertex = File('shaders/fill_outline_triangulated_dd.vert')
        .readAsStringSync();
    final ddFragment = File('shaders/fill_outline_triangulated_dd.frag')
        .readAsStringSync();

    for (final equation in const [
      'float antialiasing = 0.5 / dpr;',
      'float halfwidth = 0.5;',
      'vec2 dist = outset * a_extrude * scale;',
      'gl_Position = u_matrix * vec4(pos, 0.0, 1.0) + projected_extrude;',
    ]) {
      expect(fixedVertex, contains(equation));
      expect(ddVertex, contains(equation));
    }
    for (final equation in const [
      'dist_line * v_dpr / max(v_gamma_scale, 0.000001);',
      'float alpha = 1.0 - smoothstep(0.0, 1.0, dist_px);',
    ]) {
      expect(fixedFragment, contains(equation));
      expect(ddFragment, contains(equation));
    }
  });

  test('renderer selects DD outline pipeline and patches ABI carriers', () {
    final renderer = SourceFiles.renderer;
    final pipelines = SourceFiles.renderer;
    expect(pipelines, contains("'FillOutlineTriangulatedDDVertex'"));
    expect(pipelines, contains("'FillOutlineTriangulatedDDFragment'"));
    expect(renderer, contains('fillOutlineVertexStride(flags)'));
    // Byte-level coverage lives in uniform_packer_test.dart.
    expect(RendererUboAbi.fillOutlineDevicePixelRatioOffset, 68);
    expect(RendererUboAbi.fillOutlineDataDrivenMaskOffset, 36);
  });

  test('native outline flags reserve bits 20 and 21', () {
    final flags = File(
      'vendor/maplibre-native/include/mbgl/command_export/draw_command.hpp',
    ).readAsStringSync();
    expect(flags, contains('FillOutlineColorDataDriven = 1u << 20'));
    expect(flags, contains('FillOutlineOpacityDataDriven = 1u << 21'));
    expect(
      flags,
      contains(
        'FillOutlineDataDrivenMask = FillOutlineColorDataDriven | FillOutlineOpacityDataDriven',
      ),
    );
  });
}

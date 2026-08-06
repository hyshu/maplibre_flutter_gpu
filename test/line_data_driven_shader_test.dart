import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';

void main() {
  test('line DD flags select one fixed 88-byte layout and eight-bit mask', () {
    expect(lineUsesDataDrivenPipeline(0), isFalse);
    expect(lineVertexStride(0), 8);

    for (var bit = 12; bit <= 19; bit++) {
      final flags = 1 << bit;
      expect(lineUsesDataDrivenPipeline(flags), isTrue);
      expect(lineVertexStride(flags), 88);
      expect(lineDataDrivenMask(flags), 1 << (bit - 12));
    }

    const allLineFlags = 0xFF000;
    expect(lineDataDrivenMask(allLineFlags), 0xFF);
    expect(lineDataDrivenMask(allLineFlags | (1 << 3) | (1 << 25)), 0xFF);
    expect(lineUsesDataDrivenPipeline(1 << 11), isFalse);
  });

  test('all four line variants have dedicated DD shader pairs', () {
    final manifest =
        jsonDecode(
              File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    const shaders = {
      'LineDDVertex': 'line_dd.vert',
      'LineDDFragment': 'line_dd.frag',
      'LineSDFDDVertex': 'line_sdf_dd.vert',
      'LineSDFDDFragment': 'line_sdf_dd.frag',
      'LineGradientDDVertex': 'line_gradient_dd.vert',
      'LineGradientDDFragment': 'line_gradient_dd.frag',
      'LinePatternDDVertex': 'line_pattern_dd.vert',
      'LinePatternDDFragment': 'line_pattern_dd.frag',
    };
    for (final entry in shaders.entries) {
      expect(manifest[entry.key]['file'], entry.value, reason: entry.key);
    }
  });

  test('DD vertex shaders share the normalized native input contract', () {
    for (final name in const [
      'line_dd.vert',
      'line_sdf_dd.vert',
      'line_gradient_dd.vert',
      'line_pattern_dd.vert',
    ]) {
      final shader = File('shaders/$name').readAsStringSync();
      for (final input in const [
        'layout(location = 0) in vec2 a_pos_normal;',
        'layout(location = 1) in vec4 a_data;',
        'layout(location = 2) in vec4 a_color_range;',
        'layout(location = 3) in vec2 a_blur_range;',
        'layout(location = 4) in vec2 a_opacity_range;',
        'layout(location = 5) in vec2 a_gapwidth_range;',
        'layout(location = 6) in vec2 a_offset_range;',
        'layout(location = 7) in vec2 a_width_range;',
        'layout(location = 8) in vec2 a_floorwidth_range;',
        'layout(location = 9) in vec4 a_pattern_from;',
        'layout(location = 10) in vec4 a_pattern_to;',
      ]) {
        expect(shader, contains(input), reason: '$name: $input');
      }
      expect(shader, contains('uint u_data_driven_mask;'), reason: name);
      expect(shader, contains('gl_Position ='), reason: name);
      expect(shader, isNot(contains('v_pos')), reason: name);
      for (final mask in ['8u', '16u', '32u']) {
        expect(
          shader,
          contains('u_data_driven_mask & $mask'),
          reason: '$name: $mask',
        );
      }
    }
  });

  test('variant-specific DD paint follows MapLibre shader semantics', () {
    final simpleVertex = File('shaders/line_dd.vert').readAsStringSync();
    final simpleFragment = File('shaders/line_dd.frag').readAsStringSync();
    expect(simpleVertex, contains('mix_color_range(a_color_range, u_color_t)'));
    for (final mask in ['1u', '2u', '4u']) {
      expect(simpleFragment, contains('u_data_driven_mask & $mask'));
    }

    final sdfVertex = File('shaders/line_sdf_dd.vert').readAsStringSync();
    final sdfFragment = File('shaders/line_sdf_dd.frag').readAsStringSync();
    expect(sdfVertex, contains('u_floorwidth_t'));
    expect(sdfVertex, contains('u_data_driven_mask & 64u'));
    expect(sdfVertex, contains('u_patternscale_a.x / floorwidth'));
    expect(sdfFragment, contains('u_sdfgamma / floorwidth'));

    final gradientVertex = File(
      'shaders/line_gradient_dd.vert',
    ).readAsStringSync();
    final gradientFragment = File(
      'shaders/line_gradient_dd.frag',
    ).readAsStringSync();
    expect(gradientVertex, isNot(contains('mix_color_range')));
    expect(gradientFragment, contains('texture('));
    expect(gradientFragment, isNot(contains('u_data_driven_mask & 1u')));

    final patternVertex = File(
      'shaders/line_pattern_dd.vert',
    ).readAsStringSync();
    final patternFragment = File(
      'shaders/line_pattern_dd.frag',
    ).readAsStringSync();
    expect(patternVertex, isNot(contains('unpack_pattern')));
    expect(patternVertex, contains('v_pattern_from = a_pattern_from;'));
    expect(patternVertex, contains('v_pattern_to = a_pattern_to;'));
    expect(patternFragment, contains('u_data_driven_mask & 128u'));
    expect(patternFragment, contains('? v_pattern_from : u_pattern_from'));
    expect(patternFragment, contains('? v_pattern_to : u_pattern_to'));
  });

  test('renderer selects DD pipelines and patches the props mask carrier', () {
    final renderer = SourceFiles.renderer;
    final pipelines = SourceFiles.renderer;
    expect(pipelines, contains("'LineDDVertex'"));
    expect(pipelines, contains("'LineSDFDDVertex'"));
    expect(pipelines, contains("'LineGradientDDVertex'"));
    expect(pipelines, contains("'LinePatternDDVertex'"));
    expect(renderer, contains('lineVertexStride(flags)'));
    expect(RendererUboAbi.lineDataDrivenMaskOffset, 40);
    // The mask actually reaching the props UBO is verified byte-for-byte
    // in uniform_packer_test.dart; asserting on the call site here only
    // pinned a local variable name.
  });
}

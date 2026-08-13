import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';

void main() {
  test('fill data-driven flags select the fixed 28-byte vertex format', () {
    expect(fillUsesDataDrivenPipeline(0), isFalse);
    expect(fillVertexStride(0), 4);

    expect(fillUsesDataDrivenPipeline(1 << 2), isTrue);
    expect(fillDataDrivenMask(1 << 2), 1);
    expect(fillVertexStride(1 << 2), 28);

    expect(fillUsesDataDrivenPipeline(1 << 3), isTrue);
    expect(fillDataDrivenMask(1 << 3), 2);
    expect(fillVertexStride(1 << 3), 28);

    expect(fillDataDrivenMask((1 << 2) | (1 << 3)), 3);
    expect(fillUsesDataDrivenPipeline(1 << 1), isFalse);
  });

  test('fill data-driven shader preserves MapLibre paint evaluation', () {
    final manifest = jsonDecode(
      File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['FillDDVertex']['file'], 'fill_dd.vert');
    expect(manifest['FillDDFragment']['file'], 'fill_dd.frag');

    final vertex = File('shaders/fill_dd.vert').readAsStringSync();
    final fragment = File('shaders/fill_dd.frag').readAsStringSync();

    expect(vertex, contains('layout(location = 1) in vec4 a_color_range;'));
    expect(vertex, contains('layout(location = 2) in vec2 a_opacity_range;'));
    expect(vertex, contains('uint data_driven_mask;'));
    expect(vertex, contains('unpack_float(encoded_color.x) / 255.0'));
    expect(
      vertex,
      contains('v_color = mix(min_color, max_color, drawable.color_t);'),
    );
    expect(
      vertex,
      contains('mix(a_opacity_range.x, a_opacity_range.y, drawable.opacity_t)'),
    );
    expect(vertex, contains('v_color = props.color;'));
    expect(vertex, contains(': props.opacity;'));
    expect(fragment, contains('frag_color = v_color * v_opacity;'));
  });

  test('native flags are explicit and DD fills bypass cross-tile merge', () {
    final flags = File(
      'vendor/maplibre-native/include/mbgl/command_export/draw_command.hpp',
    ).readAsStringSync();
    final merge = File('native/src/bridge_merge.cpp').readAsStringSync();

    expect(flags, contains('FillColorDataDriven = 1u << 2'));
    expect(flags, contains('FillOpacityDataDriven = 1u << 3'));
    expect(
      flags,
      contains(
        'FillDataDrivenMask = FillColorDataDriven | FillOpacityDataDriven',
      ),
    );
    expect(
      merge,
      contains('(cmd.flags & DrawCommandFlags::FillDataDrivenMask) != 0'),
    );
  });
}

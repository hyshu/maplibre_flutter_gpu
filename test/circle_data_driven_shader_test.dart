import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:maplibre_flutter_gpu/src/frame/draw_flags.dart';
import 'package:maplibre_flutter_gpu/src/frame/ubo_abi.dart';

void main() {
  test(
    'circle DD flags select the fixed 76-byte layout and seven-bit mask',
    () {
      expect(circleUsesDataDrivenPipeline(0), isFalse);
      expect(circleVertexStride(0), 4);

      for (var bit = 5; bit <= 11; bit++) {
        final flags = 1 << bit;
        expect(circleUsesDataDrivenPipeline(flags), isTrue);
        expect(circleVertexStride(flags), 76);
        expect(circleDataDrivenMask(flags), 1 << (bit - 5));
      }

      const allCircleFlags = 0xFE0;
      expect(circleDataDrivenMask(allCircleFlags), 0x7F);
      expect(circleDataDrivenMask(allCircleFlags | (1 << 1) | (1 << 20)), 0x7F);
    },
  );

  test('circle DD shaders preserve all MapLibre paint interpolations', () {
    final manifest = jsonDecode(
      File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['CircleDDVertex']['file'], 'circle_dd.vert');
    expect(manifest['CircleDDFragment']['file'], 'circle_dd.frag');

    final vertex = File('shaders/circle_dd.vert').readAsStringSync();
    final fragment = File('shaders/circle_dd.frag').readAsStringSync();

    expect(vertex, contains('layout(location = 1) in vec4 a_color_range;'));
    expect(
      vertex,
      contains('layout(location = 7) in vec2 a_stroke_opacity_range;'),
    );
    expect(vertex, contains('uint data_driven_mask;'));
    expect(vertex, contains('unpack_float(encoded_color.x) / 255.0'));
    for (final interpolation in [
      'drawable.color_t',
      'drawable.radius_t',
      'drawable.blur_t',
      'drawable.opacity_t',
      'drawable.stroke_color_t',
      'drawable.stroke_width_t',
      'drawable.stroke_opacity_t',
    ]) {
      expect(vertex, contains(interpolation));
    }
    expect(vertex, contains('(props.data_driven_mask & 2u) != 0u'));
    expect(vertex, contains('(props.data_driven_mask & 32u) != 0u'));
    expect(
      vertex,
      contains('1.0 / drawable.device_pixel_ratio / (radius + stroke_width)'),
    );

    for (final mask in ['1u', '2u', '4u', '8u', '16u', '32u', '64u']) {
      expect(fragment, contains('props.data_driven_mask & $mask'));
    }
    expect(fragment, contains('float antialiased_blur = max('));
    expect(fragment, contains('smoothstep(-antialiased_blur, 0.0,'));
    expect(fragment, contains('radius / (radius + stroke_width)'));
    expect(fragment, contains('mix(color * opacity,'));
    expect(fragment, contains('stroke_color * stroke_opacity'));
  });

  test('native circle flags and props-mask carrier are explicit', () {
    final flags = File(
      'vendor/maplibre-native/include/mbgl/command_export/draw_command.hpp',
    ).readAsStringSync();
    final drawable = File(
      'vendor/maplibre-native/src/mbgl/command_export/drawable.cpp',
    ).readAsStringSync();

    expect(flags, contains('CircleColorDataDriven = 1u << 5'));
    expect(flags, contains('CircleStrokeOpacityDataDriven = 1u << 11'));
    expect(flags, contains('CircleDataDrivenMask = CircleColorDataDriven'));
    expect(
      drawable,
      contains('offsetof(shaders::CircleEvaluatedPropsUBO, pad1) == 60'),
    );
    expect(RendererUboAbi.circleDataDrivenMaskOffset, 60);
    // Byte-level coverage lives in uniform_packer_test.dart.
    expect(RendererUboAbi.circleCameraDistanceOffset, 100);
    expect(RendererUboAbi.circleDevicePixelRatioOffset, 104);
  });
}

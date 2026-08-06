import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('triangulated fill outline has a dedicated antialiased pipeline', () {
    expect(ShaderType.fillOutlineTriangulated, 10);

    final manifest =
        jsonDecode(
              File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(
      manifest['FillOutlineTriangulatedVertex']['file'],
      'fill_outline_triangulated.vert',
    );
    expect(
      manifest['FillOutlineTriangulatedFragment']['file'],
      'fill_outline_triangulated.frag',
    );

    final vertex = File(
      'shaders/fill_outline_triangulated.vert',
    ).readAsStringSync();
    final fragment = File(
      'shaders/fill_outline_triangulated.frag',
    ).readAsStringSync();
    expect(vertex, contains('float halfwidth = 0.5;'));
    expect(vertex, contains('vec2 dist = outset * a_extrude * scale;'));
    expect(vertex, contains('u_units_to_pixels'));
    expect(vertex, isNot(contains('v_pos')));
    expect(
      fragment,
      contains('float alpha = 1.0 - smoothstep(0.0, 1.0, dist_px);'),
    );
    expect(fragment, contains('dist_line * v_dpr / max(v_gamma_scale'));
    expect(fragment, contains('props.outline_color * (alpha * props.opacity)'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('line variants leave tile clipping to the stencil attachment', () {
    for (final name in const [
      'line.frag',
      'line_dd.frag',
      'line_sdf.frag',
      'line_sdf_dd.frag',
      'line_gradient.frag',
      'line_gradient_dd.frag',
      'line_pattern.frag',
      'line_pattern_dd.frag',
    ]) {
      final source = File('shaders/$name').readAsStringSync();
      expect(source, isNot(contains('discard')), reason: name);
      expect(source, isNot(contains('v_pos.x < 0.0')), reason: name);
      expect(source, isNot(contains('v_pos.y > 8192.0')), reason: name);
    }
  });
}

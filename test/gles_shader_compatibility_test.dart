import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vertex shaders use float-only stage inputs', () {
    final manifest =
        jsonDecode(
              File('shaders/MapShaders.shaderbundle.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final integerInput = RegExp(
      r'^layout\(location = \d+\) in (?:u?int|[ui]vec[234])\b',
      multiLine: true,
    );

    for (final entry in manifest.values.cast<Map<String, dynamic>>()) {
      if (entry['type'] != 'vertex') continue;
      final source = File('shaders/${entry['file']}').readAsStringSync();
      expect(
        source,
        isNot(matches(integerInput)),
        reason:
            '${entry['file']} must avoid integer stage inputs because '
            'Impeller OpenGLES only binds float/byte/short attributes.',
      );
      expect(
        source,
        isNot(contains('floatBitsToUint')),
        reason:
            '${entry['file']} must receive numeric floats rather than unsafe '
            'NaN/subnormal bit carriers.',
      );
    }
  });

  test('shader bundle targets GLSL ES 3.00', () {
    final hook = File('hook/build.dart').readAsStringSync();
    expect(hook, contains("'--gles-language-version=300'"));
  });
}

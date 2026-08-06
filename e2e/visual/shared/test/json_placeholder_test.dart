import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

void main() {
  test('escapes backslashes inserted into JSON strings', () {
    const style = '{"url":"__URL__"}';
    const url = r'mbtiles:///tmp/maps/escaped\path\map.mbtiles';

    final replaced = replaceJsonStringPlaceholder(style, '__URL__', url);

    expect(jsonDecode(replaced), <String, Object?>{'url': url});
  });
}

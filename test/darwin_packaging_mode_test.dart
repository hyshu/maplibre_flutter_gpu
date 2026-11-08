import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() => test('macOS packaging reuses existing iOS slices', () {
  final script = File('native/scripts/package_darwin.sh').readAsStringSync();
  final reuseStart = script.indexOf('reuse_ios_framework() {');
  expect(reuseStart, isNonNegative);
  final reuse = script.substring(
    reuseStart,
    script.indexOf('\n}\n', reuseStart),
  );

  expect(
    script,
    isNot(contains('verify_darwin_artifact.sh" ios')),
    reason:
        'macOS-only packaging must not require existing iOS binaries to '
        'export every symbol from the current source tree',
  );
  expect(
    reuse,
    contains('verify_bridge_framework_layout '),
    reason: 'reused iOS slices still need a structural check',
  );
  expect(
    reuse,
    isNot(contains('verify_bridge_framework ')),
    reason:
        'macOS-only packaging must not require existing iOS binaries to '
        'export every symbol from the current source tree',
  );
  expect(reuse, contains(r'existing="${OUTPUT}/${slice}/${FRAMEWORK_SLICE}"'));
  expect(reuse, contains(r'cp -R "${existing}" "${destination}"'));
  expect(
    script,
    contains(
      'reuse_ios_framework iphoneos ios-arm64 '
      r'"${device_framework}" arm64',
    ),
  );
  expect(script, contains('ios-arm64_x86_64-simulator'));
  expect(script, contains(r'-framework "${device_framework}"'));
  expect(script, contains(r'-framework "${simulator_framework}"'));
  expect(script, contains(r'"${SCRIPT_DIR}/build_macos.sh" universal'));
});

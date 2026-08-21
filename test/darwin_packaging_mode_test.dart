import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS packaging reuses existing iOS slices', () {
    final script = File('native/scripts/package_darwin.sh').readAsStringSync();

    expect(
      script,
      isNot(contains('verify_darwin_artifact.sh" ios')),
      reason:
          'macOS-only packaging must not require existing iOS binaries to '
          'export every symbol from the current source tree',
    );
    expect(script, contains('verify_reusable_ios_slice()'));
    expect(script, contains('xcrun lipo -archs'));
    expect(
      script,
      contains('existing_device_headers="\${OUTPUT}/ios-arm64/Headers"'),
    );
    expect(
      script,
      contains(
        'existing_simulator_headers='
        '"\${OUTPUT}/ios-arm64_x86_64-simulator/Headers"',
      ),
    );
    expect(script, contains('cp -R "\${existing_device_headers}"'));
    expect(script, contains('cp -R "\${existing_simulator_headers}"'));
    expect(script, contains('-headers "\${device_headers}"'));
    expect(script, contains('-headers "\${simulator_headers}"'));
    expect(script, contains('"\${SCRIPT_DIR}/build_macos.sh" universal'));
  });
}

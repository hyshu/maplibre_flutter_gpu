import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS packaging reuses existing iOS slices without ABI revalidation', () {
    final script = File('native/scripts/package_darwin.sh').readAsStringSync();

    expect(
      script,
      isNot(contains('verify_darwin_artifact.sh" ios')),
      reason:
          'macOS-only packaging must not require existing iOS binaries to '
          'export every symbol from the current source tree',
    );
    expect(script, contains('verify_reusable_ios_library()'));
    expect(
      script,
      contains(
        'verify_reusable_ios_library "\${existing_device_archive}" arm64',
      ),
    );
    expect(
      script,
      contains(
        'verify_reusable_ios_library "\${existing_simulator_archive}" '
        'arm64 x86_64',
      ),
    );
    expect(script, contains('xcrun lipo -archs'));
    expect(script, contains('"\${SCRIPT_DIR}/build_macos.sh" universal'));
  });
}

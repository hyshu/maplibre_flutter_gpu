import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/library_loader.dart';

void main() {
  test('desktop ABIs map to architecture-specific package directories', () {
    expect(bridgePlatformDirectory(Abi.linuxX64), 'linux/x64');
    expect(bridgePlatformDirectory(Abi.linuxArm64), isNull);
    expect(bridgePlatformDirectory(Abi.windowsX64), 'windows/x64');
    expect(bridgePlatformDirectory(Abi.androidArm64), isNull);
    expect(bridgePlatformDirectory(Abi.macosArm64), isNull);
  });

  test('runtime bundle candidates precede source checkout candidates', () {
    final candidates = bridgeLibraryCandidates(
      'libmaplibre_bridge.so',
      abi: Abi.linuxX64,
      operatingSystem: 'linux',
      executableDirectory: '/application',
      workingDirectory: '/checkout/example',
    );

    expect(candidates.first, '/application/lib/libmaplibre_bridge.so');
    expect(
      candidates,
      contains('/checkout/example/../linux/x64/libmaplibre_bridge.so'),
    );
  });

  test('missing bridge error lists every attempted path', () {
    const missing = 'definitely_absent_maplibre_bridge.so';

    expect(
      () => resolveBridgeLibraryPath(missing),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(missing),
        ),
      ),
    );
  });
}

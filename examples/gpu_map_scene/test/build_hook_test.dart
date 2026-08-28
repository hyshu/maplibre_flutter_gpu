import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shader compiler follows the desktop host architecture', () {
    final hook = File('hook/build.dart').readAsStringSync();

    expect(hook, contains(".linuxX64 => 'linux-x64/impellerc'"));
    expect(hook, contains(".linuxArm64 => 'linux-arm64/impellerc'"));
    expect(hook, contains(".windowsX64 => 'windows-x64/impellerc.exe'"));
    expect(hook, contains(".windowsArm64 => 'windows-arm64/impellerc.exe'"));
  });
}

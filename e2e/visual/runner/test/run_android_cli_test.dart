import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('prebuilt APK options must be provided together', () async {
    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--maplibre-gl-apk=missing.apk',
    ]);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('must be provided together'));
  });

  test('prebuilt APK paths must exist', () async {
    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--maplibre-gl-apk=missing-maplibre-gl.apk',
      '--gpu-apk=missing-gpu.apk',
    ]);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('prebuilt APK does not exist'));
  });

  test('performance options must be provided together', () async {
    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--performance-reference=reference.json',
    ]);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('must be provided together'));
  });
}

Future<ProcessResult> _runAndroid(List<String> arguments) {
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/run_android.dart',
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

part of 'runner.dart';

const _maplibreGlVersion = '0.26.2';

Future<Map<String, Object?>> _collectMetadata({
  required String repositoryRoot,
  required String flutter,
  required String? adb,
  required String? device,
  required String sceneId,
  required double? zoom,
  required int screenshotWidth,
  required int screenshotHeight,
}) async {
  final styleFile = File(
    path.join(repositoryRoot, 'e2e/visual/shared/assets/scenes/$sceneId.json'),
  );
  final metadata = <String, Object?>{
    'scene': sceneId,
    'zoom': ?zoom,
    'styleSha256': sha256.convert(await styleFile.readAsBytes()).toString(),
    'maplibreGlVersion': _maplibreGlVersion,
    'repositoryCommit': await _commandOutput('git', const [
      'rev-parse',
      'HEAD',
    ], workingDirectory: repositoryRoot),
    'maplibreFlutterGpuVersion': await _readPackageVersion(
      File(path.join(repositoryRoot, 'pubspec.yaml')),
    ),
    'gpuMapLibreNativeRevision': await _commandOutput(
      'git',
      const ['rev-parse', 'HEAD'],
      workingDirectory: path.join(repositoryRoot, 'vendor/maplibre-native'),
      fallback: 'public prebuilt / unavailable',
    ),
    'screenshotSize': '${screenshotWidth}x$screenshotHeight',
    'controlHandling': '24 logical px symmetric overscan clips native controls',
  };

  final flutterMachine = await _commandOutput(flutter, const [
    '--version',
    '--machine',
  ], fallback: '');
  if (flutterMachine.isNotEmpty) {
    try {
      final decoded = jsonDecode(flutterMachine) as Map<String, dynamic>;
      metadata['flutterVersion'] = decoded['frameworkVersion'];
      metadata['dartVersion'] = decoded['dartSdkVersion'];
      metadata['flutterEngineRevision'] = decoded['engineRevision'];
    } on FormatException {
      metadata['flutterVersion'] = flutterMachine;
    }
  }

  if (adb != null && device != null) {
    metadata['deviceSerial'] = device;
    metadata['deviceModel'] = await _adbOutput(adb, device, const [
      'shell',
      'getprop',
      'ro.product.model',
    ]);
    metadata['androidApi'] = await _adbOutput(adb, device, const [
      'shell',
      'getprop',
      'ro.build.version.sdk',
    ]);
    metadata['displaySize'] = await _adbOutput(adb, device, const [
      'shell',
      'wm',
      'size',
    ]);
    metadata['displayDensity'] = await _adbOutput(adb, device, const [
      'shell',
      'wm',
      'density',
    ]);
    metadata['glesRenderer'] = await _adbOutput(adb, device, const [
      'shell',
      'getprop',
      'ro.hardware.egl',
    ]);
  }
  return metadata;
}

Future<String> _readPackageVersion(File pubspec) async {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(await pubspec.readAsString());

  return match?.group(1) ?? 'unknown';
}

Future<String> _adbOutput(String adb, String device, List<String> arguments) =>
    _commandOutput(adb, ['-s', device, ...arguments]);

Future<String> _commandOutput(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String fallback = 'unknown',
}) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode == 0) return (result.stdout as String).trim();
  } on ProcessException {
    // Metadata collection must not hide the visual comparison result.
  }
  return fallback;
}

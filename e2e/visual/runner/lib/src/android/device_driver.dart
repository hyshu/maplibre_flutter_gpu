part of 'runner.dart';

Future<({String flutter, String adb, String device})> _driveApplications({
  required String repositoryRoot,
  required Directory imagesDirectory,
  required Directory logsDirectory,
  required Directory outputDirectory,
  required String sceneId,
  required double? zoom,
  required String? maplibreGlApk,
  required String? gpuApk,
  required String? device,
}) async {
  await Future.wait([
    for (final stalePath in [
      path.join(imagesDirectory.path, 'gpu.png'),
      path.join(imagesDirectory.path, 'maplibre_gl.png'),
      path.join(imagesDirectory.path, 'diff.png'),
      path.join(outputDirectory.path, 'index.html'),
      path.join(outputDirectory.path, 'results.json'),
      path.join(logsDirectory.path, 'maplibre_gl-pub-get.log'),
      path.join(logsDirectory.path, 'maplibre_gl-drive.log'),
      path.join(logsDirectory.path, 'maplibre_flutter_gpu-pub-get.log'),
      path.join(logsDirectory.path, 'maplibre_flutter_gpu-drive.log'),
    ])
      _removeStaleFile(File(stalePath)),
  ]);
  final flutter = _findFlutter();
  final adb = _findAdb();
  device ??= await _selectDevice(adb);

  final applications = [
    _VisualApplication(
      label: 'maplibre_gl',
      root: path.join(repositoryRoot, 'e2e/visual/maplibre_gl_app'),
      applicationId: 'dev.maplibre.fluttergpu.e2e.visual_e2e_maplibre_gl',
      applicationBinary: maplibreGlApk,
    ),
    _VisualApplication(
      label: 'maplibre_flutter_gpu',
      root: path.join(repositoryRoot, 'e2e/visual/gpu_app'),
      applicationId: 'dev.maplibre.fluttergpu.e2e.visual_e2e_gpu',
      applicationBinary: gpuApk,
    ),
  ];

  for (final application in applications) {
    stdout.writeln('\n[${application.label}] resolving dependencies');
    await _runLogged(
      flutter,
      const ['pub', 'get'],
      workingDirectory: application.root,
      logFile: File(
        path.join(logsDirectory.path, '${application.label}-pub-get.log'),
      ),
    );
    stdout.writeln('[${application.label}] running Android integration test');
    if (application.applicationBinary != null) {
      stdout.writeln(
        '[${application.label}] using prebuilt APK: '
        '${application.applicationBinary}',
      );
    }
    try {
      await _runLogged(
        flutter,
        buildAndroidDriveArguments(
          device: device,
          sceneId: sceneId,
          zoom: zoom,
          applicationBinary: application.applicationBinary,
        ),
        workingDirectory: application.root,
        environment: {'VISUAL_E2E_SCREENSHOT_DIR': imagesDirectory.path},
        logFile: File(
          path.join(logsDirectory.path, '${application.label}-drive.log'),
        ),
      );
    } finally {
      await _forceStop(adb, device, application.applicationId);
    }
  }

  return (flutter: flutter, adb: adb, device: device);
}

Future<void> _removeStaleFile(File file) async {
  if (await file.exists()) await file.delete();
}

Future<void> _forceStop(String adb, String device, String applicationId) async {
  try {
    await Process.run(adb, [
      '-s',
      device,
      'shell',
      'am',
      'force-stop',
      applicationId,
    ]);
  } on ProcessException {
    // Preserve the original drive result if cleanup cannot contact the device.
  }
}

String _findFlutter({bool required = true}) {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (root != null) path.join(root, 'bin', 'flutter'),
    ..._pathCandidates('flutter'),
  ];

  return _firstExecutable(candidates, 'flutter', required: required);
}

String _findAdb() {
  final sdkRoots = [
    Platform.environment['ANDROID_SDK_ROOT'],
    Platform.environment['ANDROID_HOME'],
    Platform.isMacOS && Platform.environment['HOME'] != null
        ? path.join(Platform.environment['HOME']!, 'Library/Android/sdk')
        : null,
  ];
  final candidates = [
    for (final root in sdkRoots)
      if (root != null) path.join(root, 'platform-tools', 'adb'),
    ..._pathCandidates('adb'),
  ];

  return _firstExecutable(candidates, 'adb');
}

String _firstExecutable(
  List<String> candidates,
  String name, {
  bool required = true,
}) {
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  if (!required) return name;
  throw StateError('$name executable not found');
}

Iterable<String> _pathCandidates(String name) sync* {
  final pathValue = Platform.environment['PATH'];
  if (pathValue == null) return;
  for (final directory in pathValue.split(':')) {
    if (directory.isNotEmpty) yield path.join(directory, name);
  }
}

Future<String> _selectDevice(String adb) async {
  const arguments = ['devices', '-l'];
  final result = await Process.run(adb, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(adb, arguments, result.stderr);
  }
  final devices = LineSplitter.split(result.stdout as String)
      .skip(1)
      .where((line) => line.contains(RegExp(r'\sdevice(?:\s|$)')))
      .map((line) => line.split(RegExp(r'\s+')).first)
      .toList(growable: false);
  if (devices.length != 1) {
    throw StateError(
      devices.isEmpty
          ? 'no Android device is connected'
          : 'multiple Android devices are connected; pass --device',
    );
  }
  return devices.single;
}

Future<void> _runLogged(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required File logFile,
  Map<String, String> environment = const {},
}) async {
  await logFile.parent.create(recursive: true);
  final sink = logFile.openWrite();
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).forEach((chunk) {
    stdout.write(chunk);
    sink.write(chunk);
  });
  final stderrFuture = process.stderr.transform(utf8.decoder).forEach((chunk) {
    stderr.write(chunk);
    sink.write(chunk);
  });
  final processExitCode = await process.exitCode;
  await Future.wait([stdoutFuture, stderrFuture]);
  await sink.flush();
  await sink.close();
  if (processExitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'command failed; see ${logFile.path}',
      processExitCode,
    );
  }
}

class _VisualApplication {
  const new({
    required this.label,
    required this.root,
    required this.applicationId,
    required this.applicationBinary,
  });

  final String label;
  final String root;
  final String applicationId;
  final String? applicationBinary;
}

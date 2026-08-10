import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release versions stay aligned', () {
    final packageVersion = _readPubspecVersion('pubspec.yaml');
    for (final path in <String>[
      'example/pubspec.yaml',
      'examples/gpu_map_scene/pubspec.yaml',
      'examples/map_style_controls/pubspec.yaml',
    ]) {
      expect(_readPubspecVersion(path), packageVersion, reason: path);
    }

    final podspec = File(
      'darwin/maplibre_flutter_gpu.podspec',
    ).readAsStringSync();
    expect(podspec, contains("s.version = '$packageVersion'"));

    final androidHttp = File(
      'android/src/main/java/org/maplibre/android/http/'
      'NativeHttpRequest.java',
    ).readAsStringSync();
    expect(androidHttp, contains('"maplibre_flutter_gpu/$packageVersion"'));
  });

  test('plugin declares only the supported target platforms', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final start = pubspec.indexOf('    platforms:');
    final end = pubspec.indexOf('  assets:', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final platforms = pubspec.substring(start, end);
    for (final platform in <String>['android:', 'ios:', 'macos:']) {
      expect(platforms, contains(platform));
    }
    expect(platforms, isNot(contains('linux:')));
    expect(platforms, isNot(contains('windows:')));
  });

  test('release native artifacts stay untracked but publishable', () {
    final gitignore = File('.gitignore').readAsStringSync();
    expect(
      gitignore,
      contains('/android/src/main/jniLibs/*/libmaplibre_bridge.so'),
    );
    expect(
      gitignore,
      contains(
        '/darwin/maplibre_flutter_gpu/Frameworks/'
        'MapLibreBridge.xcframework/',
      ),
    );

    final pubignore = File('.pubignore').readAsStringSync();
    expect(pubignore, contains('/.agents/'));
    expect(pubignore, isNot(contains('/android/src/main/jniLibs/')));
    expect(
      pubignore,
      isNot(contains('/darwin/maplibre_flutter_gpu/Frameworks/')),
    );
    expect(pubignore, contains('/vendor/maplibre-native/**'));
    expect(pubignore, isNot(contains('/vendor/**')));
  });

  test('release workflow can reuse native artifacts from one run', () {
    final workflow = File(
      '.github/workflows/release-prepare.yml',
    ).readAsStringSync();

    expect(workflow, contains('artifact_run_id:'));
    expect(workflow, contains("inputs.artifact_run_id == ''"));
    expect(
      RegExp(r'run-id:.*inputs\.artifact_run_id').allMatches(workflow),
      hasLength(3),
    );
    expect(
      RegExp(r'github-token:.*github\.token').allMatches(workflow),
      hasLength(3),
    );
  });

  test('native artifact workflow exposes only selected platform jobs', () {
    final workflow = File(
      '.github/workflows/_native-artifacts.yml',
    ).readAsStringSync();

    expect(workflow, contains('  build:\n'));
    expect(workflow, contains("inputs.target == 'android'"));
    expect(workflow, contains("inputs.target == 'ios'"));
    expect(workflow, contains("inputs.target == 'macos'"));
    expect(workflow, contains("inputs.target == 'darwin'"));
    expect(workflow, contains("inputs.target == 'all'"));
    expect(workflow, contains(r'name: ${{ matrix.name }}'));
    expect(workflow, isNot(contains('Build iOS XCFramework')));
    expect(workflow, isNot(contains('Build Android library')));
  });

  test('Darwin force-link anchor retains every exported FFI symbol', () {
    final exportedSymbols = <String>{};
    final apiPattern = RegExp(
      r'MAPLIBRE_API\s+[\w\s*]+?\b(maplibre_[a-zA-Z0-9_]+)\s*\(',
      multiLine: true,
    );
    for (final entity in Directory('native/src').listSync()) {
      if (entity is! File || !entity.path.endsWith('.cpp')) continue;
      exportedSymbols.addAll(
        apiPattern
            .allMatches(entity.readAsStringSync())
            .map((match) => match.group(1)!),
      );
    }
    expect(exportedSymbols, isNotEmpty);

    final anchor = File(
      'darwin/maplibre_flutter_gpu/Packaging/maplibre_bridge_anchor.cpp',
    ).readAsStringSync();
    final anchoredSymbols = RegExp(
      r'^\s*X\((maplibre_[a-zA-Z0-9_]+)\)',
      multiLine: true,
    ).allMatches(anchor).map((match) => match.group(1)!).toSet();

    expect(anchoredSymbols, exportedSymbols);
    expect(anchor, contains('maplibre_flutter_gpu_force_link'));
    expect(
      File(
        'darwin/maplibre_flutter_gpu/Sources/maplibre_flutter_gpu/'
        'MaplibreFlutterGpuPlugin.swift',
      ).readAsStringSync(),
      contains('maplibre_flutter_gpu_force_link()'),
    );
  });

  test('Darwin package managers use the same generated XCFramework', () {
    const artifact = 'Frameworks/MapLibreBridge.xcframework';
    final swiftPackage = File(
      'darwin/maplibre_flutter_gpu/Package.swift',
    ).readAsStringSync();
    final podspec = File(
      'darwin/maplibre_flutter_gpu.podspec',
    ).readAsStringSync();
    final packagingScript = File(
      'native/scripts/package_darwin.sh',
    ).readAsStringSync();
    final commonBuildScript = File(
      'native/scripts/packaging/darwin_common.sh',
    ).readAsStringSync();

    expect(swiftPackage, contains(artifact));
    expect(podspec, contains(artifact));
    expect(packagingScript, contains('MapLibreBridge.xcframework'));
    for (final source in <String>[swiftPackage, podspec, commonBuildScript]) {
      expect(source, contains('14.3'));
    }
  });
}

String _readPubspecVersion(String path) {
  final contents = File(path).readAsStringSync();
  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(contents);
  if (match == null) {
    throw StateError('Missing version in $path.');
  }

  return match.group(1)!;
}

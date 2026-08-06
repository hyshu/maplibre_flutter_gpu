import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(pubignore, isNot(contains('/android/src/main/jniLibs/')));
    expect(
      pubignore,
      isNot(contains('/darwin/maplibre_flutter_gpu/Frameworks/')),
    );
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

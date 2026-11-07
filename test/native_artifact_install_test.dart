import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _xcframework =
    'darwin/maplibre_flutter_gpu/Frameworks/MapLibreBridge.xcframework';
const _framework = '$_xcframework/macos-arm64_x86_64/MapLibreBridge.framework';
const _versionedLinks = {
  'Versions/Current': 'A',
  'MapLibreBridge': 'Versions/Current/MapLibreBridge',
  'Headers': 'Versions/Current/Headers',
  'Modules': 'Versions/Current/Modules',
  'Resources': 'Versions/Current/Resources',
};

void main() {
  late Directory workspace;
  late Directory project;
  late Directory artifacts;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('maplibre-native-install-');
    project = Directory('${workspace.path}/project');
    artifacts = Directory('${workspace.path}/artifacts')..createSync();
    Directory('${project.path}/tool/ci').createSync(recursive: true);
    File('tool/ci/install_native_artifacts.sh')
        .copySync('${project.path}/tool/ci/install_native_artifacts.sh');
    File('${project.path}/tool/ci/verify_darwin_artifact.sh')
        .writeAsStringSync('#!/usr/bin/env bash\nexit 0\n');
    File('${project.path}/.gitignore').writeAsStringSync('/$_xcframework/\n');
    _run('chmod', [
      '+x',
      'tool/ci/install_native_artifacts.sh',
      'tool/ci/verify_darwin_artifact.sh',
    ], project.path);
    _run('git', ['init', '--quiet'], project.path);
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  ProcessResult install(
    String mode,
    String archiveName, {
    Map<String, String> links = _versionedLinks,
  }) {
    final staging = Directory('${workspace.path}/staging');
    final framework = '${staging.path}/$_framework';
    for (final file in [
      'Versions/A/MapLibreBridge',
      'Versions/A/Headers/MapLibreBridge.h',
      'Versions/A/Modules/module.modulemap',
      'Versions/A/Resources/Info.plist',
    ]) {
      File('$framework/$file')
        ..createSync(recursive: true)
        ..writeAsStringSync(file);
    }
    File('${staging.path}/$_xcframework/Info.plist').writeAsStringSync('');
    for (final MapEntry(key: path, value: target) in links.entries) {
      Link('$framework/$path').createSync(target, recursive: true);
    }
    _run(
      'tar',
      ['-czf', '${artifacts.path}/$archiveName', _xcframework],
      staging.path,
      environment: {'COPYFILE_DISABLE': '1'},
    );
    _run('sh', [
      '-c',
      'if command -v sha256sum >/dev/null; then sha256sum "\$0"; '
          'else shasum -a 256 "\$0"; fi > "\$0.sha256"',
      archiveName,
    ], artifacts.path);

    return Process.runSync(
      '${project.path}/tool/ci/install_native_artifacts.sh',
      [artifacts.path, mode],
    );
  }

  test('Darwin install keeps the versioned macOS framework links', () {
    final result = install('darwin', 'native-darwin.tar.gz');

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final framework = '${project.path}/$_framework';
    for (final MapEntry(key: path, value: target) in _versionedLinks.entries) {
      expect(Link('$framework/$path').targetSync(), target);
    }
    expect(
      File('$framework/MapLibreBridge').readAsStringSync(),
      'Versions/A/MapLibreBridge',
    );
  });

  for (final (description, links) in [
    (
      'a framework link with another target',
      {..._versionedLinks, 'Versions/Current': '../../../../../../..'},
    ),
    (
      'a link outside the framework layout',
      {..._versionedLinks, 'Versions/A/Headers/hosts.h': '/etc/hosts'},
    ),
  ]) {
    test('Darwin install rejects $description', () {
      final result = install('darwin', 'native-darwin.tar.gz', links: links);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('unexpected link'));
      expect(Directory('${project.path}/$_xcframework').existsSync(), isFalse);
    });
  }

  test('iOS install rejects framework links', () {
    final result = install('ios', 'native-darwin-ios.tar.gz');

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('unexpected link'));
    expect(Directory('${project.path}/$_xcframework').existsSync(), isFalse);
  });
}

void _run(
  String executable,
  List<String> arguments,
  String workingDirectory, {
  Map<String, String>? environment,
}) {
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

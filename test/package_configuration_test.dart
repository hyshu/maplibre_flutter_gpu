import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter and Dart toolchain versions stay aligned', () {
    const flutterVersion = '3.47.0';
    const dartConstraint = '^3.13.0';
    const flutterConstraint = '>=3.47.0';
    for (final path in <String>[
      'pubspec.yaml',
      'example/pubspec.yaml',
      'examples/gpu_map_scene/pubspec.yaml',
      'examples/map_style_controls/pubspec.yaml',
      'e2e/visual/gpu_app/pubspec.yaml',
      'e2e/visual/maplibre_gl_app/pubspec.yaml',
      'e2e/visual/shared/pubspec.yaml',
    ]) {
      final pubspec = File(path).readAsStringSync();
      expect(pubspec, contains('sdk: $dartConstraint'), reason: path);
      expect(pubspec, contains("flutter: '$flutterConstraint'"), reason: path);
    }

    final runner = File('e2e/visual/runner/pubspec.yaml').readAsStringSync();
    expect(runner, contains('sdk: $dartConstraint'));

    final workflows = Directory('.github/workflows')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.yml'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    final configuredFlutterVersions = RegExp(r'flutter-version:\s*([^\s]+)')
        .allMatches(workflows)
        .map((match) => match.group(1)!)
        .toList();
    expect(configuredFlutterVersions, isNotEmpty);
    expect(configuredFlutterVersions, everyElement(flutterVersion));
    final workaroundName =
        'with_flutter_${flutterVersion.replaceAll('.', '_')}'
        '_macos_aot_workaround.sh';
    final referencedWorkarounds = RegExp(
      r'with_flutter_[0-9_]+_macos_aot_workaround\.sh',
    ).allMatches(workflows).map((match) => match.group(0)!).toSet();
    expect(referencedWorkarounds, everyElement(workaroundName));
    expect(File('tool/ci/$workaroundName').existsSync(), isTrue);
  });

  test('release versions stay aligned', () {
    final packageVersion = _readPubspecVersion('pubspec.yaml');
    for (final path in <String>[
      'example/pubspec.yaml',
      'examples/gpu_map_scene/pubspec.yaml',
      'examples/map_style_controls/pubspec.yaml',
    ]) {
      expect(_readPubspecVersion(path), packageVersion, reason: path);
    }

    final podspec = File('darwin/maplibre_flutter_gpu.podspec')
        .readAsStringSync();
    expect(podspec, contains("s.version = '$packageVersion'"));

    final androidHttp = File(
      'android/src/main/java/org/maplibre/android/http/'
      'NativeHttpRequest.java',
    ).readAsStringSync();
    expect(androidHttp, contains('"maplibre_flutter_gpu/$packageVersion"'));
  });

  test('package declares every supported target platform', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final start = pubspec.indexOf('\nplatforms:');
    final end = pubspec.indexOf('\nenvironment:', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final platforms = pubspec.substring(start, end);
    for (final platform in <String>[
      'android:',
      'ios:',
      'macos:',
      'linux:',
      'windows:',
    ]) {
      expect(platforms, contains(platform));
    }
    final pluginPlatforms = pubspec.substring(
      pubspec.indexOf('    platforms:'),
      pubspec.indexOf('  assets:'),
    );
    expect(pluginPlatforms, isNot(contains('linux:')));
    expect(pluginPlatforms, isNot(contains('windows:')));
  });

  test('release native artifacts use platform-specific delivery', () {
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
    expect(gitignore, contains('/linux/*/libmaplibre_bridge.so'));
    expect(gitignore, contains('/windows/*/maplibre_bridge.dll'));

    final pubignore = File('.pubignore').readAsStringSync();
    expect(pubignore, contains('/.agents/'));
    expect(pubignore, isNot(contains('/android/src/main/jniLibs/')));
    expect(
      pubignore,
      isNot(contains('/darwin/maplibre_flutter_gpu/Frameworks/')),
    );
    expect(pubignore, contains('/linux/'));
    expect(pubignore, contains('/windows/'));
    expect(pubignore, contains('/vendor/maplibre-native/**'));
    expect(pubignore, isNot(contains('/vendor/**')));
  });

  test('release workflows separate artifact builds from preparation', () {
    final artifactWorkflow = File('.github/workflows/release-artifacts.yml')
        .readAsStringSync();
    final preparationWorkflow = File('.github/workflows/release-prepare.yml')
        .readAsStringSync();

    expect(artifactWorkflow, contains('name: Release artifacts'));
    expect(
      artifactWorkflow,
      contains('uses: ./.github/workflows/_native-artifacts.yml'),
    );
    expect(
      artifactWorkflow,
      contains('uses: ./.github/workflows/_desktop-artifacts.yml'),
    );
    expect(artifactWorkflow, isNot(contains('artifact_run_id')));
    expect(artifactWorkflow, isNot(contains('prepare_release_bundle.sh')));

    expect(preparationWorkflow, contains('artifact_run_id:'));
    expect(preparationWorkflow, contains('required: true'));
    expect(preparationWorkflow, contains('Release artifacts'));
    expect(preparationWorkflow, contains('verify_release_artifact_source.sh'));
    expect(preparationWorkflow, isNot(contains('new-build')));
    expect(preparationWorkflow, isNot(contains('_native-artifacts.yml')));
    expect(preparationWorkflow, isNot(contains('_desktop-artifacts.yml')));
    expect(
      RegExp(r'run-id:.*inputs\.artifact_run_id')
          .allMatches(preparationWorkflow),
      hasLength(7),
    );
    expect(
      RegExp(r'github-token:.*github\.token').allMatches(preparationWorkflow),
      hasLength(7),
    );
    for (final artifact in <String>[
      'native-linux-x64',
      'native-linux-arm64',
      'native-windows-x64',
      'native-windows-arm64',
    ]) {
      expect(preparationWorkflow, contains(artifact));
    }
  });

  test('release artifact reuse accepts only release metadata changes', () {
    final repository = Directory.systemTemp.createTempSync(
      'maplibre-release-artifact-source-',
    );
    final script = File('tool/ci/verify_release_artifact_source.sh')
        .absolute
        .path;

    ProcessResult runGit(List<String> arguments) {
      final result = Process.runSync(
        'git',
        arguments,
        workingDirectory: repository.path,
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      return result;
    }

    String head() {
      return runGit(<String>['rev-parse', 'HEAD']).stdout.toString().trim();
    }

    try {
      runGit(<String>['init', '--quiet']);
      runGit(<String>['config', 'user.name', 'Release Test']);
      runGit(<String>['config', 'user.email', 'release@example.invalid']);
      File('${repository.path}/CHANGELOG.md').writeAsStringSync('base\n');
      runGit(<String>['add', 'CHANGELOG.md']);
      runGit(<String>['commit', '--quiet', '-m', 'base']);
      final artifactSource = head();

      File('${repository.path}/CHANGELOG.md').writeAsStringSync('release\n');
      runGit(<String>['add', 'CHANGELOG.md']);
      runGit(<String>['commit', '--quiet', '-m', 'release metadata']);
      final compatibleRelease = head();
      final compatible = Process.runSync(script, <String>[
        artifactSource,
        compatibleRelease,
        repository.path,
      ]);
      expect(
        compatible.exitCode,
        0,
        reason: '${compatible.stdout}\n${compatible.stderr}',
      );

      final nativeSource = File('${repository.path}/native/src/change.cpp');
      nativeSource.parent.createSync(recursive: true);
      nativeSource.writeAsStringSync('int changed;\n');
      runGit(<String>['add', nativeSource.path]);
      runGit(<String>['commit', '--quiet', '-m', 'native change']);
      final incompatible = Process.runSync(script, <String>[
        artifactSource,
        head(),
        repository.path,
      ]);
      expect(incompatible.exitCode, isNot(0));
      expect(incompatible.stderr, contains('native/src/change.cpp'));
    } finally {
      repository.deleteSync(recursive: true);
    }
  });

  test('build hook directory contains only the pub entrypoint', () {
    final dartFiles = Directory('hook')
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('.dart'))
        .toList();

    expect(dartFiles, <String>['hook/build.dart']);
  });

  test('desktop artifact workflow builds release archives on target hosts', () {
    final workflow = File('.github/workflows/_desktop-artifacts.yml')
        .readAsStringSync();
    final archiveScript = File('tool/ci/archive_native_artifact.sh')
        .readAsStringSync();
    final installScript = File('tool/ci/install_native_artifacts.sh')
        .readAsStringSync();
    final bundleScript = File('tool/ci/prepare_release_bundle.sh')
        .readAsStringSync();
    final publishScript = File('tool/ci/check_publish.sh').readAsStringSync();

    expect(workflow, contains('runner: ubuntu-22.04'));
    expect(workflow, contains('runner: ubuntu-22.04-arm'));
    expect(workflow, contains('runner: windows-2025'));
    expect(workflow, contains('runner: windows-11-arm'));
    expect(workflow, contains('./native/scripts/build_linux.sh'));
    expect(workflow, contains('./native/scripts/build_windows.ps1'));
    for (final artifact in <String>[
      'native-linux-x64.tar.gz',
      'native-linux-arm64.tar.gz',
      'native-windows-x64.tar.gz',
      'native-windows-arm64.tar.gz',
    ]) {
      expect(workflow, contains(artifact));
      expect(installScript, contains(artifact));
      expect(bundleScript, contains(artifact));
    }
    for (final path in <String>[
      'linux/x64/libmaplibre_bridge.so',
      'linux/arm64/libmaplibre_bridge.so',
      'windows/x64/maplibre_bridge.dll',
      'windows/arm64/maplibre_bridge.dll',
    ]) {
      expect(installScript, contains(path));
      expect(installScript, contains(path));
    }
    expect(publishScript, isNot(contains('linux/x64/libmaplibre_bridge.so')));
    expect(publishScript, contains('hook/desktop_artifacts.json'));
    expect(bundleScript, contains('verify_desktop_release_manifest.py'));
    expect(bundleScript, contains(r'"${ARTIFACT_DIRECTORY}" android'));
    expect(bundleScript, isNot(contains('android-arm64-v8a\n')));
    expect(bundleScript, isNot(contains('android-x86_64\n')));
    expect(archiveScript, contains('linux-x64|linux-arm64'));
    expect(archiveScript, contains(r'linux/${ARCHITECTURE}'));
    expect(archiveScript, contains('windows-x64|windows-arm64'));
    expect(archiveScript, contains(r'windows/${ARCHITECTURE}'));
    final windowsBuildScript = File('native/scripts/build_windows.ps1')
        .readAsStringSync();
    expect(windowsBuildScript, contains('[ValidateSet("x64", "arm64")]'));
    expect(workflow, contains(r"-Architecture '${{ matrix.architecture }}'"));
    expect(workflow, isNot(contains('x86')));
  });

  test('quality installs the Linux build-hook artifact', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    final qualityStart = workflow.indexOf('  quality:');
    final linuxStart = workflow.indexOf('\n  linux:', qualityStart);
    final quality = workflow.substring(qualityStart, linuxStart);

    expect(quality, contains('needs: linux'));
    expect(quality, contains(r'ci-native-linux-x64-${{ github.run_id }}'));
    expect(quality, contains('install_native_artifacts.sh'));
    expect(quality, contains('linux-x64'));
  });

  test('Linux compatibility smoke runs the Ubuntu 22.04 artifact on 24.04', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    final compatibilityStart = workflow.indexOf('  linux_compat:');
    final armStart = workflow.indexOf('\n  linux_arm64:', compatibilityStart);
    final compatibility = workflow.substring(compatibilityStart, armStart);

    expect(compatibility, contains('needs: linux'));
    expect(compatibility, contains('runs-on: ubuntu-24.04'));
    expect(
      compatibility,
      contains(r'ci-native-linux-x64-${{ github.run_id }}'),
    );
    expect(compatibility, contains('--scene text-symbol'));
  });

  test('required CI covers mobile, Darwin, and desktop jobs', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    final required = workflow.substring(workflow.indexOf('  required:'));

    for (final job in <String>[
      'native_ios',
      'consumer_ios',
      'ios_visual',
      'native_android',
      'consumer_android',
      'android_e2e_firebase',
      'android_visual',
      'native_macos',
      'consumer_macos',
      'macos_visual',
      'macos_functional',
      'linux',
      'linux_visual',
      'linux_compat',
      'linux_arm64',
      'windows',
      'windows_visual',
      'windows_arm64',
    ]) {
      expect(required, contains('      - $job\n'), reason: job);
    }
  });

  test('publish readiness installs only packaged native artifacts', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    final packageStart = workflow.indexOf('  package:');
    final iosVisualStart = workflow.indexOf('  ios_visual:', packageStart);
    final package = workflow.substring(packageStart, iosVisualStart);

    expect(package, contains(r'"$RUNNER_TEMP/native-artifacts" android'));
    expect(package, contains(r'"$RUNNER_TEMP/native-artifacts" darwin'));
    expect(package, isNot(contains('native-linux')));
    expect(package, isNot(contains('native-windows')));
  });

  test('native artifact workflow exposes only selected platform jobs', () {
    final workflow = File('.github/workflows/_native-artifacts.yml')
        .readAsStringSync();

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
    final swiftPackage = File('darwin/maplibre_flutter_gpu/Package.swift')
        .readAsStringSync();
    final podspec = File('darwin/maplibre_flutter_gpu.podspec')
        .readAsStringSync();
    final packagingScript = File('native/scripts/package_darwin.sh')
        .readAsStringSync();
    final commonBuildScript = File('native/scripts/packaging/darwin_common.sh')
        .readAsStringSync();

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

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

import '../lib/src/native/desktop_artifacts.dart';

void main() {
  test('desktop artifact manifest covers every supported 64-bit target', () {
    final manifest = parseDesktopArtifactManifest(
      File('hook/desktop_artifacts.json').readAsStringSync(),
    );
    expect(
      manifest.artifacts
          .map(
            (artifact) =>
                '${artifact.operatingSystem.name}-${artifact.architecture.name}',
          )
          .toSet(),
      {'linux-x64', 'linux-arm64', 'windows-x64', 'windows-arm64'},
    );
    expect(Uri.parse(manifest.baseUrl).scheme, 'https');
    for (final artifact in manifest.artifacts) {
      expect(artifact.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(artifact.archiveName, endsWith('.tar.gz'));
      expect(artifact.archiveMember, isNot(startsWith('/')));
    }
  });

  test('desktop hook bundles an explicit local artifact', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'maplibre-hook-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final source = File('${temporaryDirectory.path}/bridge.so');
    await source.writeAsBytes([0x7f, 0x45, 0x4c, 0x46]);

    await testCodeBuildHook(
      mainMethod: (arguments) => build(
        arguments,
        (input, output) => bundleDesktopBridge(input, output),
      ),
      targetOS: .linux,
      targetArchitecture: .x64,
      userDefines: .new(
        workspacePubspec: .new(
          defines: {'desktop_artifact': source.path},
          basePath: Directory.current.uri,
        ),
      ),
      check: (input, output) async {
        expect(output.assets.code, hasLength(1));
        final asset = output.assets.code.single;
        expect(
          asset.id,
          'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart',
        );
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        expect(await File.fromUri(asset.file!).readAsBytes(), [
          0x7f,
          0x45,
          0x4c,
          0x46,
        ]);
      },
    );
  });

  test('archive extraction accepts only the declared regular file', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'maplibre-archive-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final artifact = parseDesktopArtifactManifest(
      File('hook/desktop_artifacts.json').readAsStringSync(),
    ).artifacts.first;
    final validArchive = File('${temporaryDirectory.path}/valid.tar.gz');
    final output = File('${temporaryDirectory.path}/libmaplibre_bridge.so');
    await _writeArchive(validArchive, [
      .bytes(artifact.archiveMember, [1, 2, 3]),
    ]);

    await extractDesktopArchive(validArchive, artifact, output);
    expect(await output.readAsBytes(), [1, 2, 3]);

    final unexpectedArchive = File(
      '${temporaryDirectory.path}/unexpected.tar.gz',
    );
    await _writeArchive(unexpectedArchive, [
      .bytes('../maplibre_bridge.so', [1]),
    ]);
    await expectLater(
      extractDesktopArchive(unexpectedArchive, artifact, output),
      throwsStateError,
    );

    final linkedArchive = File('${temporaryDirectory.path}/linked.tar.gz');
    await _writeArchive(linkedArchive, [
      .symlink(artifact.archiveMember, '/tmp/bridge'),
    ]);
    await expectLater(
      extractDesktopArchive(linkedArchive, artifact, output),
      throwsStateError,
    );
  });
}

Future<void> _writeArchive(File file, List<ArchiveFile> entries) async {
  final archive = Archive();
  for (final entry in entries) {
    archive.add(entry);
  }
  final tarBytes = TarEncoder().encodeBytes(archive);
  final compressed = GZipEncoder().encodeBytes(tarBytes);
  await file.writeAsBytes(compressed, flush: true);
}

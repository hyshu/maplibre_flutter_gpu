import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = input.packageRoot;
    final impellerc = await _findImpellerc();
    final shaderDirectory = packageRoot.resolve('shaders/');
    final manifestFile = shaderDirectory.resolve(
      'OverlayShaders.shaderbundle.json',
    );
    final outputDirectory = Directory.fromUri(
      packageRoot.resolve('assets/shaderbundles/'),
    );
    await outputDirectory.create(recursive: true);

    final manifest = jsonDecode(
      await File.fromUri(manifestFile).readAsString(),
    ) as Map<String, dynamic>;
    output.dependencies.add(manifestFile);
    for (final entry in manifest.values) {
      final shader = entry as Map<String, dynamic>;
      final source = shaderDirectory.resolve(shader['file'] as String);
      output.dependencies.add(source);
      shader['file'] = source.toFilePath();
    }

    final shaderLibrary = impellerc.resolve('./shader_lib');
    final outputFile = outputDirectory.uri.resolve(
      'OverlayShaders.shaderbundle',
    );
    final result = await Process.run(impellerc.toFilePath(), <String>[
      '--sl=${outputFile.toFilePath()}',
      '--shader-bundle=${jsonEncode(manifest)}',
      '--include=${shaderLibrary.toFilePath()}',
      '--gles-language-version=300',
    ], workingDirectory: packageRoot.toFilePath());
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to build OverlayShaders: ${result.stderr}\n${result.stdout}',
      );
    }
  });
}

Future<Uri> _findImpellerc() async {
  final dartExecutable = Uri.file(Platform.resolvedExecutable);
  Uri? cacheDirectory;
  for (var i = dartExecutable.pathSegments.length - 1; i >= 0; i--) {
    final segment = dartExecutable.pathSegments[i];
    if (segment == 'dart-sdk' || segment == 'artifacts') {
      cacheDirectory = dartExecutable.replace(
        pathSegments: <String>[
          ...dartExecutable.pathSegments.sublist(0, i),
          '',
        ],
      );
      break;
    }
  }
  if (cacheDirectory == null) {
    throw StateError('Unable to find the Flutter SDK cache directory');
  }

  final engineArtifacts = cacheDirectory.resolve('artifacts/engine/');
  final candidate = switch (Platform.operatingSystem) {
    'linux' => 'linux-x64/impellerc',
    'macos' => 'darwin-x64/impellerc',
    'windows' => 'windows-x64/impellerc.exe',
    final platform => throw UnsupportedError(
      'Shader compilation is not supported on $platform',
    ),
  };
  final executable = engineArtifacts.resolve(candidate);
  if (await File.fromUri(executable).exists()) {
    return executable;
  }
  throw StateError('Unable to find impellerc at ${executable.toFilePath()}');
}

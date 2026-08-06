import 'dart:convert';
import 'dart:io';

import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = input.packageRoot;

    // Find impellerc in the Flutter SDK.
    final dartExec = Uri.file(Platform.resolvedExecutable);
    Uri? cacheDir;
    for (var i = dartExec.pathSegments.length - 1; i >= 0; i--) {
      if (dartExec.pathSegments[i] == 'dart-sdk' ||
          dartExec.pathSegments[i] == 'artifacts') {
        cacheDir = dartExec.replace(
          pathSegments: dartExec.pathSegments.sublist(0, i) + [''],
        );
        break;
      }
    }
    if (cacheDir == null) {
      throw Exception('Unable to find Flutter SDK cache directory');
    }

    final engineArtifactsDir = cacheDir.resolve('./artifacts/engine/');
    final impellercLocation = switch (Platform.operatingSystem) {
      'linux' => 'linux-x64/impellerc',
      'macos' => 'darwin-x64/impellerc',
      'windows' => 'windows-x64/impellerc.exe',
      final platform => throw UnsupportedError(
        'Shader compilation is not supported on $platform',
      ),
    };
    final impellercExec = engineArtifactsDir.resolve(impellercLocation);
    if (!await File(impellercExec.toFilePath()).exists()) {
      throw Exception(
        'Unable to find impellerc at ${impellercExec.toFilePath()}',
      );
    }

    final shadersDir = packageRoot.resolve('shaders/');
    final outDir = Directory.fromUri(
      packageRoot.resolve('build/shaderbundles/'),
    );
    await outDir.create(recursive: true);
    final shaderLibPath = impellercExec.resolve('./shader_lib');

    // Build all shader bundles
    for (final name in ['MapShaders']) {
      final manifestFile = shadersDir.resolve('$name.shaderbundle.json');
      if (!await File(manifestFile.toFilePath()).exists()) continue;

      final manifest = await File(manifestFile.toFilePath()).readAsString();
      final decodedManifest = json.decode(manifest) as Map<String, dynamic>;

      // Declare inputs so the hooks framework reruns this hook when the
      // manifest or any shader source changes (otherwise the cached bundle
      // is reused and shader edits silently don't take effect).
      output.dependencies.add(manifestFile);
      for (final entry in decodedManifest.values) {
        if (entry is Map<String, dynamic> && entry.containsKey('file')) {
          final relPath = entry['file'] as String;
          final resolved = shadersDir.resolve(relPath);
          output.dependencies.add(resolved);
          entry['file'] = resolved.toFilePath();
        }
      }

      final resolvedManifest = json.encode(decodedManifest);
      final outFile = outDir.uri.resolve('$name.shaderbundle');

      final result = Process.runSync(impellercExec.toFilePath(), [
        '--sl=${outFile.toFilePath()}',
        '--shader-bundle=$resolvedManifest',
        '--include=${shaderLibPath.toFilePath()}',
        // Data-driven uint uniforms and bitwise masks require GLSL ES 3.00
        // on Impeller's OpenGLES backend.
        '--gles-language-version=300',
      ], workingDirectory: packageRoot.toFilePath());
      if (result.exitCode != 0) {
        throw Exception(
          'Failed to build $name: ${result.stderr}\n${result.stdout}',
        );
      }
    }
  });
}

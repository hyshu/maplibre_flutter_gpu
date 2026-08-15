import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const _maximumArchiveBytes = 128 * 1024 * 1024;
const _manifestPath = 'hook/desktop_artifacts.json';

/// Describes one immutable desktop bridge archive.
final class DesktopArtifact {
  const DesktopArtifact({
    required this.operatingSystem,
    required this.architecture,
    required this.archiveName,
    required this.archiveMember,
    required this.libraryName,
    required this.sha256,
  });

  final OS operatingSystem;
  final Architecture architecture;
  final String archiveName;
  final String archiveMember;
  final String libraryName;
  final String sha256;
}

final class DesktopArtifactManifest {
  const DesktopArtifactManifest({
    required this.baseUrl,
    required this.artifacts,
  });

  final String baseUrl;
  final List<DesktopArtifact> artifacts;
}

/// Bundles the bridge matching the requested desktop target.
Future<void> bundleDesktopBridge(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;

  final codeConfig = input.config.code;
  final targetOS = codeConfig.targetOS;
  if (targetOS != OS.linux && targetOS != OS.windows) return;

  final manifestFile = File.fromUri(input.packageRoot.resolve(_manifestPath));
  output.dependencies.add(manifestFile.uri);
  final manifest = parseDesktopArtifactManifest(
    await manifestFile.readAsString(),
  );
  final artifact = manifest.artifacts.where((candidate) {
    return candidate.operatingSystem == targetOS &&
        candidate.architecture == codeConfig.targetArchitecture;
  }).firstOrNull;
  if (artifact == null) {
    throw UnsupportedError(
      'No MapLibre bridge is available for '
      '${targetOS.name}-${codeConfig.targetArchitecture.name}',
    );
  }

  final outputFile = File.fromUri(
    input.outputDirectory.resolve(artifact.libraryName),
  );
  await outputFile.parent.create(recursive: true);

  final customArtifact = input.userDefines.path('desktop_artifact');
  if (input.userDefines['desktop_artifact'] != null && customArtifact == null) {
    throw const FormatException(
      'hooks.user_defines.maplibre_flutter_gpu.desktop_artifact '
      'must be a file path',
    );
  }

  if (customArtifact != null) {
    final customFile = File.fromUri(customArtifact);
    output.dependencies.add(customFile.uri);
    await _copyLocalArtifact(customFile, outputFile);
  } else {
    final repositoryFile = File.fromUri(
      input.packageRoot.resolve(artifact.archiveMember),
    );
    if (await repositoryFile.exists()) {
      output.dependencies.add(repositoryFile.uri);
      await _copyLocalArtifact(repositoryFile, outputFile);
    } else {
      final archive = await _downloadArtifact(input, manifest, artifact);
      await extractDesktopArchive(archive, artifact, outputFile);
    }
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/native/maplibre_ffi.dart',
      linkMode: DynamicLoadingBundled(),
      file: outputFile.uri,
    ),
  );
}

/// Extracts the single expected bridge from [archiveFile].
Future<void> extractDesktopArchive(
  File archiveFile,
  DesktopArtifact artifact,
  File outputFile,
) async {
  final compressedBytes = await archiveFile.readAsBytes();
  if (compressedBytes.length > _maximumArchiveBytes) {
    throw StateError('Desktop artifact exceeds the 128 MiB safety limit');
  }

  final tarBytes = GZipDecoder().decodeBytes(compressedBytes, verify: true);
  final archive = TarDecoder().decodeBytes(tarBytes, verify: true);
  if (archive.files.length != 1) {
    throw StateError(
      '${artifact.archiveName} must contain exactly one regular file',
    );
  }

  final entry = archive.files.single;
  if (!entry.isFile ||
      entry.isSymbolicLink ||
      entry.name != artifact.archiveMember) {
    throw StateError(
      '${artifact.archiveName} contains an unexpected entry: ${entry.name}',
    );
  }
  final bytes = entry.readBytes();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('${artifact.archiveName} contains an empty bridge');
  }

  await outputFile.writeAsBytes(bytes, flush: true);
}

Future<File> _downloadArtifact(
  BuildInput input,
  DesktopArtifactManifest manifest,
  DesktopArtifact artifact,
) async {
  final customBaseUrl = input.userDefines['desktop_artifact_base_url'];
  if (customBaseUrl is! String? ||
      (customBaseUrl is String && customBaseUrl.trim().isEmpty)) {
    throw const FormatException(
      'hooks.user_defines.maplibre_flutter_gpu.desktop_artifact_base_url '
      'must be a non-empty URL',
    );
  }
  final baseUrl = _directoryUri(customBaseUrl ?? manifest.baseUrl);
  final artifactUrl = baseUrl.resolve(artifact.archiveName);
  if (artifactUrl.scheme != 'https' ||
      artifactUrl.host.isEmpty ||
      artifactUrl.userInfo.isNotEmpty) {
    throw FormatException('Desktop artifact URL must use HTTPS: $artifactUrl');
  }

  final cacheDirectory = Directory.fromUri(
    input.outputDirectoryShared.resolve('desktop/${artifact.sha256}/'),
  );
  await cacheDirectory.create(recursive: true);
  final archiveFile = File.fromUri(
    cacheDirectory.uri.resolve(artifact.archiveName),
  );
  if (await archiveFile.exists() &&
      await _sha256File(archiveFile) == artifact.sha256) {
    return archiveFile;
  }

  final partialFile = File('${archiveFile.path}.partial');
  if (await partialFile.exists()) await partialFile.delete();
  await _downloadHttps(artifactUrl, partialFile);
  final actualHash = await _sha256File(partialFile);
  if (actualHash != artifact.sha256) {
    await partialFile.delete();
    throw StateError(
      'Checksum mismatch for ${artifact.archiveName}. '
      'Expected ${artifact.sha256}, found $actualHash.',
    );
  }
  if (await archiveFile.exists()) await archiveFile.delete();
  await partialFile.rename(archiveFile.path);

  return archiveFile;
}

/// Parses and validates the checked-in immutable artifact manifest.
DesktopArtifactManifest parseDesktopArtifactManifest(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, Object?> || root['schemaVersion'] != 1) {
    throw const FormatException('Unsupported desktop artifact manifest');
  }
  final baseUrl = root['baseUrl'];
  final entries = root['artifacts'];
  if (baseUrl is! String || entries is! List<Object?>) {
    throw const FormatException('Invalid desktop artifact manifest');
  }
  final artifacts = entries
      .map((entry) {
        if (entry is! Map<String, Object?>) {
          throw const FormatException('Invalid desktop artifact entry');
        }
        final os = switch (entry['os']) {
          'linux' => OS.linux,
          'windows' => OS.windows,
          _ => throw const FormatException('Unsupported desktop artifact OS'),
        };
        final architecture = switch (entry['architecture']) {
          'x64' => Architecture.x64,
          'arm64' => Architecture.arm64,
          _ => throw const FormatException('Unsupported desktop architecture'),
        };
        String field(String name) {
          final value = entry[name];
          if (value is! String || value.isEmpty) {
            throw FormatException('Invalid desktop artifact field: $name');
          }

          return value;
        }

        final hash = field('sha256');
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
          throw const FormatException('Invalid desktop artifact checksum');
        }

        return DesktopArtifact(
          operatingSystem: os,
          architecture: architecture,
          archiveName: field('archive'),
          archiveMember: field('member'),
          libraryName: field('library'),
          sha256: hash,
        );
      })
      .toList(growable: false);
  final targets = artifacts
      .map(
        (artifact) =>
            '${artifact.operatingSystem.name}-${artifact.architecture.name}',
      )
      .toSet();
  if (artifacts.length != 4 || targets.length != 4) {
    throw const FormatException(
      'Desktop manifest must define four unique targets',
    );
  }

  return DesktopArtifactManifest(baseUrl: baseUrl, artifacts: artifacts);
}

Future<void> _copyLocalArtifact(File source, File destination) async {
  if (!await source.exists() || await source.length() == 0) {
    throw StateError('Desktop artifact is missing or empty: ${source.path}');
  }
  await source.copy(destination.path);
}

Uri _directoryUri(String value) {
  final normalized = value.endsWith('/') ? value : '$value/';

  return Uri.parse(normalized);
}

Future<String> _sha256File(File file) async {
  final digest = await sha256.bind(file.openRead()).first;

  return digest.toString();
}

Future<void> _downloadHttps(Uri initialUrl, File destination) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  var currentUrl = initialUrl;
  try {
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = await client
          .getUrl(currentUrl)
          .timeout(const Duration(seconds: 30));
      request
        ..followRedirects = false
        ..headers.set(
          HttpHeaders.userAgentHeader,
          'maplibre_flutter_gpu build hook',
        );
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) {
          throw HttpException('Redirect is missing Location', uri: currentUrl);
        }
        final nextUrl = currentUrl.resolve(location);
        if (nextUrl.scheme != 'https' || nextUrl.userInfo.isNotEmpty) {
          throw HttpException('Unsafe artifact redirect', uri: nextUrl);
        }
        currentUrl = nextUrl;
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Artifact download returned HTTP ${response.statusCode}',
          uri: currentUrl,
        );
      }
      if (response.contentLength > _maximumArchiveBytes) {
        await response.drain<void>();
        throw HttpException('Desktop artifact is too large', uri: currentUrl);
      }

      await response.pipe(destination.openWrite());
      if (await destination.length() > _maximumArchiveBytes) {
        await destination.delete();
        throw HttpException('Desktop artifact is too large', uri: currentUrl);
      }

      return;
    }
    throw HttpException('Too many artifact redirects', uri: currentUrl);
  } finally {
    client.close(force: true);
  }
}

bool _isRedirect(int statusCode) =>
    statusCode == HttpStatus.movedPermanently ||
    statusCode == HttpStatus.found ||
    statusCode == HttpStatus.seeOther ||
    statusCode == HttpStatus.temporaryRedirect ||
    statusCode == HttpStatus.permanentRedirect;

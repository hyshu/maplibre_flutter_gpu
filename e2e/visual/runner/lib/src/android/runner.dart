import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:visual_e2e_runner/src/android_drive.dart';
import 'package:visual_e2e_runner/visual_e2e_runner.dart';

part 'comparison.dart';
part 'device_driver.dart';
part 'metadata.dart';
part 'options.dart';
part 'performance.dart';
part 'scene_gates.dart';
part 'summary.dart';

/// Runs Android capture and visual gates, returning a process exit code.
///
/// Relative input and output paths are resolved from [repositoryRoot]. A failed
/// visual gate returns 1. Invalid options and failed commands throw for the CLI
/// entry point to report.
Future<int> runAndroidVisualComparison(
  List<String> arguments, {
  required String repositoryRoot,
}) async {
  final parser = _createArgumentParser();
  final parsed = parser.parse(arguments);
  if (parsed.flag('help')) {
    stdout
      ..writeln('Android MapLibre visual E2E')
      ..writeln(parser.usage);

    return 0;
  }

  final sceneId = parsed.option('scene')!;
  final minimumSimilarity = parsed.option('minimum-similarity') == null
      ? _sceneMinimumSimilarity[sceneId] ?? 0.998
      : _parseFraction(
          parsed.option('minimum-similarity')!,
          'minimum-similarity',
        );
  final colorThreshold = _parseFraction(
    parsed.option('color-threshold')!,
    'color-threshold',
  );
  final minimumContentRetention = _parseFraction(
    parsed.option('minimum-content-retention')!,
    'minimum-content-retention',
  );
  final minimumContentRatio = parsed.option('minimum-content-ratio') == null
      ? _sceneMinimumContentRatio[sceneId] ?? 0
      : _parseFraction(
          parsed.option('minimum-content-ratio')!,
          'minimum-content-ratio',
        );
  final minimumForegroundSimilarity =
      parsed.option('minimum-foreground-similarity') == null
      ? _symbolSceneMinimumForegroundSimilarity[sceneId] ?? 0
      : _parseFraction(
          parsed.option('minimum-foreground-similarity')!,
          'minimum-foreground-similarity',
        );
  final zoom = _parseZoom(parsed.option('zoom'));
  final outputOption = parsed.option('output')!;
  final outputPath = _resolveOptionalPath(outputOption, repositoryRoot)!;
  final outputDirectory = Directory(outputPath);
  final imagesDirectory = Directory(path.join(outputPath, 'images'));
  final logsDirectory = Directory(path.join(outputPath, 'logs'));
  final maplibreGlApk = _resolveOptionalPath(
    parsed.option('maplibre-gl-apk'),
    repositoryRoot,
  );
  final gpuApk = _resolveOptionalPath(parsed.option('gpu-apk'), repositoryRoot);
  final performanceReference = _resolveOptionalPath(
    parsed.option('performance-reference'),
    repositoryRoot,
  );
  final performanceActual = _resolveOptionalPath(
    parsed.option('performance-actual'),
    repositoryRoot,
  );
  if ((maplibreGlApk == null) != (gpuApk == null)) {
    throw const FormatException(
      '--maplibre-gl-apk and --gpu-apk must be provided together',
    );
  }
  if ((performanceReference == null) != (performanceActual == null)) {
    throw const FormatException(
      '--performance-reference and --performance-actual must be provided '
      'together',
    );
  }
  for (final apk in [maplibreGlApk, gpuApk]) {
    if (apk != null && !await File(apk).exists()) {
      throw FormatException('prebuilt APK does not exist: $apk');
    }
  }
  await imagesDirectory.create(recursive: true);
  await logsDirectory.create(recursive: true);

  final skipDrive = parsed.flag('skip-drive');
  String? device = parsed.option('device');
  String? adb;
  String? flutter;

  if (!skipDrive) {
    final capture = await _driveApplications(
      repositoryRoot: repositoryRoot,
      imagesDirectory: imagesDirectory,
      logsDirectory: logsDirectory,
      outputDirectory: outputDirectory,
      sceneId: sceneId,
      zoom: zoom,
      maplibreGlApk: maplibreGlApk,
      gpuApk: gpuApk,
      device: device,
    );
    flutter = capture.flutter;
    adb = capture.adb;
    device = capture.device;
  }

  final referenceFile = File(
    path.join(imagesDirectory.path, 'maplibre_gl.png'),
  );
  final actualFile = File(path.join(imagesDirectory.path, 'gpu.png'));
  if (!await referenceFile.exists() || !await actualFile.exists()) {
    throw StateError(
      'both screenshots are required: '
      '${referenceFile.path}, ${actualFile.path}',
    );
  }

  final referencePng = Uint8List.fromList(await referenceFile.readAsBytes());
  final actualPng = Uint8List.fromList(await actualFile.readAsBytes());
  final result = _compareSceneScreenshots(
    referencePng: referencePng,
    actualPng: actualPng,
    sceneId: sceneId,
    colorThreshold: colorThreshold,
    includeAntiAlias: parsed.flag('include-antialiasing'),
  );
  final comparison = result.pixels;
  final foregroundRegion = result.foregroundRegion;
  final focusedForegroundResults = result.focusedForegroundResults;
  final referenceContentRatio = result.referenceContentRatio;
  final actualContentRatio = result.actualContentRatio;
  final contentRetention = result.contentRetention;
  final foregroundSimilarity = result.foregroundSimilarity;
  final additionalGatePassed =
      contentRetention >= minimumContentRetention &&
      referenceContentRatio >= minimumContentRatio &&
      actualContentRatio >= minimumContentRatio &&
      foregroundSimilarity >= minimumForegroundSimilarity &&
      result.focusedForegroundPassed;
  final performanceComparison =
      performanceReference == null || performanceActual == null
      ? null
      : await _readPerformanceComparison(
          referencePath: performanceReference,
          actualPath: performanceActual,
        );
  final metadata = await _collectMetadata(
    repositoryRoot: repositoryRoot,
    flutter: flutter ?? _findFlutter(required: false),
    adb: adb,
    device: device,
    sceneId: sceneId,
    zoom: zoom,
    screenshotWidth: comparison.width,
    screenshotHeight: comparison.height,
  );
  await writeVisualReport(
    outputDirectory: outputDirectory,
    comparison: comparison,
    minimumSimilarity: minimumSimilarity,
    sceneId: sceneId,
    platform: parsed.option('platform')!,
    metadata: metadata,
    extraResults: {
      'referenceContentRatio': referenceContentRatio,
      'actualContentRatio': actualContentRatio,
      'contentRetention': contentRetention,
      'minimumContentRetention': minimumContentRetention,
      'minimumContentRatio': minimumContentRatio,
      'minimumForegroundSimilarity': minimumForegroundSimilarity,
      if (foregroundRegion != null)
        'foregroundRegion': foregroundRegion.toJson(),
      if (focusedForegroundResults.isNotEmpty)
        'focusedForegroundGates': [
          for (final entry in focusedForegroundResults)
            {
              'region': entry.gate.region.toJson(),
              'similarity': entry.similarity,
              'minimumSimilarity': entry.gate.minimumSimilarity,
              'passed': entry.similarity >= entry.gate.minimumSimilarity,
              if (entry.orientation != null)
                'colorOrientation': entry.orientation!.toJson(),
              if (entry.colorPresence != null)
                'actualColorPresence': entry.colorPresence!.toJson(),
            },
        ],
      'zoom': ?zoom,
    },
    performanceComparison: performanceComparison,
    additionalGatePassed: additionalGatePassed,
  );

  _printComparisonSummary(
    outputDirectory: outputDirectory,
    result: result,
    minimumSimilarity: minimumSimilarity,
    minimumContentRetention: minimumContentRetention,
    minimumContentRatio: minimumContentRatio,
    minimumForegroundSimilarity: minimumForegroundSimilarity,
    performanceComparison: performanceComparison,
  );

  return comparison.similarity >= minimumSimilarity && additionalGatePassed
      ? 0
      : 1;
}

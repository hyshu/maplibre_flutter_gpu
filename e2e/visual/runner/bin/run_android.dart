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

const _maplibreGlVersion = '0.26.2';
const _visualBackground = PixelColor(0xe7, 0xed, 0xf3);

const _symbolSceneMinimumForegroundSimilarity = <String, double>{
  'text-symbol': 0.45,
  'symbol-data-driven-paint': 0.55,
  'symbol-paint-update': 0.40,
  'symbol-line-pitch': 0.30,
  'symbol-icon-effects': 0.55,
  'symbol-layer-order': 0.70,
  'symbol-z-order': 0.60,
  'symbol-text-shaping': 0.25,
};

const _sceneMinimumSimilarity = <String, double>{
  'text-symbol': 0.970,
  'symbol-data-driven-paint': 0.950,
  'symbol-paint-update': 0.950,
  'symbol-line-pitch': 0.950,
  'symbol-icon-effects': 0.950,
  'symbol-layer-order': 0.950,
  'symbol-z-order': 0.950,
  'symbol-text-shaping': 0.800,
};

const _sceneMinimumContentRatio = <String, double>{
  'symbol-data-driven-paint': 0.0005,
  'symbol-paint-update': 0.001,
  'symbol-line-pitch': 0.0005,
  'symbol-icon-effects': 0.005,
  'symbol-layer-order': 0.003,
  'symbol-z-order': 0.01,
  'symbol-text-shaping': 0.01,
};

const _sceneForegroundRegion = <String, NormalizedPixelRegion>{
  'symbol-z-order': NormalizedPixelRegion(
    left: 0.27,
    top: 0.46,
    right: 0.72,
    bottom: 0.55,
    label: 'overlap centers for both ordering paths',
  ),
  'symbol-text-shaping': NormalizedPixelRegion(
    left: 0.05,
    top: 0.55,
    right: 0.95,
    bottom: 0.69,
    label: 'mixed bidirectional text',
  ),
};

const _sceneFocusedForegroundGates = <String, List<_FocusedForegroundGate>>{
  'symbol-data-driven-paint': <_FocusedForegroundGate>[
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.25,
        top: 0.425,
        right: 0.30,
        bottom: 0.448,
        label: 'NAVY icon color and opacity',
      ),
      targetColor: PixelColor(0x36, 0x62, 0xe3),
      channelThreshold: 12,
      minimumPixelCount: 100,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.697,
        top: 0.425,
        right: 0.747,
        bottom: 0.448,
        label: 'ORANGE icon color and opacity',
      ),
      targetColor: PixelColor(0xe7, 0x9c, 0x64),
      channelThreshold: 12,
      minimumPixelCount: 100,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.25,
        top: 0.552,
        right: 0.30,
        bottom: 0.575,
        label: 'GREEN icon color and opacity',
      ),
      targetColor: PixelColor(0x5b, 0xac, 0x6a),
      channelThreshold: 12,
      minimumPixelCount: 100,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.697,
        top: 0.552,
        right: 0.747,
        bottom: 0.575,
        label: 'PURPLE icon color and opacity',
      ),
      targetColor: PixelColor(0xb2, 0x89, 0xe8),
      channelThreshold: 12,
      minimumPixelCount: 100,
    ),
  ],
  'symbol-paint-update': <_FocusedForegroundGate>[
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.43,
        top: 0.42,
        right: 0.57,
        bottom: 0.49,
        label: 'updated icon fill',
      ),
      targetColor: PixelColor(0x39, 0x82, 0xc2),
      channelThreshold: 12,
      minimumPixelCount: 500,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.43,
        top: 0.42,
        right: 0.57,
        bottom: 0.49,
        label: 'updated icon halo',
      ),
      targetColor: PixelColor(0xe9, 0x7b, 0x35),
      channelThreshold: 12,
      minimumPixelCount: 50,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.615,
        right: 0.88,
        bottom: 0.66,
        label: 'updated text fill',
      ),
      targetColor: PixelColor(0xb1, 0x35, 0xcc),
      channelThreshold: 12,
      minimumPixelCount: 200,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.615,
        right: 0.88,
        bottom: 0.66,
        label: 'updated text halo',
      ),
      targetColor: PixelColor(0xfc, 0xf1, 0x97),
      channelThreshold: 12,
      minimumPixelCount: 500,
    ),
  ],
  'symbol-line-pitch': <_FocusedForegroundGate>[
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.54,
        top: 0.36,
        right: 0.67,
        bottom: 0.45,
        label: 'icon-only line symbol',
      ),
      minimumSimilarity: 0.40,
    ),
    _FocusedForegroundGate.colorOrientation(
      region: NormalizedPixelRegion(
        left: 0.15,
        top: 0.64,
        right: 0.38,
        bottom: 0.78,
        label: 'single-glyph map-aligned line text',
      ),
      minimumSimilarity: 0.85,
      targetColor: PixelColor(0x02, 0x84, 0xc7),
      channelThreshold: 70,
      minimumPixelCount: 20,
      minimumElongation: 1.5,
    ),
  ],
  'symbol-icon-effects': <_FocusedForegroundGate>[
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.43,
        top: 0.35,
        right: 0.92,
        bottom: 0.48,
        label: 'asymmetric nine-patch text fit',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.13,
        top: 0.34,
        right: 0.40,
        bottom: 0.43,
        label: 'small proportional nine-patch fit',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.47,
        top: 0.55,
        right: 0.69,
        bottom: 0.65,
        label: 'natural 64 by 48 nine-patch',
      ),
      minimumSimilarity: 0.50,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.62,
        right: 0.85,
        bottom: 0.88,
        label: 'uniformly scaled nine-patch without text fit',
      ),
      minimumSimilarity: 0.50,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.63,
        top: 0.49,
        right: 0.98,
        bottom: 0.63,
        label: 'map-anchored point translation',
      ),
      minimumSimilarity: 0.40,
    ),
  ],
  'symbol-layer-order': <_FocusedForegroundGate>[
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.40,
        right: 0.35,
        bottom: 0.49,
        label: 'widget stratum slot 1',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.425,
        top: 0.40,
        right: 0.575,
        bottom: 0.49,
        label: 'widget stratum slot 2',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.65,
        top: 0.40,
        right: 0.80,
        bottom: 0.49,
        label: 'widget stratum slot 3',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.51,
        right: 0.35,
        bottom: 0.60,
        label: 'widget stratum slot 4',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.425,
        top: 0.51,
        right: 0.575,
        bottom: 0.60,
        label: 'widget stratum slot 5',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.65,
        top: 0.51,
        right: 0.80,
        bottom: 0.60,
        label: 'widget stratum slot 6',
      ),
      minimumSimilarity: 0.45,
    ),
  ],
  'symbol-text-shaping': <_FocusedForegroundGate>[
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.02,
        top: 0.13,
        right: 0.98,
        bottom: 0.33,
        label: 'padded left and right multiline text',
      ),
      minimumSimilarity: 0.25,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.02,
        top: 0.48,
        right: 0.98,
        bottom: 0.58,
        label: 'formatted mixed RTL line sections',
      ),
      minimumSimilarity: 0.20,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.21,
        top: 0.405,
        right: 0.25,
        bottom: 0.435,
        label: 'formatted inline SDF halo',
      ),
      targetColor: PixelColor(0xfa, 0xcc, 0x15),
      channelThreshold: 64,
      minimumPixelCount: 120,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.50,
        top: 0.30,
        right: 0.55,
        bottom: 0.33,
        label: 'formatted inline raster image',
      ),
      targetColor: PixelColor(0xd9, 0x72, 0x00),
      channelThreshold: 64,
      minimumPixelCount: 200,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.70,
        top: 0.25,
        right: 0.82,
        bottom: 0.38,
        label: 'vertical CJK widget text',
      ),
      targetColor: PixelColor(0x7c, 0x2d, 0x12),
      channelThreshold: 32,
      minimumPixelCount: 2000,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.35,
        top: 0.39,
        right: 0.68,
        bottom: 0.52,
        label: 'asymmetric variable anchor offset',
      ),
      minimumSimilarity: 0.24,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.08,
        top: 0.68,
        right: 0.92,
        bottom: 0.93,
        label: 'long UTF-8 widget export boundary',
      ),
      minimumSimilarity: 0.30,
    ),
  ],
};

final class _FocusedForegroundGate {
  const new({
    required this.region,
    required this.minimumSimilarity,
  }) : metric = .foregroundSimilarity,
       targetColor = null,
       channelThreshold = 0,
       minimumPixelCount = 0,
       minimumElongation = 0;

  const new colorOrientation({
    required this.region,
    required this.minimumSimilarity,
    required this.targetColor,
    this.channelThreshold = 16,
    required this.minimumPixelCount,
    required this.minimumElongation,
  }) : metric = .colorOrientation;

  const new actualColorPresence({
    required this.region,
    required this.targetColor,
    this.channelThreshold = 16,
    required this.minimumPixelCount,
  }) : metric = .actualColorPresence,
       minimumSimilarity = 1,
       minimumElongation = 0;

  final NormalizedPixelRegion region;
  final double minimumSimilarity;
  final _FocusedGateMetric metric;
  final PixelColor? targetColor;
  final int channelThreshold;
  final int minimumPixelCount;
  final double minimumElongation;
}

enum _FocusedGateMetric {
  foregroundSimilarity,
  colorOrientation,
  actualColorPresence,
}

final class _FocusedForegroundResult {
  const new({
    required this.gate,
    required this.similarity,
    this.orientation,
    this.colorPresence,
  });

  final _FocusedForegroundGate gate;
  final double similarity;
  final ColorOrientationMatchResult? orientation;
  final ColorPresenceResult? colorPresence;
}

Future<void> main(List<String> arguments) async {
  try {
    exitCode = await _run(arguments);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exitCode = 2;
  } on ProcessException catch (error) {
    stderr.writeln('error: $error');
    exitCode = 2;
  } catch (error, stackTrace) {
    stderr
      ..writeln('error: $error')
      ..writeln(stackTrace);
    exitCode = 2;
  }
}

Future<int> _run(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('device', abbr: 'd', help: 'Android device serial.')
    ..addOption(
      'scene',
      defaultsTo: 'geometry',
      allowed: const [
        'geometry',
        'text-symbol',
        'symbol-data-driven-paint',
        'symbol-paint-update',
        'symbol-line-pitch',
        'symbol-icon-effects',
        'symbol-layer-order',
        'symbol-z-order',
        'symbol-text-shaping',
        '3d-buildings',
        'flutter-markers',
        'mvt',
        'tilejson-mvt',
        'image-source',
        'geojson-url',
        'raster-jpeg',
        'raster-webp',
        'raster-tms',
        'wmts',
      ],
    )
    ..addOption('zoom', help: 'Optional camera zoom override.')
    ..addOption(
      'minimum-similarity',
      help:
          'Required substantial-pixel similarity in the range 0..1. '
          'Defaults to a scene-specific threshold.',
    )
    ..addOption(
      'color-threshold',
      defaultsTo: '0.05',
      help: 'Pixelmatch YIQ color threshold in the range 0..1.',
    )
    ..addOption(
      'minimum-content-retention',
      defaultsTo: '0',
      help:
          'Required GPU non-background pixel ratio relative to the reference '
          'in the range 0..1.',
    )
    ..addOption(
      'minimum-content-ratio',
      help:
          'Required non-background pixel ratio in both screenshots, '
          'in the range 0..1. Defaults to a scene-specific threshold.',
    )
    ..addOption(
      'minimum-foreground-similarity',
      help:
          'Required similarity over the union of non-background pixels. '
          'Symbol scenes use a calibrated default; other scenes default to 0.',
    )
    ..addOption(
      'output',
      defaultsTo: 'e2e/visual/report',
      help: 'Report output directory, relative to repository root.',
    )
    ..addOption(
      'platform',
      defaultsTo: 'Android',
      allowed: const ['Android', 'iOS', 'macOS'],
      help: 'Platform label shown in the generated report.',
    )
    ..addOption(
      'maplibre-gl-apk',
      help:
          'Prebuilt maplibre_gl integration-test APK, relative to the '
          'repository root.',
    )
    ..addOption(
      'gpu-apk',
      help:
          'Prebuilt maplibre_flutter_gpu integration-test APK, relative to '
          'the repository root.',
    )
    ..addOption(
      'performance-reference',
      help: 'Optional maplibre_gl integration response JSON.',
    )
    ..addOption(
      'performance-actual',
      help: 'Optional maplibre_flutter_gpu integration response JSON.',
    )
    ..addFlag(
      'include-antialiasing',
      defaultsTo: false,
      help: 'Count detected anti-alias differences as mismatches.',
    )
    ..addFlag(
      'skip-drive',
      defaultsTo: false,
      help: 'Reuse existing images in the output directory.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
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
  final runnerRoot = path.dirname(path.dirname(Platform.script.toFilePath()));
  final repositoryRoot = path.normalize(path.join(runnerRoot, '../../..'));
  final outputOption = parsed.option('output')!;
  final outputPath = path.isAbsolute(outputOption)
      ? path.normalize(outputOption)
      : path.normalize(path.join(repositoryRoot, outputOption));
  final outputDirectory = Directory(outputPath);
  final imagesDirectory = Directory(path.join(outputPath, 'images'));
  final logsDirectory = Directory(path.join(outputPath, 'logs'));
  final maplibreGlApk = _resolvePrebuiltApk(
    parsed.option('maplibre-gl-apk'),
    repositoryRoot,
  );
  final gpuApk = _resolvePrebuiltApk(parsed.option('gpu-apk'), repositoryRoot);
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
    flutter = _findFlutter();
    adb = _findAdb();
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
          environment: {
            'VISUAL_E2E_SCREENSHOT_DIR': imagesDirectory.path,
          },
          logFile: File(
            path.join(logsDirectory.path, '${application.label}-drive.log'),
          ),
        );
      } finally {
        await _forceStop(adb, device, application.applicationId);
      }
    }
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
  final foregroundRegion = _sceneForegroundRegion[sceneId];
  final comparison = comparePngBytes(
    referencePng: referencePng,
    actualPng: actualPng,
    options: .new(
      colorThreshold: colorThreshold,
      includeAntiAlias: parsed.flag('include-antialiasing'),
      foregroundBackground: _visualBackground,
      foregroundRegion: foregroundRegion,
    ),
  );
  final foregroundSimilarity = comparison.foreground!.similarity;
  final focusedForegroundResults = <_FocusedForegroundResult>[];
  for (final gate
      in _sceneFocusedForegroundGates[sceneId] ?? const []) {
    final targetColor = gate.targetColor;
    if (gate.metric == .colorOrientation) {
      final orientation = compareColorOrientationPngBytes(
        referencePng: referencePng,
        actualPng: actualPng,
        targetColor: targetColor!,
        region: gate.region,
        channelThreshold: gate.channelThreshold,
        minimumPixelCount: gate.minimumPixelCount,
        minimumElongation: gate.minimumElongation,
      );
      focusedForegroundResults.add(
        .new(
          gate: gate,
          similarity: orientation.similarity,
          orientation: orientation,
        ),
      );
      continue;
    }
    if (gate.metric == .actualColorPresence) {
      final presence = analyzeColorPresencePngBytes(
        png: actualPng,
        targetColor: targetColor!,
        region: gate.region,
        channelThreshold: gate.channelThreshold,
      );
      focusedForegroundResults.add(
        .new(
          gate: gate,
          similarity: math.min(1, presence.pixelCount / gate.minimumPixelCount),
          colorPresence: presence,
        ),
      );
      continue;
    }

    final foreground = comparePngBytes(
      referencePng: referencePng,
      actualPng: actualPng,
      options: .new(
        colorThreshold: colorThreshold,
        includeAntiAlias: parsed.flag('include-antialiasing'),
        foregroundBackground: _visualBackground,
        foregroundRegion: gate.region,
      ),
    ).foreground!;
    focusedForegroundResults.add(
      .new(gate: gate, similarity: foreground.similarity),
    );
  }
  final focusedForegroundPassed = focusedForegroundResults.every(
    (entry) => entry.similarity >= entry.gate.minimumSimilarity,
  );
  final referenceContentRatio = pngContentRatio(
    png: referencePng,
    backgroundRed: 0xe7,
    backgroundGreen: 0xed,
    backgroundBlue: 0xf3,
  );
  final actualContentRatio = pngContentRatio(
    png: actualPng,
    backgroundRed: 0xe7,
    backgroundGreen: 0xed,
    backgroundBlue: 0xf3,
  );
  final contentRetention = referenceContentRatio == 0
      ? 1.0
      : actualContentRatio / referenceContentRatio;
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
    additionalGatePassed:
        contentRetention >= minimumContentRetention &&
        referenceContentRatio >= minimumContentRatio &&
        actualContentRatio >= minimumContentRatio &&
        foregroundSimilarity >= minimumForegroundSimilarity &&
        focusedForegroundPassed,
  );

  final reportPath = path.join(outputDirectory.path, 'index.html');
  final similarity = (comparison.similarity * 100).toStringAsFixed(3);
  final strictSimilarity = (comparison.strictSimilarity * 100).toStringAsFixed(
    3,
  );
  final required = (minimumSimilarity * 100).toStringAsFixed(3);
  final primaryLabel = comparison.options.includeAntiAlias
      ? 'Strict similarity'
      : 'AA-adjusted similarity';
  stdout
    ..writeln('\n$primaryLabel: $similarity% (required $required%)')
    ..writeln('Strict similarity: $strictSimilarity%')
    ..writeln(
      'Content retention: ${(contentRetention * 100).toStringAsFixed(3)}% '
      '(required '
      '${(minimumContentRetention * 100).toStringAsFixed(3)}%)',
    )
    ..writeln(
      'Reference/actual content: '
      '${(referenceContentRatio * 100).toStringAsFixed(3)}% / '
      '${(actualContentRatio * 100).toStringAsFixed(3)}% '
      '(required ${(minimumContentRatio * 100).toStringAsFixed(3)}%)',
    )
    ..writeln(
      'Foreground similarity: '
      '${(foregroundSimilarity * 100).toStringAsFixed(3)}% '
      '(required '
      '${(minimumForegroundSimilarity * 100).toStringAsFixed(3)}%)',
    )
    ..writeln('Report: $reportPath');
  for (final entry in focusedForegroundResults) {
    stdout.writeln(
      'Focused foreground ${entry.gate.region.label}: '
      '${(entry.similarity * 100).toStringAsFixed(3)}% '
      '(required '
      '${(entry.gate.minimumSimilarity * 100).toStringAsFixed(3)}%)',
    );
  }
  if (performanceComparison != null) {
    final reference =
        performanceComparison['reference']! as Map<String, Object?>;
    final actual = performanceComparison['actual']! as Map<String, Object?>;
    stdout.writeln(
      'Camera step FPS: '
      '${_metric(reference, 'camera_step_fps').toStringAsFixed(2)} / '
      '${_metric(actual, 'camera_step_fps').toStringAsFixed(2)} '
      '(maplibre_gl / GPU)',
    );
  }
  return comparison.similarity >= minimumSimilarity &&
          contentRetention >= minimumContentRetention &&
          referenceContentRatio >= minimumContentRatio &&
          actualContentRatio >= minimumContentRatio &&
          foregroundSimilarity >= minimumForegroundSimilarity &&
          focusedForegroundPassed
      ? 0
      : 1;
}

String? _resolvePrebuiltApk(String? option, String repositoryRoot) {
  if (option == null) return null;

  return path.isAbsolute(option)
      ? path.normalize(option)
      : path.normalize(path.join(repositoryRoot, option));
}

String? _resolveOptionalPath(String? option, String repositoryRoot) {
  if (option == null) return null;

  return path.isAbsolute(option)
      ? path.normalize(option)
      : path.normalize(path.join(repositoryRoot, option));
}

Future<Map<String, Object?>> _readPerformanceResult(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw FormatException('performance result does not exist: $filePath');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('performance result must be an object: $filePath');
  }
  final metrics = decoded['visual_performance'];
  if (metrics is! Map<String, dynamic>) {
    throw FormatException('visual_performance is missing from: $filePath');
  }
  return metrics.cast<String, Object?>();
}

Future<Map<String, Object?>> _readPerformanceComparison({
  required String referencePath,
  required String actualPath,
}) async => {
  'reference': await _readPerformanceResult(referencePath),
  'actual': await _readPerformanceResult(actualPath),
};

double _metric(Map<String, Object?> metrics, String key) {
  final value = metrics[key];

  return value is num ? value.toDouble() : 0;
}

double _parseFraction(String raw, String optionName) {
  final value = double.tryParse(raw);
  if (value == null || value < 0 || value > 1) {
    throw FormatException('--$optionName must be a number from 0 to 1');
  }
  return value;
}

double? _parseZoom(String? raw) {
  if (raw == null) return null;
  final value = double.tryParse(raw);
  if (value == null || value < 0 || value > 24) {
    throw const FormatException('--zoom must be a number from 0 to 24');
  }
  return value;
}

Future<void> _removeStaleFile(File file) async {
  if (await file.exists()) await file.delete();
}

Future<void> _forceStop(String adb, String device, String applicationId) async {
  try {
    await Process.run(adb, ['-s', device, 'shell', 'am', 'force-stop', applicationId]);
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

Future<Map<String, Object?>> _collectMetadata({
  required String repositoryRoot,
  required String flutter,
  required String? adb,
  required String? device,
  required String sceneId,
  required double? zoom,
  required int screenshotWidth,
  required int screenshotHeight,
}) async {
  final styleFile = File(
    path.join(repositoryRoot, 'e2e/visual/shared/assets/scenes/$sceneId.json'),
  );
  final metadata = <String, Object?>{
    'scene': sceneId,
    'zoom': ?zoom,
    'styleSha256': sha256.convert(await styleFile.readAsBytes()).toString(),
    'maplibreGlVersion': _maplibreGlVersion,
    'repositoryCommit': await _commandOutput(
      'git',
      const ['rev-parse', 'HEAD'],
      workingDirectory: repositoryRoot,
    ),
    'maplibreFlutterGpuVersion': await _readPackageVersion(
      File(path.join(repositoryRoot, 'pubspec.yaml')),
    ),
    'gpuMapLibreNativeRevision': await _commandOutput(
      'git',
      const ['rev-parse', 'HEAD'],
      workingDirectory: path.join(repositoryRoot, 'vendor/maplibre-native'),
      fallback: 'public prebuilt / unavailable',
    ),
    'screenshotSize': '${screenshotWidth}x$screenshotHeight',
    'controlHandling': '24 logical px symmetric overscan clips native controls',
  };

  final flutterMachine = await _commandOutput(
    flutter,
    const ['--version', '--machine'],
    fallback: '',
  );
  if (flutterMachine.isNotEmpty) {
    try {
      final decoded = jsonDecode(flutterMachine) as Map<String, dynamic>;
      metadata['flutterVersion'] = decoded['frameworkVersion'];
      metadata['dartVersion'] = decoded['dartSdkVersion'];
      metadata['flutterEngineRevision'] = decoded['engineRevision'];
    } on FormatException {
      metadata['flutterVersion'] = flutterMachine;
    }
  }

  if (adb != null && device != null) {
    metadata['deviceSerial'] = device;
    metadata['deviceModel'] = await _adbOutput(
      adb,
      device,
      const ['shell', 'getprop', 'ro.product.model'],
    );
    metadata['androidApi'] = await _adbOutput(
      adb,
      device,
      const ['shell', 'getprop', 'ro.build.version.sdk'],
    );
    metadata['displaySize'] = await _adbOutput(
      adb,
      device,
      const ['shell', 'wm', 'size'],
    );
    metadata['displayDensity'] = await _adbOutput(
      adb,
      device,
      const ['shell', 'wm', 'density'],
    );
    metadata['glesRenderer'] = await _adbOutput(
      adb,
      device,
      const ['shell', 'getprop', 'ro.hardware.egl'],
    );
  }
  return metadata;
}

Future<String> _readPackageVersion(File pubspec) async {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(await pubspec.readAsString());

  return match?.group(1) ?? 'unknown';
}

Future<String> _adbOutput(String adb, String device, List<String> arguments) =>
    _commandOutput(adb, ['-s', device, ...arguments]);

Future<String> _commandOutput(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String fallback = 'unknown',
}) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode == 0) return (result.stdout as String).trim();
  } on ProcessException {
    // Metadata collection must not hide the visual comparison result.
  }
  return fallback;
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

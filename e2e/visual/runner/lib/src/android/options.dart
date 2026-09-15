part of 'runner.dart';

ArgParser _createArgumentParser() => ArgParser()
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

String? _resolveOptionalPath(String? option, String repositoryRoot) {
  if (option == null) return null;

  return path.isAbsolute(option)
      ? path.normalize(option)
      : path.normalize(path.join(repositoryRoot, option));
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

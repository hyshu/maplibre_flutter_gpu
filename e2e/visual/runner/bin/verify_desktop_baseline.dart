// Compares a desktop visual-E2E screenshot against a committed baseline PNG.
//
// This is the refactor guard that `verify_desktop_smoke.dart` cannot provide:
// the smoke check only asserts that *something* was drawn, so a change that
// corrupts UBO offsets, pass ordering, or vertex strides still passes it. A
// baseline diff catches those, because the expected output is a fixed image
// captured before the change.
//
// Capture a baseline with `--update-baseline`, review the PNG by eye, and
// commit it. Afterwards every run compares against it.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:visual_e2e_runner/visual_e2e_runner.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('screenshot', mandatory: true, help: 'Actual run PNG.')
    ..addOption('baseline', mandatory: true, help: 'Committed baseline PNG.')
    ..addOption('output', mandatory: true, help: 'Report directory.')
    ..addOption('platform', defaultsTo: 'macOS')
    ..addOption('scene', defaultsTo: 'geometry')
    // Both gates default to bit-exact. A baseline is compared against the same
    // renderer on the same machine, so any drift is a regression until proven
    // to be GPU nondeterminism. For calibration: two *different* renderers
    // (this repo's gpu.png vs maplibre_gl.png) still score 99.92% similar, so
    // a 0.999-style gate would wave through a large visual regression.
    ..addOption(
      'minimum-similarity',
      defaultsTo: '1.0',
      help: 'Fraction of pixels that must match the baseline.',
    )
    ..addOption(
      'color-threshold',
      defaultsTo: '0.0',
      help: 'Pixelmatch YIQ color threshold in the range 0..1.',
    )
    ..addFlag(
      'include-antialiasing',
      defaultsTo: false,
      help: 'Count detected anti-alias differences as mismatches.',
    )
    ..addFlag(
      'update-baseline',
      defaultsTo: false,
      negatable: false,
      help: 'Overwrite the baseline with this run instead of comparing.',
    );

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 2;

    return;
  }

  final screenshot = File(options.option('screenshot')!);
  final baseline = File(options.option('baseline')!);
  final platform = options.option('platform')!;
  final scene = options.option('scene')!;

  if (!await screenshot.exists()) {
    stderr.writeln('$platform screenshot missing: ${screenshot.path}');
    exitCode = 2;

    return;
  }

  if (options.flag('update-baseline')) {
    await baseline.parent.create(recursive: true);
    await screenshot.copy(baseline.path);
    stdout.writeln('Baseline updated: ${baseline.path}');
    stdout.writeln('Review the image by eye before committing it.');

    return;
  }

  if (!await baseline.exists()) {
    stderr.writeln('No baseline for $platform/$scene: ${baseline.path}');
    stderr.writeln(
      'Capture one on a known-good commit with --update-baseline, verify it '
      'visually, then commit it.',
    );
    exitCode = 2;

    return;
  }

  final minimumSimilarity = _parseUnitInterval(
    options.option('minimum-similarity')!,
    'minimum-similarity',
  );
  final colorThreshold = _parseUnitInterval(
    options.option('color-threshold')!,
    'color-threshold',
  );
  if (minimumSimilarity == null || colorThreshold == null) {
    exitCode = 2;

    return;
  }

  final PixelMatchResult comparison;
  try {
    final actualPng = await screenshot.readAsBytes();
    final referencePng = normalizeReferencePngSize(
      referencePng: await baseline.readAsBytes(),
      actualPng: actualPng,
    );
    comparison = comparePngBytes(
      referencePng: referencePng,
      actualPng: actualPng,
      options: .new(
        colorThreshold: colorThreshold,
        includeAntiAlias: options.flag('include-antialiasing'),
      ),
    );
  } on ArgumentError catch (error) {
    stderr.writeln('$platform baseline comparison failed: ${error.message}');
    exitCode = 1;

    return;
  } on FormatException catch (error) {
    stderr.writeln('$platform baseline comparison failed: ${error.message}');
    exitCode = 2;

    return;
  }

  final output = Directory(options.option('output')!);
  final images = Directory(path.join(output.path, 'images'));
  await images.create(recursive: true);
  await File(path.join(images.path, 'baseline.png'))
      .writeAsBytes(await baseline.readAsBytes(), flush: true);
  await File(path.join(images.path, 'baseline-diff.png'))
      .writeAsBytes(comparison.diffPng, flush: true);

  final passed = comparison.similarity >= minimumSimilarity;
  final result = {
    'status': passed ? 'passed' : 'failed',
    'platform': platform,
    'scene': scene,
    'minimumSimilarity': minimumSimilarity,
    'baseline': path.relative(baseline.path, from: output.path),
    'comparison': comparison.toJson(),
  };
  const encoder = JsonEncoder.withIndent('  ');
  await File(path.join(output.path, 'baseline-results.json'))
      .writeAsString('${encoder.convert(result)}\n', flush: true);

  stdout.writeln(
    '$platform baseline similarity: '
    '${(comparison.similarity * 100).toStringAsFixed(4)}% '
    '(required ${(minimumSimilarity * 100).toStringAsFixed(4)}%)',
  );
  stdout.writeln(
    'mismatched ${comparison.mismatchPixelCount} of '
    '${comparison.comparedPixelCount} px · '
    'p95 channel delta ${comparison.p95MaxChannelDelta}',
  );
  if (!passed) {
    stderr.writeln(
      'Diff image: ${path.join(images.path, 'baseline-diff.png')}',
    );
  }
  exitCode = passed ? 0 : 1;
}

double? _parseUnitInterval(String raw, String name) {
  final value = double.tryParse(raw);
  if (value == null || value.isNaN || value < 0 || value > 1) {
    stderr.writeln('--$name must be a number in the range 0..1 (got "$raw")');

    return null;
  }
  return value;
}

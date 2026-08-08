import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;
import 'package:visual_e2e_runner/visual_e2e_runner.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('screenshot', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('platform', defaultsTo: 'macOS')
    ..addOption('scene', defaultsTo: 'geometry')
    ..addOption('minimum-content-ratio', defaultsTo: '0.01')
    ..addOption('expected-width', defaultsTo: '1600')
    ..addOption('expected-height', defaultsTo: '1200')
    ..addOption('minimum-channel-range', defaultsTo: '16');
  final options = parser.parse(arguments);
  final screenshot = File(options.option('screenshot')!);
  final output = Directory(options.option('output')!);
  final platform = options.option('platform')!;
  final scene = options.option('scene')!;
  final minimumContentRatio = double.parse(
    options.option('minimum-content-ratio')!,
  );
  final expectedWidth = int.parse(options.option('expected-width')!);
  final expectedHeight = int.parse(options.option('expected-height')!);
  final minimumChannelRange = int.parse(
    options.option('minimum-channel-range')!,
  );

  if (!await screenshot.exists()) {
    stderr.writeln('$platform screenshot missing: ${screenshot.path}');
    exitCode = 2;

    return;
  }
  late final PngSmokeMetrics metrics;
  try {
    metrics = analyzePngSmoke(
      png: await screenshot.readAsBytes(),
      backgroundRed: 0xe7,
      backgroundGreen: 0xed,
      backgroundBlue: 0xf3,
    );
  } on FormatException {
    stderr.writeln(
      '$platform screenshot is not a valid PNG: ${screenshot.path}',
    );
    exitCode = 2;

    return;
  }
  final passed = metrics.passes(
    expectedWidth: expectedWidth,
    expectedHeight: expectedHeight,
    minimumContentRatio: minimumContentRatio,
    minimumChannelRange: minimumChannelRange,
  );

  await output.create(recursive: true);
  final relativeScreenshot = path.relative(screenshot.path, from: output.path);
  final result = <String, Object?>{
    'status': passed ? 'passed' : 'failed',
    'platform': platform,
    'scene': scene,
    'screenshot': relativeScreenshot,
    'width': metrics.width,
    'height': metrics.height,
    'expectedWidth': expectedWidth,
    'expectedHeight': expectedHeight,
    'contentPixels': metrics.contentPixels,
    'totalPixels': metrics.totalPixels,
    'contentRatio': metrics.contentRatio,
    'minimumContentRatio': minimumContentRatio,
    'maximumChannelRange': metrics.maximumChannelRange,
    'minimumChannelRange': minimumChannelRange,
  };
  const encoder = JsonEncoder.withIndent('  ');
  await File(
    path.join(output.path, 'results.json'),
  ).writeAsString('${encoder.convert(result)}\n');
  await File(path.join(output.path, 'index.html')).writeAsString('''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>$platform MapLibre visual smoke: ${passed ? 'PASS' : 'FAIL'}</title>
  <style>
    body { margin: 0; padding: 24px; background: #0e1621; color: #e8eef5; font-family: system-ui, sans-serif; }
    main { max-width: 1200px; margin: auto; }
    .status { color: ${passed ? '#8df0c4' : '#ffb2bf'}; font-size: 2rem; font-weight: 800; }
    img { display: block; max-width: 100%; height: auto; border: 1px solid #2a3a4e; }
    code { color: #a9c7ef; }
  </style>
</head>
<body><main>
  <div class="status">${passed ? 'PASS' : 'FAIL'}</div>
  <h1>$platform maplibre_flutter_gpu visual smoke</h1>
  <p>$scene scene · ${metrics.width}×${metrics.height} · rendered content ${(metrics.contentRatio * 100).toStringAsFixed(3)}% · channel range ${metrics.maximumChannelRange}</p>
  <img src="${Uri.encodeFull(relativeScreenshot)}" alt="$platform map render">
</main></body>
</html>
''');

  stdout.writeln(
    '$platform rendered content: '
    '${(metrics.contentRatio * 100).toStringAsFixed(3)}% '
    '(required ${(minimumContentRatio * 100).toStringAsFixed(3)}%), '
    'size ${metrics.width}x${metrics.height} '
    '(required ${expectedWidth}x$expectedHeight), '
    'channel range ${metrics.maximumChannelRange} '
    '(required $minimumChannelRange)',
  );
  stdout.writeln('Report: ${path.join(output.path, 'index.html')}');
  exitCode = passed ? 0 : 1;
}

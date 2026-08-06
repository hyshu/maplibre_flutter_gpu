import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('screenshot', mandatory: true)
    ..addOption('output', mandatory: true)
    ..addOption('platform', defaultsTo: 'macOS')
    ..addOption('scene', defaultsTo: 'geometry')
    ..addOption('minimum-content-ratio', defaultsTo: '0.01');
  final options = parser.parse(arguments);
  final screenshot = File(options.option('screenshot')!);
  final output = Directory(options.option('output')!);
  final platform = options.option('platform')!;
  final scene = options.option('scene')!;
  final minimumContentRatio = double.parse(
    options.option('minimum-content-ratio')!,
  );

  if (!await screenshot.exists()) {
    stderr.writeln('$platform screenshot missing: ${screenshot.path}');
    exitCode = 2;

    return;
  }
  final decoded = image.decodePng(await screenshot.readAsBytes());
  if (decoded == null) {
    stderr.writeln(
      '$platform screenshot is not a valid PNG: ${screenshot.path}',
    );
    exitCode = 2;

    return;
  }

  const background = (r: 0xe7, g: 0xed, b: 0xf3);
  var contentPixels = 0;
  for (final pixel in decoded) {
    final delta = <num>[
      (pixel.r - background.r).abs(),
      (pixel.g - background.g).abs(),
      (pixel.b - background.b).abs(),
    ].reduce((a, b) => a > b ? a : b);
    if (delta > 8) contentPixels++;
  }
  final totalPixels = decoded.width * decoded.height;
  final contentRatio = contentPixels / totalPixels;
  final passed =
      decoded.width >= 800 &&
      decoded.height >= 600 &&
      contentRatio >= minimumContentRatio;

  await output.create(recursive: true);
  final relativeScreenshot = path.relative(screenshot.path, from: output.path);
  final result = <String, Object?>{
    'status': passed ? 'passed' : 'failed',
    'platform': platform,
    'scene': scene,
    'screenshot': relativeScreenshot,
    'width': decoded.width,
    'height': decoded.height,
    'contentPixels': contentPixels,
    'totalPixels': totalPixels,
    'contentRatio': contentRatio,
    'minimumContentRatio': minimumContentRatio,
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
  <p>$scene scene · ${decoded.width}×${decoded.height} · rendered content ${(contentRatio * 100).toStringAsFixed(3)}%</p>
  <img src="${Uri.encodeFull(relativeScreenshot)}" alt="$platform map render">
</main></body>
</html>
''');

  stdout.writeln(
    '$platform rendered content: ${(contentRatio * 100).toStringAsFixed(3)}% '
    '(required ${(minimumContentRatio * 100).toStringAsFixed(3)}%)',
  );
  stdout.writeln('Report: ${path.join(output.path, 'index.html')}');
  exitCode = passed ? 0 : 1;
}

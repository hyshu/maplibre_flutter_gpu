import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:test/test.dart';

void main() {
  test('prebuilt APK options must be provided together', () async {
    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--maplibre-gl-apk=missing.apk',
    ]);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('must be provided together'));
  });

  test('prebuilt APK paths must exist', () async {
    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--maplibre-gl-apk=missing-maplibre-gl.apk',
      '--gpu-apk=missing-gpu.apk',
    ]);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('prebuilt APK does not exist'));
  });

  test('performance options must be provided together', () async {
    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--performance-reference=reference.json',
    ]);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('must be provided together'));
  });

  test('data-driven icon gates reject an opaque feature fallback', () async {
    final output = await Directory.systemTemp.createTemp(
      'visual-e2e-data-driven-paint-',
    );
    addTearDown(() => output.delete(recursive: true));
    final reference = _backgroundImage();
    final icons = <String, ((int, int), image.ColorRgb8)>{
      'NAVY icon color and opacity': ((150, 383), _navyRendered),
      'ORANGE icon color and opacity': ((419, 383), _orangeRendered),
      'GREEN icon color and opacity': ((150, 498), _greenRendered),
      'PURPLE icon color and opacity': ((419, 498), _purpleRendered),
    };
    for (final entry in icons.values) {
      _fillRect(
        reference,
        left: entry.$1.$1,
        top: entry.$1.$2,
        width: 25,
        height: 16,
        color: entry.$2,
      );
    }
    final actual = image.Image.from(reference);
    _fillRect(
      actual,
      left: 419,
      top: 383,
      width: 25,
      height: 16,
      color: _opaqueOrangeRendered,
    );
    await _writeComparison(output, reference: reference, actual: actual);

    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--scene=symbol-data-driven-paint',
      '--output=${output.path}',
    ]);

    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    final report = await _readReport(output);
    expect(_comparison(report)['similarity']! as num, greaterThan(0.95));
    expect(
      (_comparison(report)['foreground']!
              as Map<String, Object?>)['similarity']!
          as num,
      greaterThan(0.55),
    );
    expect(
      _focusedGate(report, 'ORANGE icon color and opacity')['passed'],
      isFalse,
    );
    for (final label in icons.keys.where(
      (label) => !label.startsWith('ORANGE'),
    )) {
      expect(_focusedGate(report, label)['passed'], isTrue);
    }

    await _writeComparison(
      output,
      reference: reference,
      actual: image.Image.from(reference),
    );
    final passingResult = await _runAndroid(<String>[
      '--skip-drive',
      '--scene=symbol-data-driven-paint',
      '--output=${output.path}',
    ]);
    expect(
      passingResult.exitCode,
      0,
      reason: '${passingResult.stdout}\n${passingResult.stderr}',
    );
  });

  test('paint-update color gates reject stale text paint', () async {
    final output = await Directory.systemTemp.createTemp(
      'visual-e2e-paint-update-',
    );
    addTearDown(() => output.delete(recursive: true));
    final reference = _backgroundImage();
    _fillRect(
      reference,
      left: 270,
      top: 390,
      width: 30,
      height: 20,
      color: _updatedBlue,
    );
    _fillRect(
      reference,
      left: 310,
      top: 390,
      width: 10,
      height: 10,
      color: _updatedOrange,
    );
    _fillRect(
      reference,
      left: 150,
      top: 565,
      width: 20,
      height: 15,
      color: _updatedMagenta,
    );
    _fillRect(
      reference,
      left: 200,
      top: 565,
      width: 30,
      height: 20,
      color: _updatedYellow,
    );
    final actual = image.Image.from(reference);
    _fillRect(
      actual,
      left: 150,
      top: 565,
      width: 20,
      height: 15,
      color: _stalePaint,
    );
    await _writeComparison(output, reference: reference, actual: actual);

    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--scene=symbol-paint-update',
      '--output=${output.path}',
    ]);

    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    final report = await _readReport(output);
    expect(_comparison(report)['similarity']! as num, greaterThan(0.95));
    expect(
      (_comparison(report)['foreground']!
              as Map<String, Object?>)['similarity']!
          as num,
      greaterThan(0.40),
    );
    expect(_focusedGate(report, 'updated text fill')['passed'], isFalse);
    expect(_focusedGate(report, 'updated icon fill')['passed'], isTrue);
    expect(_focusedGate(report, 'updated icon halo')['passed'], isTrue);
    expect(_focusedGate(report, 'updated text halo')['passed'], isTrue);

    await _writeComparison(
      output,
      reference: reference,
      actual: image.Image.from(reference),
    );
    final passingResult = await _runAndroid(<String>[
      '--skip-drive',
      '--scene=symbol-paint-update',
      '--output=${output.path}',
    ]);
    expect(
      passingResult.exitCode,
      0,
      reason: '${passingResult.stdout}\n${passingResult.stderr}',
    );
  });

  test('inline SDF halo focused gate catches a missing halo', () async {
    final output = await Directory.systemTemp.createTemp(
      'visual-e2e-inline-sdf-',
    );
    addTearDown(() => output.delete(recursive: true));
    final reference = _backgroundImage();
    _fillRect(
      reference,
      left: 270,
      top: 510,
      width: 120,
      height: 90,
      color: _teal,
    );
    _fillRect(
      reference,
      left: 435,
      top: 300,
      width: 55,
      height: 40,
      color: _cjkBrown,
    );
    _fillRect(
      reference,
      left: 310,
      top: 275,
      width: 18,
      height: 15,
      color: _inlineRasterOrange,
    );
    _drawInlineSdfCircle(reference, haloColor: _yellow);
    final actual = image.Image.from(reference);
    _drawInlineSdfCircle(actual, haloColor: _background);
    await _writeComparison(output, reference: reference, actual: actual);

    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--scene=symbol-text-shaping',
      '--output=${output.path}',
    ]);

    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('formatted inline SDF halo'));
    final report = await _readReport(output);
    expect(_comparison(report)['similarity']! as num, greaterThan(0.95));
    expect(report['contentRetention']! as num, greaterThan(0.70));
    expect(
      (_comparison(report)['foreground']!
          as Map<String, Object?>)['similarity'],
      1,
    );
    expect(
      _focusedGate(report, 'formatted inline SDF halo')['passed'],
      isFalse,
    );
    expect(
      (_focusedGate(report, 'formatted inline SDF halo')['actualColorPresence']!
          as Map<String, Object?>)['pixelCount'],
      0,
    );

    await _writeComparison(
      output,
      reference: reference,
      actual: image.Image.from(reference),
    );
    final passingResult = await _runAndroid(<String>[
      '--skip-drive',
      '--scene=symbol-text-shaping',
      '--output=${output.path}',
    ]);

    expect(
      passingResult.exitCode,
      0,
      reason: '${passingResult.stdout}\n${passingResult.stderr}',
    );
    expect(
      _focusedGate(
        await _readReport(output),
        'formatted inline SDF halo',
      )['passed'],
      isTrue,
    );
  });

  test('each text-shaping fixture has an independent focused gate', () async {
    final output = await Directory.systemTemp.createTemp(
      'visual-e2e-text-shaping-',
    );
    addTearDown(() => output.delete(recursive: true));
    final reference = _backgroundImage();
    _fillRect(
      reference,
      left: 250,
      top: 530,
      width: 100,
      height: 70,
      color: _teal,
    );
    final fixtures =
        <
          String,
          ({int left, int top, int width, int height, image.Color color})
        >{
          'padded left and right multiline text': (
            left: 100,
            top: 170,
            width: 50,
            height: 30,
            color: _teal,
          ),
          'formatted mixed RTL line sections': (
            left: 100,
            top: 450,
            width: 30,
            height: 30,
            color: _teal,
          ),
          'asymmetric variable anchor offset': (
            left: 300,
            top: 380,
            width: 30,
            height: 30,
            color: _teal,
          ),
          'long UTF-8 widget export boundary': (
            left: 100,
            top: 700,
            width: 30,
            height: 30,
            color: _teal,
          ),
          'vertical CJK widget text': (
            left: 435,
            top: 300,
            width: 55,
            height: 40,
            color: _cjkBrown,
          ),
          'formatted inline raster image': (
            left: 310,
            top: 275,
            width: 18,
            height: 15,
            color: _inlineRasterOrange,
          ),
        };
    for (final fixture in fixtures.values) {
      _fillRect(
        reference,
        left: fixture.left,
        top: fixture.top,
        width: fixture.width,
        height: fixture.height,
        color: fixture.color,
      );
    }
    _drawInlineSdfCircle(reference, haloColor: _yellow);

    for (final MapEntry(key: label, value: fixture) in fixtures.entries) {
      final actual = image.Image.from(reference);
      _fillRect(
        actual,
        left: fixture.left,
        top: fixture.top,
        width: fixture.width,
        height: fixture.height,
        color: _background,
      );
      await _writeComparison(output, reference: reference, actual: actual);

      final result = await _runAndroid(<String>[
        '--skip-drive',
        '--scene=symbol-text-shaping',
        '--output=${output.path}',
      ]);

      expect(result.exitCode, 1, reason: '$label\n${result.stdout}');
      expect(_focusedGate(await _readReport(output), label)['passed'], isFalse);
    }
  });

  test('each layer-order slot has an independent focused gate', () async {
    final output = await Directory.systemTemp.createTemp(
      'visual-e2e-layer-order-',
    );
    addTearDown(() => output.delete(recursive: true));
    final reference = _backgroundImage();
    const centers = <(int, int)>[
      (165, 400),
      (300, 400),
      (435, 400),
      (165, 500),
      (300, 500),
      (435, 500),
    ];
    for (final (x, y) in centers) {
      _fillRect(
        reference,
        left: x - 20,
        top: y - 20,
        width: 40,
        height: 40,
        color: _teal,
      );
    }
    final actual = image.Image.from(reference);
    final (wrongX, wrongY) = centers.last;
    _fillRect(
      actual,
      left: wrongX - 20,
      top: wrongY - 20,
      width: 40,
      height: 40,
      color: _orange,
    );
    await _writeComparison(output, reference: reference, actual: actual);

    final result = await _runAndroid(<String>[
      '--skip-drive',
      '--scene=symbol-layer-order',
      '--output=${output.path}',
    ]);

    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('widget stratum slot 6'));
    final report = await _readReport(output);
    expect(_comparison(report)['similarity']! as num, greaterThan(0.95));
    expect(
      (_comparison(report)['foreground']!
              as Map<String, Object?>)['similarity']!
          as num,
      greaterThan(0.70),
    );
    expect(_focusedGate(report, 'widget stratum slot 6')['passed'], isFalse);
    for (var slot = 1; slot <= 5; slot++) {
      expect(
        result.stdout,
        contains('Focused foreground widget stratum slot $slot: 100.000%'),
      );
      expect(
        _focusedGate(report, 'widget stratum slot $slot')['passed'],
        isTrue,
      );
    }
  });

  test(
    'line text orientation gate ignores placement and rejects reversal',
    () async {
      final output = await Directory.systemTemp.createTemp(
        'visual-e2e-line-orientation-',
      );
      addTearDown(() => output.delete(recursive: true));
      final reference = _backgroundImage();
      _drawLineGlyph(
        reference,
        top: (120, 595),
        corner: (128, 665),
        end: (185, 653),
      );
      final translated = _backgroundImage();
      _drawLineGlyph(
        translated,
        top: (150, 585),
        corner: (158, 655),
        end: (215, 643),
      );
      await _writeComparison(output, reference: reference, actual: translated);

      final translatedResult = await _runAndroid(<String>[
        '--skip-drive',
        '--scene=symbol-line-pitch',
        '--minimum-foreground-similarity=0',
        '--output=${output.path}',
      ]);

      expect(
        translatedResult.exitCode,
        0,
        reason: '${translatedResult.stdout}\n${translatedResult.stderr}',
      );
      final translatedReport = await _readReport(output);
      expect(
        _focusedGate(
          translatedReport,
          'single-glyph map-aligned line text',
        )['passed'],
        isTrue,
      );

      final reversed = _backgroundImage();
      _drawLineGlyph(
        reversed,
        top: (150, 585),
        corner: (190, 645),
        end: (222, 595),
      );
      await _writeComparison(output, reference: reference, actual: reversed);

      final reversedResult = await _runAndroid(<String>[
        '--skip-drive',
        '--scene=symbol-line-pitch',
        '--minimum-foreground-similarity=0',
        '--output=${output.path}',
      ]);

      expect(
        reversedResult.exitCode,
        1,
        reason: '${reversedResult.stdout}\n${reversedResult.stderr}',
      );
      final reversedGate = _focusedGate(
        await _readReport(output),
        'single-glyph map-aligned line text',
      );
      expect(reversedGate['passed'], isFalse);
      expect(reversedGate['similarity']! as num, lessThan(0.85));
      expect(
        (reversedGate['colorOrientation']!
                as Map<String, Object?>)['orientationDifferenceDegrees']!
            as num,
        greaterThan(13.5),
      );
    },
  );
}

final _background = image.ColorRgb8(231, 237, 243);
final _teal = image.ColorRgb8(15, 118, 110);
final _yellow = image.ColorRgb8(250, 204, 21);
final _cjkBrown = image.ColorRgb8(124, 45, 18);
final _inlineRasterOrange = image.ColorRgb8(217, 114, 0);
final _orange = image.ColorRgb8(249, 115, 22);
final _blue = image.ColorRgb8(2, 132, 199);
final _navyRendered = image.ColorRgb8(0x36, 0x62, 0xe3);
final _orangeRendered = image.ColorRgb8(0xe7, 0x9c, 0x64);
final _greenRendered = image.ColorRgb8(0x5b, 0xac, 0x6a);
final _purpleRendered = image.ColorRgb8(0xb2, 0x89, 0xe8);
final _opaqueOrangeRendered = image.ColorRgb8(0xe9, 0x7b, 0x35);
final _updatedBlue = image.ColorRgb8(0x39, 0x82, 0xc2);
final _updatedOrange = image.ColorRgb8(0xe9, 0x7b, 0x35);
final _updatedMagenta = image.ColorRgb8(0xb1, 0x35, 0xcc);
final _updatedYellow = image.ColorRgb8(0xfc, 0xf1, 0x97);
final _stalePaint = image.ColorRgb8(0x64, 0x74, 0x8b);

image.Image _backgroundImage() {
  final result = image.Image(width: 600, height: 900);
  image.fill(result, color: _background);

  return result;
}

void _fillRect(
  image.Image target, {
  required int left,
  required int top,
  required int width,
  required int height,
  required image.Color color,
}) {
  image.fillRect(
    target,
    x1: left,
    y1: top,
    x2: left + width - 1,
    y2: top + height - 1,
    color: color,
  );
}

void _drawInlineSdfCircle(
  image.Image target, {
  required image.Color haloColor,
}) {
  image.fillCircle(target, x: 138, y: 378, radius: 10, color: haloColor);
  image.fillCircle(target, x: 138, y: 378, radius: 7, color: _teal);
}

void _drawLineGlyph(
  image.Image target, {
  required (int, int) top,
  required (int, int) corner,
  required (int, int) end,
}) {
  image.drawLine(
    target,
    x1: top.$1,
    y1: top.$2,
    x2: corner.$1,
    y2: corner.$2,
    color: _blue,
    thickness: 10,
  );
  image.drawLine(
    target,
    x1: corner.$1,
    y1: corner.$2,
    x2: end.$1,
    y2: end.$2,
    color: _blue,
    thickness: 10,
  );
}

Future<void> _writeComparison(
  Directory output, {
  required image.Image reference,
  required image.Image actual,
}) async {
  final images = Directory('${output.path}/images');
  await images.create(recursive: true);
  await File('${images.path}/maplibre_gl.png')
      .writeAsBytes(image.encodePng(reference), flush: true);
  await File('${images.path}/gpu.png')
      .writeAsBytes(image.encodePng(actual), flush: true);
}

Future<Map<String, Object?>> _readReport(Directory output) async {
  return jsonDecode(await File('${output.path}/results.json').readAsString())
      as Map<String, Object?>;
}

Map<String, Object?> _comparison(Map<String, Object?> report) {
  return report['comparison']! as Map<String, Object?>;
}

Map<String, Object?> _focusedGate(Map<String, Object?> report, String label) {
  return (report['focusedForegroundGates']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere(
        (gate) => (gate['region']! as Map<String, Object?>)['label'] == label,
      );
}

Future<ProcessResult> _runAndroid(List<String> arguments) {
  return Process.run(Platform.resolvedExecutable, <String>[
    'run',
    'bin/run_android.dart',
    ...arguments,
  ], workingDirectory: Directory.current.path);
}

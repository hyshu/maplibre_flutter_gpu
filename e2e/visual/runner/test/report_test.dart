import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:test/test.dart';
import 'package:visual_e2e_runner/visual_e2e_runner.dart';

void main() {
  test('report contains both screenshots, diff, and similarity', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'visual-e2e-report-test.',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final images = Directory(
      '${temporary.path}${Platform.pathSeparator}images',
    );
    await images.create();
    final png = Uint8List.fromList(
      image.encodePng(image.Image(width: 2, height: 2)),
    );
    await File('${images.path}${Platform.pathSeparator}maplibre_gl.png')
        .writeAsBytes(png);
    await File('${images.path}${Platform.pathSeparator}gpu.png')
        .writeAsBytes(png);
    final comparison = comparePngBytes(referencePng: png, actualPng: png);

    await writeVisualReport(
      outputDirectory: temporary,
      comparison: comparison,
      minimumSimilarity: 0.998,
      sceneId: 'geometry',
      platform: 'Android',
      metadata: const {
        'androidApi': '35',
        'maplibreGlVersion': '0.26.2',
      },
    );

    final html = await File(
      '${temporary.path}${Platform.pathSeparator}index.html',
    ).readAsString();
    expect(html, contains('maplibre_gl.png'));
    expect(html, contains('gpu.png'));
    expect(html, contains('diff.png'));
    expect(html, contains('100.000%'));
    expect(html, contains('Strict similarity · AA counted'));
    expect(html, contains('YIQ threshold 0.0500'));
    expect(html, contains('maplibre_gl 0.26.2 · reference'));
    expect(html, contains('overflow-wrap: anywhere'));
    expect(html, isNot(contains('swatch mask')));
    expect(
      File('${temporary.path}${Platform.pathSeparator}results.json')
          .existsSync(),
      isTrue,
    );
  });

  test('failed report escapes metadata and records the strict score', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'visual-e2e-failed-report-test.',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final reference = image.Image(width: 2, height: 2);
    final actual = image.Image(width: 2, height: 2);
    for (final pixel in reference) {
      pixel.setRgba(0, 0, 0, 255);
    }
    for (final pixel in actual) {
      pixel.setRgba(255, 255, 255, 255);
    }
    final referencePng = Uint8List.fromList(image.encodePng(reference));
    final actualPng = Uint8List.fromList(image.encodePng(actual));
    final images = Directory(
      '${temporary.path}${Platform.pathSeparator}images',
    );
    await images.create();
    await File('${images.path}${Platform.pathSeparator}maplibre_gl.png')
        .writeAsBytes(referencePng);
    await File('${images.path}${Platform.pathSeparator}gpu.png')
        .writeAsBytes(actualPng);
    final comparison = comparePngBytes(
      referencePng: referencePng,
      actualPng: actualPng,
      options: const PixelMatchOptions(includeAntiAlias: true),
    );

    await writeVisualReport(
      outputDirectory: temporary,
      comparison: comparison,
      minimumSimilarity: 0.998,
      sceneId: 'geometry',
      platform: 'iOS',
      metadata: const {
        'maplibreGlVersion': '<unsafe & version>',
      },
      extraResults: const {'contentRetention': 0},
      additionalGatePassed: false,
    );

    final html = await File(
      '${temporary.path}${Platform.pathSeparator}index.html',
    ).readAsString();
    final result = jsonDecode(
      await File('${temporary.path}${Platform.pathSeparator}results.json')
          .readAsString(),
    ) as Map<String, Object?>;
    final comparisonJson = result['comparison'] as Map<String, Object?>;

    expect(html, contains('FAIL'));
    expect(html, contains('iOS MapLibre visual parity'));
    expect(html, contains('&lt;unsafe &amp; version&gt;'));
    expect(html, isNot(contains('<unsafe & version>')));
    expect(html, contains('Strict similarity · AA counted · Required'));
    expect(html, contains('<dt>AA handling</dt><dd>No exclusion</dd>'));
    expect(html, isNot(contains('aria-label="GPU overlay amount"')));
    expect(html, contains('.swatch.antialias { background: #2563eb; }'));
    expect(result['status'], 'failed');
    expect(result['contentRetention'], 0);
    expect(html, contains('contentRetention'));
    expect(comparisonJson['strictSimilarity'], 0);
    expect(comparisonJson['antiAliasAdjustedSimilarity'], 0);
  });

  test('report renders local camera performance comparison', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'visual-e2e-performance-report-test.',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final images = Directory(
      '${temporary.path}${Platform.pathSeparator}images',
    );
    await images.create();
    final png = Uint8List.fromList(
      image.encodePng(image.Image(width: 2, height: 2)),
    );
    await File('${images.path}${Platform.pathSeparator}maplibre_gl.png')
        .writeAsBytes(png);
    await File('${images.path}${Platform.pathSeparator}gpu.png')
        .writeAsBytes(png);

    await writeVisualReport(
      outputDirectory: temporary,
      comparison: comparePngBytes(referencePng: png, actualPng: png),
      minimumSimilarity: 0,
      sceneId: 'flutter-markers',
      platform: 'iOS',
      metadata: const {'maplibreGlVersion': '0.26.2'},
      performanceComparison: const {
        'reference': {
          'environment': 'iOS Simulator',
          'build_mode': 'profile',
          'camera_step_fps': 60,
          'average_camera_apply_time_millis': 1,
          'p90_camera_apply_time_millis': 2,
          'p99_camera_apply_time_millis': 3,
          'p90_camera_step_interval_millis': 17,
          'p99_camera_step_interval_millis': 20,
          'camera_step_interval_over_33_3ms_count': 1,
          'average_animation_elapsed_millis': 1050,
          'flutter_frame_count': 12,
          'average_flutter_build_time_millis': 2,
          'p90_flutter_build_time_millis': 3,
          'average_flutter_raster_time_millis': 4,
          'p90_flutter_raster_time_millis': 5,
          'flutter_janky_frame_percent': 0,
        },
        'actual': {
          'environment': 'iOS Simulator',
          'build_mode': 'profile',
          'camera_step_fps': 54,
          'average_camera_apply_time_millis': 2,
          'p90_camera_apply_time_millis': 3,
          'p99_camera_apply_time_millis': 4,
          'p90_camera_step_interval_millis': 19,
          'p99_camera_step_interval_millis': 24,
          'camera_step_interval_over_33_3ms_count': 2,
          'average_animation_elapsed_millis': 900,
          'flutter_frame_count': 300,
          'average_flutter_build_time_millis': 3,
          'p90_flutter_build_time_millis': 4,
          'average_flutter_raster_time_millis': 5,
          'p90_flutter_raster_time_millis': 6,
          'flutter_janky_frame_percent': 2,
        },
      },
    );

    final html = await File(
      '${temporary.path}${Platform.pathSeparator}index.html',
    ).readAsString();
    final result = jsonDecode(
      await File('${temporary.path}${Platform.pathSeparator}results.json')
          .readAsString(),
    ) as Map<String, Object?>;
    expect(html, contains('Camera animation performance'));
    expect(html, contains('Camera step cadence'));
    expect(html, contains('iOS Simulator · profile mode'));
    expect(html, contains('maplibre_gl renders its map'));
    expect(result['performance'], isA<Map<String, Object?>>());
  });
}

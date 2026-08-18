import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

import 'package:visual_e2e_gpu/main.dart' as app;

import 'command_coverage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final sceneIds = visualE2eSuiteSceneIds;

  for (final sceneId in sceneIds) {
    testWidgets('capture maplibre_flutter_gpu $sceneId scene', (tester) async {
      setVisualE2eRuntimeSceneId(sceneId);
      try {
        await app.main();
        if (Platform.isAndroid) {
          await binding.convertFlutterSurfaceToImage();
        }
        await tester.pump();
        await _waitForMapIdle(tester);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        _verifySymbolPaint(
          sceneId,
          (await app.visualE2eController).getPlacedLabels(),
        );

        if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
          final screenshot = _desktopScreenshot(sceneId);
          final png = await captureVisualE2ePng(
            pixelRatio: 2,
            readbackAttempts: 2,
            beforeReadbackRetry: (failedAttempt, error, stackTrace) async {
              debugPrint(
                'VISUAL_E2E_CAPTURE|$sceneId|png-readback|'
                'attempt=$failedAttempt|retry\n$error\n$stackTrace',
              );
              await Future<void>.delayed(const Duration(milliseconds: 500));
              await tester.pump();
            },
          );
          await screenshot.parent.create(recursive: true);
          await screenshot.writeAsBytes(png, flush: true);
          expect(png, isNotEmpty);
          await writeVisualE2eCommandCoverage(
            controller: await app.visualE2eController,
            path: _desktopCoveragePath(sceneId, screenshot),
            scene: sceneId,
          );

          return;
        }

        final screenshotName = sceneIds.length == 1 ? 'gpu' : 'gpu-$sceneId';
        final png = await binding.takeScreenshot(screenshotName);
        expect(png, isNotEmpty);

        if (visualE2ePerformanceEnabled) {
          expect(
            Platform.isIOS,
            isTrue,
            reason: 'local visual performance comparison is iOS-only',
          );
          final performance = await runVisualE2eCameraBenchmark(
            animateCamera: app.animateVisualE2eCamera,
          );
          binding.reportData ??= <String, dynamic>{};
          binding.reportData!['visual_performance'] = performance;
        }
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 200));
        } finally {
          try {
            await stopVisualE2eAssetServer();
          } finally {
            setVisualE2eRuntimeSceneId(null);
          }
        }
      }
    });
  }
}

void _verifySymbolPaint(String sceneId, List<gpu.LabelData> labels) {
  if (sceneId == 'symbol-data-driven-paint') {
    const expected = <String, _ExpectedPaint>{
      'NAVY': _ExpectedPaint(
        textColor: (0x17, 0x25, 0x54),
        haloColor: (0xfe, 0xf3, 0xc7),
        haloWidth: 3,
        textOpacity: 1,
        iconColor: (0x25, 0x63, 0xeb),
        iconOpacity: 1,
      ),
      'ORANGE': _ExpectedPaint(
        textColor: (0x9a, 0x34, 0x12),
        haloColor: (0xff, 0xed, 0xd5),
        haloWidth: 1,
        textOpacity: 0.72,
        iconColor: (0xf9, 0x73, 0x16),
        iconOpacity: 0.7,
      ),
      'GREEN': _ExpectedPaint(
        textColor: (0x14, 0x53, 0x2d),
        haloColor: (0xdc, 0xfc, 0xe7),
        haloWidth: 4,
        textOpacity: 0.88,
        iconColor: (0x16, 0xa3, 0x4a),
        iconOpacity: 0.85,
      ),
      'PURPLE': _ExpectedPaint(
        textColor: (0x58, 0x1c, 0x87),
        haloColor: (0xf3, 0xe8, 0xff),
        haloWidth: 2,
        textOpacity: 0.58,
        iconColor: (0x93, 0x33, 0xea),
        iconOpacity: 0.55,
      ),
    };
    for (final entry in expected.entries) {
      final matching = labels
          .where((label) => label.text == entry.key)
          .toList(growable: false);
      expect(matching, isNotEmpty, reason: '${entry.key} was not placed');
      for (final label in matching) {
        _expectPaint(label, entry.value, haloBlur: 0.5);
      }
    }

    return;
  }
  if (sceneId == 'symbol-text-shaping') {
    _verifyTextShaping(labels);

    return;
  }
  if (sceneId != 'symbol-paint-update') return;

  final matching = labels
      .where((label) => label.layer == 'paint-update-symbols')
      .toList(growable: false);
  expect(matching, hasLength(2));
  const expected = _ExpectedPaint(
    textColor: (0xc0, 0x26, 0xd3),
    haloColor: (0xfe, 0xf0, 0x8a),
    haloWidth: 4,
    textOpacity: 1,
    iconColor: (0x02, 0x84, 0xc7),
    iconOpacity: 1,
    iconHaloColor: (0xf9, 0x73, 0x16),
    iconHaloWidth: 4,
  );
  for (final label in matching) {
    _expectPaint(label, expected, haloBlur: 1, iconHaloBlur: 1);
  }
  final before = app.visualE2ePaintUpdatePlacementBefore;
  expect(before, isNotNull);
  final beforeByText = {
    for (final label in before!)
      if (label.layer == 'paint-update-symbols') label.text: label,
  };
  for (final label in matching) {
    final original = beforeByText[label.text];
    expect(
      original,
      isNotNull,
      reason: '${label.text} had no pre-update label',
    );
    expect(_placementSignature(label), _placementSignature(original!));
  }
}

void _verifyTextShaping(List<gpu.LabelData> labels) {
  final vertical = labels.where((label) => label.layer == 'vertical-cjk-text');
  expect(
    vertical.any(
      (label) => label.textPlaced && label.text == '東京駅' && label.vertical,
    ),
    isTrue,
    reason: 'vertical CJK text was not exported for its Widget',
  );

  final inlineRaster = labels.where(
    (label) => label.layer == 'formatted-inline-image',
  );
  expect(
    inlineRaster.any(
      (label) =>
          label.textPlaced &&
          label.text.contains('INLINE ') &&
          label.text.contains(' IMAGE') &&
          label.textSections.any((section) => section.imageId == 'cafe_15'),
    ),
    isTrue,
    reason: 'inline raster section was not exported for its Widget',
  );
}

typedef _Rgb = (int, int, int);

final class _ExpectedPaint {
  const _ExpectedPaint({
    required this.textColor,
    required this.haloColor,
    required this.haloWidth,
    required this.textOpacity,
    required this.iconColor,
    required this.iconOpacity,
    this.iconHaloColor = (0, 0, 0),
    this.iconHaloWidth = 0,
  });

  final _Rgb textColor;
  final _Rgb haloColor;
  final double haloWidth;
  final double textOpacity;
  final _Rgb iconColor;
  final double iconOpacity;
  final _Rgb iconHaloColor;
  final double iconHaloWidth;
}

void _expectPaint(
  gpu.LabelData label,
  _ExpectedPaint expected, {
  required double haloBlur,
  double iconHaloBlur = 0,
}) {
  _expectRgb(label.textR, label.textG, label.textB, expected.textColor);
  _expectRgb(label.haloR, label.haloG, label.haloB, expected.haloColor);
  _expectRgb(label.iconR, label.iconG, label.iconB, expected.iconColor);
  _expectRgb(
    label.iconHaloR,
    label.iconHaloG,
    label.iconHaloB,
    expected.iconHaloColor,
  );
  expect(label.textOpacity, closeTo(expected.textOpacity, 0.001));
  expect(label.iconOpacity, closeTo(expected.iconOpacity, 0.001));
  expect(label.haloWidth, closeTo(expected.haloWidth, 0.001));
  expect(label.haloBlur, closeTo(haloBlur, 0.001));
  expect(label.iconHaloWidth, closeTo(expected.iconHaloWidth, 0.001));
  expect(label.iconHaloBlur, closeTo(iconHaloBlur, 0.001));
  expect(label.textA, closeTo(1, 0.001));
  expect(label.haloA, closeTo(1, 0.001));
  expect(label.iconA, closeTo(1, 0.001));
  expect(label.iconHaloA, closeTo(expected.iconHaloWidth > 0 ? 1 : 0, 0.001));
}

void _expectRgb(double red, double green, double blue, _Rgb expected) {
  expect(red, closeTo(expected.$1 / 255, 0.001));
  expect(green, closeTo(expected.$2 / 255, 0.001));
  expect(blue, closeTo(expected.$3 / 255, 0.001));
}

Object _placementSignature(gpu.LabelData label) => (
  label.crossTileId,
  label.lat,
  label.lon,
  label.iconLat,
  label.iconLon,
  label.textW,
  label.textH,
  label.iconW,
  label.iconH,
  label.textOffsetX,
  label.textOffsetY,
  label.iconOffsetX,
  label.iconOffsetY,
  label.textPlaced,
  label.iconPlaced,
);

File _desktopScreenshot(String sceneId) {
  const screenshotDirectory = String.fromEnvironment(
    'VISUAL_E2E_SCREENSHOT_DIR',
  );
  if (screenshotDirectory.isNotEmpty) {
    return File('$screenshotDirectory${Platform.pathSeparator}$sceneId.png');
  }

  const screenshotPath = String.fromEnvironment('VISUAL_E2E_SCREENSHOT_PATH');
  if (screenshotPath.isEmpty) {
    fail(
      'VISUAL_E2E_SCREENSHOT_DIR or VISUAL_E2E_SCREENSHOT_PATH is required '
      'on desktop platforms',
    );
  }

  return File(screenshotPath);
}

String _desktopCoveragePath(String sceneId, File screenshot) {
  const screenshotDirectory = String.fromEnvironment(
    'VISUAL_E2E_SCREENSHOT_DIR',
  );
  if (screenshotDirectory.isNotEmpty) {
    return '$screenshotDirectory${Platform.pathSeparator}$sceneId.coverage.json';
  }

  return '${screenshot.parent.path}/command-coverage.json';
}

Future<void> _waitForMapIdle(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!VisualTestStatus.ready.value) {
    if (DateTime.now().isAfter(deadline)) {
      fail('maplibre_flutter_gpu did not become idle within 60 seconds');
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

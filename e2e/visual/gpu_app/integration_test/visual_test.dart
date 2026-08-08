import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

        if (Platform.isMacOS) {
          final screenshot = _macOsScreenshot(sceneId);
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
            path: _macOsCoveragePath(sceneId, screenshot),
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

File _macOsScreenshot(String sceneId) {
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
      'on macOS',
    );
  }

  return File(screenshotPath);
}

String _macOsCoveragePath(String sceneId, File screenshot) {
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

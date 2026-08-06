import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

import 'package:visual_e2e_gpu/main.dart' as app;

import 'command_coverage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture maplibre_flutter_gpu $visualE2eSceneId scene', (
    tester,
  ) async {
    await app.main();
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
    }
    await tester.pump();
    try {
      await _waitForMapIdle(tester);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();

      if (Platform.isMacOS) {
        const screenshotPath = String.fromEnvironment(
          'VISUAL_E2E_SCREENSHOT_PATH',
        );
        if (screenshotPath.isEmpty) {
          fail('VISUAL_E2E_SCREENSHOT_PATH is required on macOS');
        }
        final png = await captureVisualE2ePng();
        final screenshot = File(screenshotPath);
        await screenshot.parent.create(recursive: true);
        await screenshot.writeAsBytes(png, flush: true);
        expect(png, isNotEmpty);
        // Records the render paths a screenshot cannot show — see
        // command_coverage.dart.
        await writeVisualE2eCommandCoverage(
          controller: await app.visualE2eController,
          path: '${screenshot.parent.path}/command-coverage.json',
          scene: visualE2eSceneId,
        );

        return;
      }

      final png = await binding.takeScreenshot('gpu');
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await stopVisualE2eAssetServer();
    }
  });
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

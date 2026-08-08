import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

import 'package:visual_e2e_maplibre_gl/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final sceneIds = visualE2eSuiteSceneIds;

  for (final sceneId in sceneIds) {
    testWidgets('capture maplibre_gl $sceneId scene', (tester) async {
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

        final screenshotName = sceneIds.length == 1
            ? 'maplibre_gl'
            : 'maplibre_gl-$sceneId';
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

Future<void> _waitForMapIdle(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!VisualTestStatus.ready.value) {
    if (DateTime.now().isAfter(deadline)) {
      fail('maplibre_gl did not become idle within 60 seconds');
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

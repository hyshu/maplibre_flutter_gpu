import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outputPath = Platform.environment['VISUAL_E2E_SCREENSHOT_DIR'];
  if (outputPath == null || outputPath.isEmpty) {
    throw StateError('VISUAL_E2E_SCREENSHOT_DIR is required');
  }
  final output = Directory(outputPath);
  await output.create(recursive: true);

  await integrationDriver(
    responseDataCallback: (Map<String, dynamic>? data) async {
      final performancePath =
          Platform.environment['VISUAL_E2E_PERFORMANCE_OUTPUT'];
      if (performancePath == null || performancePath.isEmpty) {
        await writeResponseData(data);

        return;
      }
      final file = File(performancePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{'visual_performance': data?['visual_performance']})}\n',
        flush: true,
      );
    },
    onScreenshot:
        (
          String screenshotName,
          List<int> screenshotBytes, [
          Map<String, Object?>? args,
        ]) async {
          final safeName = screenshotName.replaceAll(
            RegExp('[^A-Za-z0-9_.-]'),
            '_',
          );
          final file = File(
            '${output.path}${Platform.pathSeparator}$safeName.png',
          );
          await file.writeAsBytes(screenshotBytes, flush: true);

          return screenshotBytes.isNotEmpty;
        },
  );
}

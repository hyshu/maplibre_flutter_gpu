import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:visual_e2e_runner/src/android/runner.dart';

Future<void> main(List<String> arguments) async {
  try {
    final runnerRoot = path.dirname(path.dirname(Platform.script.toFilePath()));
    final repositoryRoot = path.normalize(path.join(runnerRoot, '../../..'));
    exitCode = await runAndroidVisualComparison(
      arguments,
      repositoryRoot: repositoryRoot,
    );
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exitCode = 2;
  } on ProcessException catch (error) {
    stderr.writeln('error: $error');
    exitCode = 2;
  } catch (error, stackTrace) {
    stderr
      ..writeln('error: $error')
      ..writeln(stackTrace);
    exitCode = 2;
  }
}

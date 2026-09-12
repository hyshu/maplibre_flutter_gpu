part of 'runner.dart';

void _printComparisonSummary({
  required Directory outputDirectory,
  required _SceneComparison result,
  required double minimumSimilarity,
  required double minimumContentRetention,
  required double minimumContentRatio,
  required double minimumForegroundSimilarity,
  required Map<String, Object?>? performanceComparison,
}) {
  final comparison = result.pixels;
  final referenceContentRatio = result.referenceContentRatio;
  final actualContentRatio = result.actualContentRatio;
  final contentRetention = result.contentRetention;
  final foregroundSimilarity = result.foregroundSimilarity;
  final focusedForegroundResults = result.focusedForegroundResults;
  final reportPath = path.join(outputDirectory.path, 'index.html');
  final similarity = (comparison.similarity * 100).toStringAsFixed(3);
  final strictSimilarity = (comparison.strictSimilarity * 100).toStringAsFixed(
    3,
  );
  final required = (minimumSimilarity * 100).toStringAsFixed(3);
  final primaryLabel = comparison.options.includeAntiAlias
      ? 'Strict similarity'
      : 'AA-adjusted similarity';
  stdout
    ..writeln('\n$primaryLabel: $similarity% (required $required%)')
    ..writeln('Strict similarity: $strictSimilarity%')
    ..writeln(
      'Content retention: ${(contentRetention * 100).toStringAsFixed(3)}% '
      '(required '
      '${(minimumContentRetention * 100).toStringAsFixed(3)}%)',
    )
    ..writeln(
      'Reference/actual content: '
      '${(referenceContentRatio * 100).toStringAsFixed(3)}% / '
      '${(actualContentRatio * 100).toStringAsFixed(3)}% '
      '(required ${(minimumContentRatio * 100).toStringAsFixed(3)}%)',
    )
    ..writeln(
      'Foreground similarity: '
      '${(foregroundSimilarity * 100).toStringAsFixed(3)}% '
      '(required '
      '${(minimumForegroundSimilarity * 100).toStringAsFixed(3)}%)',
    )
    ..writeln('Report: $reportPath');
  for (final entry in focusedForegroundResults) {
    stdout.writeln(
      'Focused foreground ${entry.gate.region.label}: '
      '${(entry.similarity * 100).toStringAsFixed(3)}% '
      '(required '
      '${(entry.gate.minimumSimilarity * 100).toStringAsFixed(3)}%)',
    );
  }
  if (performanceComparison != null) {
    final reference =
        performanceComparison['reference']! as Map<String, Object?>;
    final actual = performanceComparison['actual']! as Map<String, Object?>;
    stdout.writeln(
      'Camera step FPS: '
      '${_metric(reference, 'camera_step_fps').toStringAsFixed(2)} / '
      '${_metric(actual, 'camera_step_fps').toStringAsFixed(2)} '
      '(maplibre_gl / GPU)',
    );
  }
}

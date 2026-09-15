part of 'runner.dart';

Future<Map<String, Object?>> _readPerformanceResult(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw FormatException('performance result does not exist: $filePath');
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('performance result must be an object: $filePath');
  }
  final metrics = decoded['visual_performance'];
  if (metrics is! Map<String, dynamic>) {
    throw FormatException('visual_performance is missing from: $filePath');
  }
  return metrics.cast<String, Object?>();
}

Future<Map<String, Object?>> _readPerformanceComparison({
  required String referencePath,
  required String actualPath,
}) async => {
  'reference': await _readPerformanceResult(referencePath),
  'actual': await _readPerformanceResult(actualPath),
};

double _metric(Map<String, Object?> metrics, String key) {
  final value = metrics[key];

  return value is num ? value.toDouble() : 0;
}

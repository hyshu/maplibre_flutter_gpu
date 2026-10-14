// Summarizes and compares SYMBOL_PROBE and MAP_PROBE benchmark records.
//
// Usage:
//   dart run bin/compare_symbol_probes.dart baseline.json [candidate.json]
//
// Records of the same case, count, and variant are collapsed to the median of
// their per-repeat medians and the median of their per-repeat p95 values. With
// a candidate file, each row shows the candidate delta against the baseline.
// Native records also print symbol pipeline counters per camera step.
import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run bin/compare_symbol_probes.dart baseline.json '
      '[candidate.json]',
    );
    exit(64);
  }
  final baseline = _load(arguments[0]);
  final candidate = arguments.length == 2 ? _load(arguments[1]) : null;
  final keys = [
    ...baseline.keys,
    if (candidate != null)
      for (final key in candidate.keys)
        if (!baseline.containsKey(key)) key,
  ];
  stdout.writeln(
    candidate == null
        ? 'case                              count  frames  ui med    ui p95  raster med  raster p95  sem  extra'
        : 'case                              count  ui med (base -> cand)      ui p95 (base -> cand)      raster med (base -> cand)   sem',
  );
  for (final key in keys) {
    final base = baseline[key];
    final cand = candidate?[key];
    final buffer = StringBuffer(key.$1.padRight(33))
      ..write((key.$2 ?? '').padRight(7));
    if (candidate == null) {
      final summary = base!;
      buffer
        ..write(summary.frames.toString().padRight(8))
        ..write(_ms(summary.uiMedian).padRight(10))
        ..write(_ms(summary.uiP95).padRight(8))
        ..write(_ms(summary.rasterMedian).padRight(12))
        ..write(_ms(summary.rasterP95).padRight(12))
        ..write(summary.semantics.padRight(5))
        ..write(summary.extra);
    } else {
      buffer
        ..write(_delta(base?.uiMedian, cand?.uiMedian).padRight(27))
        ..write(_delta(base?.uiP95, cand?.uiP95).padRight(27))
        ..write(_delta(base?.rasterMedian, cand?.rasterMedian).padRight(28))
        ..write('${base?.semantics ?? '-'}/${cand?.semantics ?? '-'}');
    }
    stdout.writeln(buffer);
  }
}

String _ms(double? value) => value == null ? '-' : value.toStringAsFixed(2);

String _delta(double? base, double? candidate) {
  if (base == null || candidate == null) {
    return '${_ms(base)} -> ${_ms(candidate)}';
  }
  final percent = base == 0 ? 0 : (candidate - base) / base * 100;
  final sign = percent >= 0 ? '+' : '';

  return '${_ms(base)} -> ${_ms(candidate)} ($sign${percent.toStringAsFixed(0)}%)';
}

class _Summary {
  _Summary({
    required this.frames,
    required this.uiMedian,
    required this.uiP95,
    required this.rasterMedian,
    required this.rasterP95,
    required this.semantics,
    required this.extra,
  });

  final int frames;
  final double uiMedian;
  final double uiP95;
  final double rasterMedian;
  final double rasterP95;
  final String semantics;
  final String extra;
}

Map<(String, String?), _Summary> _load(String path) {
  final records = (jsonDecode(File(path).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final groups = <(String, String?), List<Map<String, dynamic>>>{};
  for (final record in records) {
    final count = record['count'];
    groups
        .putIfAbsent((record['case'] as String, count?.toString()), () => [])
        .add(record);
  }

  return {
    for (final entry in groups.entries) entry.key: _summarize(entry.value),
  };
}

_Summary _summarize(List<Map<String, dynamic>> records) {
  double stat(String metric, String field) => _median([
    for (final record in records)
      ((record[metric] as Map<String, dynamic>)[field] as num).toDouble(),
  ]);
  final first = records.first;
  final extra = StringBuffer();
  if (first.containsKey('cameraSteps')) {
    final steps = _median([
      for (final record in records) (record['cameraSteps'] as num).toDouble(),
    ]);
    extra.write(
      'steps=${steps.round()} labels=${first['labelsBefore']}/${first['labelsAfter']}',
    );
    final counters = first['counters'] as Map<String, dynamic>?;
    if (counters != null && counters.isNotEmpty && steps > 0) {
      extra.write(' per step:');
      for (final key in const [
        'nativeRenderCalls',
        'fullSymbolUpdates',
        'relayoutUpdates',
        'textVisualMisses',
        'transformOnlyMisses',
        'relayoutSetStates',
        'atlasGlyphs',
        'atlasFallbacks',
        'atlasFlushes',
      ]) {
        final value = counters[key];
        if (value is num) {
          extra.write(' $key=${(value / steps).toStringAsFixed(2)}');
        }
      }
      for (final key in const [
        'nativeRenderMicros',
        'labelSyncMicros',
        'labelProjectionMicros',
      ]) {
        final value = counters[key];
        if (value is num) {
          extra.write(' $key=${(value / steps).round()}');
        }
      }
    }
  }
  final tree = first['tree'] as Map<String, dynamic>?;
  if (tree != null) {
    extra.write(
      'elements=${tree['elements']} renderObjects=${tree['renderObjects']} '
      'layers=${tree['wholeAppLayers']}',
    );
  }

  return _Summary(
    frames: _median([
      for (final record in records) (record['frames'] as num).toDouble(),
    ]).round(),
    uiMedian: stat('ui_ms', 'median'),
    uiP95: stat('ui_ms', 'p95'),
    rasterMedian: stat('raster_ms', 'median'),
    rasterP95: stat('raster_ms', 'p95'),
    semantics: records.every((record) => record['semanticsEnabled'] == false)
        ? 'off'
        : records.every((record) => record['semanticsEnabled'] == true)
        ? 'on'
        : 'mixed',
    extra: extra.toString(),
  );
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();

  return sorted[sorted.length ~/ 2];
}

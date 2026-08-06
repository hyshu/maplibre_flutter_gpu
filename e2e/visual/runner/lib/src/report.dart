import 'dart:convert';
import 'dart:io';

import 'pixel_match.dart';

Future<void> writeVisualReport({
  required Directory outputDirectory,
  required PixelMatchResult comparison,
  required double minimumSimilarity,
  required String sceneId,
  required String platform,
  required Map<String, Object?> metadata,
  Map<String, Object> extraResults = const <String, Object>{},
  Map<String, Object?>? performanceComparison,
  bool additionalGatePassed = true,
}) async {
  final images = Directory(
    '${outputDirectory.path}${Platform.pathSeparator}images',
  );
  await images.create(recursive: true);
  await File(
    '${images.path}${Platform.pathSeparator}diff.png',
  ).writeAsBytes(comparison.diffPng, flush: true);

  final passed =
      comparison.similarity >= minimumSimilarity && additionalGatePassed;
  final resultJson = <String, Object?>{
    'status': passed ? 'passed' : 'failed',
    'scene': sceneId,
    'minimumSimilarity': minimumSimilarity,
    'comparison': comparison.toJson(),
    ...extraResults,
    'performance': ?performanceComparison,
    'images': <String, String>{
      'reference': 'images/maplibre_gl.png',
      'actual': 'images/gpu.png',
      'diff': 'images/diff.png',
    },
    'metadata': metadata,
  };
  const encoder = JsonEncoder.withIndent('  ');
  await File(
    '${outputDirectory.path}${Platform.pathSeparator}results.json',
  ).writeAsString('${encoder.convert(resultJson)}\n', flush: true);
  await File(
    '${outputDirectory.path}${Platform.pathSeparator}index.html',
  ).writeAsString(
    _buildHtml(
      comparison: comparison,
      minimumSimilarity: minimumSimilarity,
      sceneId: sceneId,
      platform: platform,
      metadata: metadata,
      extraResults: extraResults,
      performanceComparison: performanceComparison,
      passed: passed,
    ),
    flush: true,
  );
}

String _buildHtml({
  required PixelMatchResult comparison,
  required double minimumSimilarity,
  required String sceneId,
  required String platform,
  required Map<String, Object?> metadata,
  required Map<String, Object> extraResults,
  required Map<String, Object?>? performanceComparison,
  required bool passed,
}) {
  final status = passed ? 'PASS' : 'FAIL';
  final statusClass = passed ? 'pass' : 'fail';
  final similarity = _percentage(comparison.similarity);
  final strictSimilarity = _percentage(comparison.strictSimilarity);
  final minimum = _percentage(minimumSimilarity);
  final exactSimilarity = _percentage(comparison.exactSimilarity);
  final antiAlias = comparison.antiAliasedPixelCount;
  final colorThreshold = comparison.options.colorThreshold.toStringAsFixed(4);
  final maplibreGlVersion = _escape(
    _displayValue(metadata['maplibreGlVersion']),
  );
  final antiAliasPolicy = comparison.options.includeAntiAlias
      ? 'counted as mismatches'
      : 'ignored only where both images contain a local edge';
  final primaryScoreLabel = comparison.options.includeAntiAlias
      ? 'Strict similarity · AA counted'
      : 'AA-adjusted similarity';
  final antiAliasMetric = comparison.options.includeAntiAlias
      ? 'No exclusion'
      : '$antiAlias ignored';
  final maskLegend = comparison.maskedPixelCount == 0
      ? ''
      : '<span><i class="swatch mask"></i>masked</span>';
  final metadataRows = <String, Object?>{...metadata, ...extraResults}.entries
      .map(
        (entry) =>
            '<tr><th>${_escape(entry.key)}</th>'
            '<td>${_escape(_displayValue(entry.value))}</td></tr>',
      )
      .join();
  final performanceSection = _buildPerformanceSection(performanceComparison);

  return '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${_escape(platform)} MapLibre visual parity: $status</title>
  <style>
    :root { color-scheme: light dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
    body { margin: 0; background: #0e1621; color: #e8eef5; }
    main { width: min(1500px, calc(100% - 32px)); margin: 28px auto 56px; }
    h1, h2, p { margin-top: 0; }
    .summary { display: grid; grid-template-columns: auto 1fr; gap: 24px; align-items: center; padding: 24px; border: 1px solid #2a3a4e; border-radius: 16px; background: #152131; }
    .badge { padding: 14px 18px; border-radius: 12px; font-size: 1.35rem; font-weight: 800; letter-spacing: .08em; }
    .badge.pass { background: #164e3a; color: #8df0c4; }
    .badge.fail { background: #642a36; color: #ffb2bf; }
    .score { font-size: clamp(2rem, 6vw, 4rem); font-weight: 800; line-height: 1; }
    .subtle { color: #a9b9cc; }
    .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 12px; margin: 16px 0 28px; }
    .metric { border: 1px solid #2a3a4e; border-radius: 12px; padding: 14px; background: #152131; }
    .metric dt { color: #c1cfde; }
    .metric dd { margin: 5px 0 0; font-size: 1.25rem; font-weight: 800; }
    .method { margin: -10px 0 28px; padding: 14px 16px; border-left: 4px solid #5ea2ef; background: #152131; color: #c1cfde; }
    .images { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; }
    figure { margin: 0; border: 1px solid #2a3a4e; border-radius: 14px; overflow: hidden; background: #152131; }
    figcaption { padding: 12px 14px; font-weight: 700; }
    figure img { display: block; width: 100%; height: auto; background: #fff; }
    .diff { grid-column: 1 / -1; }
    .compare { margin: 28px 0; border: 1px solid #2a3a4e; border-radius: 14px; padding: 16px; background: #152131; }
    .comparison-frame { position: relative; width: min(100%, 720px); margin: 0 auto; overflow: hidden; }
    .comparison-frame img { display: block; width: 100%; height: auto; }
    .comparison-frame .actual { position: absolute; inset: 0; clip-path: inset(0 50% 0 0); }
    input[type=range] { width: min(100%, 720px); display: block; margin: 16px auto 0; }
    .slider-labels { width: min(100%, 720px); display: flex; justify-content: space-between; gap: 12px; margin: 8px auto 0; color: #a9b9cc; }
    .slider-labels label { color: #e8eef5; font-weight: 700; }
    table { border-collapse: collapse; table-layout: fixed; width: 100%; background: #152131; border-radius: 12px; overflow: hidden; }
    th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid #2a3a4e; vertical-align: top; }
    th { width: 240px; color: #a9b9cc; }
    td { overflow-wrap: anywhere; word-break: break-word; }
    .legend { display: flex; flex-wrap: wrap; gap: 18px; margin: 0; padding: 12px 14px 14px; color: #c1cfde; }
    .swatch { display: inline-block; width: 12px; height: 12px; margin-right: 6px; border-radius: 2px; }
    .swatch.mismatch { background: #e62d3e; }
    .swatch.antialias { background: #2563eb; }
    .swatch.mask { background: #4b5b73; }
    .performance { margin: 28px 0; }
    .delta.better { color: #8df0c4; }
    .delta.worse { color: #ffb2bf; }
    @media (max-width: 760px) {
      main { width: min(100% - 20px, 1500px); margin-top: 10px; }
      .summary, .images { grid-template-columns: 1fr; }
      .diff { grid-column: auto; }
      th { width: 34%; }
      th, td { padding: 9px 8px; }
    }
  </style>
</head>
<body>
<main>
  <section class="summary">
    <div class="badge $statusClass">$status</div>
    <div>
      <h1>${_escape(platform)} MapLibre visual parity</h1>
      <div class="score">$similarity</div>
      <p class="subtle">$primaryScoreLabel · Required $minimum · Scene ${_escape(sceneId)}</p>
    </div>
  </section>

  <section aria-labelledby="metrics-heading">
    <h2 id="metrics-heading">Comparison metrics</h2>
    <dl class="metrics">
      <div class="metric"><dt>Strict similarity · AA counted</dt><dd>$strictSimilarity</dd></div>
      <div class="metric"><dt>Exact pixel similarity</dt><dd>$exactSimilarity</dd></div>
      <div class="metric"><dt>Substantial mismatches</dt><dd>${comparison.mismatchPixelCount}</dd></div>
      <div class="metric"><dt>AA handling</dt><dd>$antiAliasMetric</dd></div>
      <div class="metric"><dt>Mean RGB channel delta · 0–255</dt><dd>${comparison.meanAbsoluteChannelDelta.toStringAsFixed(3)}</dd></div>
      <div class="metric"><dt>P95 max RGB delta · 0–255</dt><dd>${comparison.p95MaxChannelDelta}</dd></div>
      <div class="metric"><dt>Compared pixels</dt><dd>${comparison.comparedPixelCount}</dd></div>
    </dl>
  </section>
  <p class="method">
    Gate uses perceptual YIQ threshold $colorThreshold; anti-alias pixels are $antiAliasPolicy.
    Strict similarity applies the same color threshold but counts those pixels.
  </p>

  $performanceSection

  <section aria-labelledby="screenshots-heading">
    <h2 id="screenshots-heading">Screenshots</h2>
    <div class="images">
      <figure>
        <figcaption>maplibre_gl $maplibreGlVersion · reference</figcaption>
        <img src="images/maplibre_gl.png" alt="maplibre_gl reference screenshot">
      </figure>
      <figure>
        <figcaption>maplibre_flutter_gpu · actual</figcaption>
        <img src="images/gpu.png" alt="maplibre_flutter_gpu screenshot">
      </figure>
      <figure class="diff">
        <figcaption>Pixel difference</figcaption>
        <img src="images/diff.png" alt="pixel difference">
        <div class="legend">
          <span><i class="swatch mismatch"></i>substantial mismatch</span>
          <span><i class="swatch antialias"></i>shared-edge anti-alias difference, ignored</span>
          $maskLegend
        </div>
      </figure>
    </div>
  </section>

  <section class="compare" aria-labelledby="overlay-heading">
    <h2 id="overlay-heading">Interactive overlay</h2>
    <div class="comparison-frame">
      <img src="images/maplibre_gl.png" alt="" aria-hidden="true">
      <img class="actual" id="actual-overlay" src="images/gpu.png" alt="" aria-hidden="true">
    </div>
    <input id="comparison-slider" type="range" min="0" max="100" value="50">
    <div class="slider-labels">
      <span>Reference</span>
      <label for="comparison-slider">Overlay split</label>
      <span>GPU</span>
    </div>
  </section>

  <h2 id="metadata-heading">Run metadata</h2>
  <table aria-labelledby="metadata-heading"><tbody>$metadataRows</tbody></table>
</main>
<script>
  const slider = document.getElementById('comparison-slider');
  const overlay = document.getElementById('actual-overlay');
  slider.addEventListener('input', () => {
    overlay.style.clipPath = `inset(0 \${100 - Number(slider.value)}% 0 0)`;
  });
</script>
</body>
</html>
''';
}

String _percentage(double value) => '${(value * 100).toStringAsFixed(3)}%';

String _buildPerformanceSection(Map<String, Object?>? performanceComparison) {
  if (performanceComparison == null) return '';
  final reference = performanceComparison['reference'];
  final actual = performanceComparison['actual'];
  if (reference is! Map || actual is! Map) return '';
  final referenceMetrics = reference.cast<String, Object?>();
  final actualMetrics = actual.cast<String, Object?>();
  final environment = _escape(
    _displayValue(
      actualMetrics['environment'] ?? referenceMetrics['environment'],
    ),
  );
  final buildMode = _escape(
    _displayValue(
      actualMetrics['build_mode'] ?? referenceMetrics['build_mode'],
    ),
  );
  final referenceFrameCount = referenceMetrics['flutter_frame_count'];
  final actualFrameCount = actualMetrics['flutter_frame_count'];
  final flutterTimingsAvailable =
      (referenceFrameCount is num && referenceFrameCount > 0) ||
      (actualFrameCount is num && actualFrameCount > 0);
  final metrics =
      <({String key, String label, String unit, bool? higherIsBetter})>[
        (
          key: 'camera_step_fps',
          label: 'Camera step cadence',
          unit: 'fps',
          higherIsBetter: true,
        ),
        (
          key: 'average_camera_apply_time_millis',
          label: 'Average camera update apply',
          unit: 'ms',
          higherIsBetter: false,
        ),
        (
          key: 'p90_camera_apply_time_millis',
          label: 'P90 camera update apply',
          unit: 'ms',
          higherIsBetter: false,
        ),
        (
          key: 'p99_camera_apply_time_millis',
          label: 'P99 camera update apply',
          unit: 'ms',
          higherIsBetter: false,
        ),
        (
          key: 'p90_camera_step_interval_millis',
          label: 'P90 camera step interval',
          unit: 'ms',
          higherIsBetter: false,
        ),
        (
          key: 'p99_camera_step_interval_millis',
          label: 'P99 camera step interval',
          unit: 'ms',
          higherIsBetter: false,
        ),
        (
          key: 'camera_step_interval_over_33_3ms_count',
          label: 'Camera step intervals over 33.3 ms',
          unit: '',
          higherIsBetter: false,
        ),
        (
          key: 'average_animation_elapsed_millis',
          label: 'Average animation elapsed',
          unit: 'ms',
          higherIsBetter: false,
        ),
        if (flutterTimingsAvailable) ...const [
          (
            key: 'flutter_frame_count',
            label: 'Flutter engine frames observed',
            unit: '',
            higherIsBetter: null,
          ),
          (
            key: 'average_flutter_build_time_millis',
            label: 'Average Flutter build',
            unit: 'ms',
            higherIsBetter: false,
          ),
          (
            key: 'p90_flutter_build_time_millis',
            label: 'P90 Flutter build',
            unit: 'ms',
            higherIsBetter: false,
          ),
          (
            key: 'average_flutter_raster_time_millis',
            label: 'Average Flutter raster',
            unit: 'ms',
            higherIsBetter: false,
          ),
          (
            key: 'p90_flutter_raster_time_millis',
            label: 'P90 Flutter raster',
            unit: 'ms',
            higherIsBetter: false,
          ),
          (
            key: 'flutter_janky_frame_percent',
            label: 'Flutter frames over 16.7 ms',
            unit: '%',
            higherIsBetter: false,
          ),
        ],
      ];
  final rows = metrics.map((metric) {
    final referenceValue = referenceMetrics[metric.key];
    final actualValue = actualMetrics[metric.key];
    final referenceNumber = referenceValue is num
        ? referenceValue.toDouble()
        : null;
    final actualNumber = actualValue is num ? actualValue.toDouble() : null;
    var delta = 'n/a';
    var deltaClass = '';
    if (referenceNumber != null &&
        actualNumber != null &&
        referenceNumber != 0) {
      final ratio = (actualNumber / referenceNumber - 1) * 100;
      delta = '${ratio >= 0 ? '+' : ''}${ratio.toStringAsFixed(1)}%';
      final higherIsBetter = metric.higherIsBetter;
      if (higherIsBetter != null && ratio != 0) {
        final better = higherIsBetter ? ratio > 0 : ratio < 0;
        deltaClass = better ? ' better' : ' worse';
      }
    }
    return '<tr>'
        '<th>${_escape(metric.label)}</th>'
        '<td>${_formatPerformanceValue(referenceNumber, metric.unit)}</td>'
        '<td>${_formatPerformanceValue(actualNumber, metric.unit)}</td>'
        '<td class="delta$deltaClass">$delta</td>'
        '</tr>';
  }).join();
  return '''
  <section class="performance" aria-labelledby="performance-heading">
    <h2 id="performance-heading">Camera animation performance</h2>
    <p class="method">
      Captured after both screenshots using the same three camera round trips.
      $environment · $buildMode mode. Simulator numbers are for relative local
      comparison, not physical-device throughput. maplibre_gl renders its map
      in a native view. Camera step cadence and update-apply latency are the
      cross-implementation motion signals.
      ${flutterTimingsAvailable ? 'Flutter build/raster timings are supplementary.' : 'Flutter FrameTiming was unavailable on this Simulator run and is omitted.'}
    </p>
    <table aria-labelledby="performance-heading">
      <thead><tr><th>Metric</th><th>maplibre_gl</th><th>GPU</th><th>GPU delta</th></tr></thead>
      <tbody>$rows</tbody>
    </table>
  </section>
''';
}

String _formatPerformanceValue(double? value, String unit) {
  if (value == null) return 'n/a';
  final formatted = value.toStringAsFixed(
    value.abs() >= 100 || unit.isEmpty ? 1 : 2,
  );

  return unit.isEmpty ? formatted : '$formatted $unit';
}

String _escape(String value) => const HtmlEscape().convert(value);

String _displayValue(Object? value) {
  if (value is Map || value is Iterable) return jsonEncode(value);

  return value?.toString() ?? 'unknown';
}

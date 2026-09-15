part of 'runner.dart';

_SceneComparison _compareSceneScreenshots({
  required Uint8List referencePng,
  required Uint8List actualPng,
  required String sceneId,
  required double colorThreshold,
  required bool includeAntiAlias,
}) {
  final foregroundRegion = _sceneForegroundRegion[sceneId];
  final comparison = comparePngBytes(
    referencePng: referencePng,
    actualPng: actualPng,
    options: .new(
      colorThreshold: colorThreshold,
      includeAntiAlias: includeAntiAlias,
      foregroundBackground: _visualBackground,
      foregroundRegion: foregroundRegion,
    ),
  );
  final focusedForegroundResults = <_FocusedForegroundResult>[];
  for (final gate
      in _sceneFocusedForegroundGates[sceneId] ??
          const <_FocusedForegroundGate>[]) {
    final targetColor = gate.targetColor;
    if (gate.metric == .colorOrientation) {
      final orientation = compareColorOrientationPngBytes(
        referencePng: referencePng,
        actualPng: actualPng,
        targetColor: targetColor!,
        region: gate.region,
        channelThreshold: gate.channelThreshold,
        minimumPixelCount: gate.minimumPixelCount,
        minimumElongation: gate.minimumElongation,
      );
      focusedForegroundResults.add(
        .new(
          gate: gate,
          similarity: orientation.similarity,
          orientation: orientation,
        ),
      );
      continue;
    }
    if (gate.metric == .actualColorPresence) {
      final presence = analyzeColorPresencePngBytes(
        png: actualPng,
        targetColor: targetColor!,
        region: gate.region,
        channelThreshold: gate.channelThreshold,
      );
      focusedForegroundResults.add(
        .new(
          gate: gate,
          similarity: math.min(1, presence.pixelCount / gate.minimumPixelCount),
          colorPresence: presence,
        ),
      );
      continue;
    }

    final foreground = comparePngBytes(
      referencePng: referencePng,
      actualPng: actualPng,
      options: .new(
        colorThreshold: colorThreshold,
        includeAntiAlias: includeAntiAlias,
        foregroundBackground: _visualBackground,
        foregroundRegion: gate.region,
      ),
    ).foreground!;
    focusedForegroundResults.add(
      .new(gate: gate, similarity: foreground.similarity),
    );
  }
  final referenceContentRatio = pngContentRatio(
    png: referencePng,
    backgroundRed: 0xe7,
    backgroundGreen: 0xed,
    backgroundBlue: 0xf3,
  );
  final actualContentRatio = pngContentRatio(
    png: actualPng,
    backgroundRed: 0xe7,
    backgroundGreen: 0xed,
    backgroundBlue: 0xf3,
  );

  return _SceneComparison(
    pixels: comparison,
    foregroundRegion: foregroundRegion,
    focusedForegroundResults: focusedForegroundResults,
    referenceContentRatio: referenceContentRatio,
    actualContentRatio: actualContentRatio,
  );
}

final class _SceneComparison {
  const new({
    required this.pixels,
    required this.foregroundRegion,
    required this.focusedForegroundResults,
    required this.referenceContentRatio,
    required this.actualContentRatio,
  });

  final PixelMatchResult pixels;
  final NormalizedPixelRegion? foregroundRegion;
  final List<_FocusedForegroundResult> focusedForegroundResults;
  final double referenceContentRatio;
  final double actualContentRatio;

  double get foregroundSimilarity => pixels.foreground!.similarity;

  double get contentRetention => referenceContentRatio == 0
      ? 1.0
      : actualContentRatio / referenceContentRatio;

  bool get focusedForegroundPassed => focusedForegroundResults.every(
    (entry) => entry.similarity >= entry.gate.minimumSimilarity,
  );
}

final class _FocusedForegroundResult {
  const new({
    required this.gate,
    required this.similarity,
    this.orientation,
    this.colorPresence,
  });

  final _FocusedForegroundGate gate;
  final double similarity;
  final ColorOrientationMatchResult? orientation;
  final ColorPresenceResult? colorPresence;
}

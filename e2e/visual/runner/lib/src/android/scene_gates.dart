part of 'runner.dart';

const _visualBackground = PixelColor(0xe7, 0xed, 0xf3);

const _symbolSceneMinimumForegroundSimilarity = <String, double>{
  'text-symbol': 0.45,
  'symbol-data-driven-paint': 0.55,
  'symbol-paint-update': 0.40,
  'symbol-line-pitch': 0.30,
  'symbol-icon-effects': 0.55,
  'symbol-layer-order': 0.70,
  'symbol-z-order': 0.60,
  'symbol-text-shaping': 0.25,
};

const _sceneMinimumSimilarity = <String, double>{
  'text-symbol': 0.970,
  'symbol-data-driven-paint': 0.950,
  'symbol-paint-update': 0.950,
  'symbol-line-pitch': 0.950,
  'symbol-icon-effects': 0.950,
  'symbol-layer-order': 0.950,
  'symbol-z-order': 0.950,
  'symbol-text-shaping': 0.800,
};

const _sceneMinimumContentRatio = <String, double>{
  'symbol-data-driven-paint': 0.0005,
  'symbol-paint-update': 0.001,
  'symbol-line-pitch': 0.0005,
  'symbol-icon-effects': 0.005,
  'symbol-layer-order': 0.003,
  'symbol-z-order': 0.01,
  'symbol-text-shaping': 0.01,
};

const _sceneForegroundRegion = <String, NormalizedPixelRegion>{
  'symbol-z-order': NormalizedPixelRegion(
    left: 0.27,
    top: 0.46,
    right: 0.72,
    bottom: 0.55,
    label: 'overlap centers for both ordering paths',
  ),
  'symbol-text-shaping': NormalizedPixelRegion(
    left: 0.05,
    top: 0.55,
    right: 0.95,
    bottom: 0.69,
    label: 'mixed bidirectional text',
  ),
};

const _sceneFocusedForegroundGates = <String, List<_FocusedForegroundGate>>{
  'symbol-data-driven-paint': <_FocusedForegroundGate>[
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.25,
        top: 0.425,
        right: 0.30,
        bottom: 0.448,
        label: 'NAVY icon color and opacity',
      ),
      targetColor: PixelColor(0x36, 0x62, 0xe3),
      channelThreshold: 12,
      minimumPixelCount: 100,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.697,
        top: 0.425,
        right: 0.747,
        bottom: 0.448,
        label: 'ORANGE icon color and opacity',
      ),
      targetColor: PixelColor(0xe7, 0x9c, 0x64),
      channelThreshold: 12,
      minimumPixelCount: 100,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.25,
        top: 0.552,
        right: 0.30,
        bottom: 0.575,
        label: 'GREEN icon color and opacity',
      ),
      targetColor: PixelColor(0x5b, 0xac, 0x6a),
      channelThreshold: 12,
      minimumPixelCount: 100,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.697,
        top: 0.552,
        right: 0.747,
        bottom: 0.575,
        label: 'PURPLE icon color and opacity',
      ),
      targetColor: PixelColor(0xb2, 0x89, 0xe8),
      channelThreshold: 12,
      minimumPixelCount: 100,
    ),
  ],
  'symbol-paint-update': <_FocusedForegroundGate>[
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.43,
        top: 0.42,
        right: 0.57,
        bottom: 0.49,
        label: 'updated icon fill',
      ),
      targetColor: PixelColor(0x39, 0x82, 0xc2),
      channelThreshold: 12,
      minimumPixelCount: 500,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.43,
        top: 0.42,
        right: 0.57,
        bottom: 0.49,
        label: 'updated icon halo',
      ),
      targetColor: PixelColor(0xe9, 0x7b, 0x35),
      channelThreshold: 12,
      minimumPixelCount: 50,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.615,
        right: 0.88,
        bottom: 0.66,
        label: 'updated text fill',
      ),
      targetColor: PixelColor(0xb1, 0x35, 0xcc),
      channelThreshold: 12,
      minimumPixelCount: 200,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.615,
        right: 0.88,
        bottom: 0.66,
        label: 'updated text halo',
      ),
      targetColor: PixelColor(0xfc, 0xf1, 0x97),
      channelThreshold: 12,
      minimumPixelCount: 500,
    ),
  ],
  'symbol-line-pitch': <_FocusedForegroundGate>[
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.54,
        top: 0.36,
        right: 0.67,
        bottom: 0.45,
        label: 'icon-only line symbol',
      ),
      minimumSimilarity: 0.40,
    ),
    _FocusedForegroundGate.colorOrientation(
      region: NormalizedPixelRegion(
        left: 0.15,
        top: 0.64,
        right: 0.38,
        bottom: 0.78,
        label: 'single-glyph map-aligned line text',
      ),
      minimumSimilarity: 0.85,
      targetColor: PixelColor(0x02, 0x84, 0xc7),
      channelThreshold: 70,
      minimumPixelCount: 20,
      minimumElongation: 1.5,
    ),
  ],
  'symbol-icon-effects': <_FocusedForegroundGate>[
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.43,
        top: 0.35,
        right: 0.92,
        bottom: 0.48,
        label: 'asymmetric nine-patch text fit',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.13,
        top: 0.34,
        right: 0.40,
        bottom: 0.43,
        label: 'small proportional nine-patch fit',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.47,
        top: 0.55,
        right: 0.69,
        bottom: 0.65,
        label: 'natural 64 by 48 nine-patch',
      ),
      minimumSimilarity: 0.50,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.62,
        right: 0.85,
        bottom: 0.88,
        label: 'uniformly scaled nine-patch without text fit',
      ),
      minimumSimilarity: 0.50,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.63,
        top: 0.49,
        right: 0.98,
        bottom: 0.63,
        label: 'map-anchored point translation',
      ),
      minimumSimilarity: 0.40,
    ),
  ],
  'symbol-layer-order': <_FocusedForegroundGate>[
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.40,
        right: 0.35,
        bottom: 0.49,
        label: 'widget stratum slot 1',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.425,
        top: 0.40,
        right: 0.575,
        bottom: 0.49,
        label: 'widget stratum slot 2',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.65,
        top: 0.40,
        right: 0.80,
        bottom: 0.49,
        label: 'widget stratum slot 3',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.20,
        top: 0.51,
        right: 0.35,
        bottom: 0.60,
        label: 'widget stratum slot 4',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.425,
        top: 0.51,
        right: 0.575,
        bottom: 0.60,
        label: 'widget stratum slot 5',
      ),
      minimumSimilarity: 0.45,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.65,
        top: 0.51,
        right: 0.80,
        bottom: 0.60,
        label: 'widget stratum slot 6',
      ),
      minimumSimilarity: 0.45,
    ),
  ],
  'symbol-text-shaping': <_FocusedForegroundGate>[
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.02,
        top: 0.13,
        right: 0.98,
        bottom: 0.33,
        label: 'padded left and right multiline text',
      ),
      minimumSimilarity: 0.25,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.02,
        top: 0.48,
        right: 0.98,
        bottom: 0.58,
        label: 'formatted mixed RTL line sections',
      ),
      minimumSimilarity: 0.20,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.21,
        top: 0.405,
        right: 0.25,
        bottom: 0.435,
        label: 'formatted inline SDF halo',
      ),
      targetColor: PixelColor(0xfa, 0xcc, 0x15),
      channelThreshold: 64,
      minimumPixelCount: 120,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.50,
        top: 0.30,
        right: 0.55,
        bottom: 0.33,
        label: 'formatted inline raster image',
      ),
      targetColor: PixelColor(0xd9, 0x72, 0x00),
      channelThreshold: 64,
      minimumPixelCount: 200,
    ),
    _FocusedForegroundGate.actualColorPresence(
      region: NormalizedPixelRegion(
        left: 0.70,
        top: 0.25,
        right: 0.82,
        bottom: 0.38,
        label: 'vertical CJK widget text',
      ),
      targetColor: PixelColor(0x7c, 0x2d, 0x12),
      channelThreshold: 32,
      minimumPixelCount: 2000,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.35,
        top: 0.39,
        right: 0.68,
        bottom: 0.52,
        label: 'asymmetric variable anchor offset',
      ),
      minimumSimilarity: 0.24,
    ),
    _FocusedForegroundGate(
      region: NormalizedPixelRegion(
        left: 0.08,
        top: 0.68,
        right: 0.92,
        bottom: 0.93,
        label: 'long UTF-8 widget export boundary',
      ),
      minimumSimilarity: 0.30,
    ),
  ],
};

final class _FocusedForegroundGate {
  const new({required this.region, required this.minimumSimilarity})
    : metric = .foregroundSimilarity,
      targetColor = null,
      channelThreshold = 0,
      minimumPixelCount = 0,
      minimumElongation = 0;

  const new colorOrientation({
    required this.region,
    required this.minimumSimilarity,
    required this.targetColor,
    this.channelThreshold = 16,
    required this.minimumPixelCount,
    required this.minimumElongation,
  }) : metric = .colorOrientation;

  const new actualColorPresence({
    required this.region,
    required this.targetColor,
    this.channelThreshold = 16,
    required this.minimumPixelCount,
  }) : metric = .actualColorPresence,
       minimumSimilarity = 1,
       minimumElongation = 0;

  final NormalizedPixelRegion region;
  final double minimumSimilarity;
  final _FocusedGateMetric metric;
  final PixelColor? targetColor;
  final int channelThreshold;
  final int minimumPixelCount;
  final double minimumElongation;
}

enum _FocusedGateMetric {
  foregroundSimilarity,
  colorOrientation,
  actualColorPresence,
}

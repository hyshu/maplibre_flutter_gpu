import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native label snapshots follow MapLibre placementChanged frames', () {
    final source = File('native/src/maplibre_bridge.cpp').readAsStringSync();

    expect(
      source,
      contains(
        'g_framePlacementChanged.store(status.placementChanged, '
        'std::memory_order_relaxed);',
      ),
    );
    expect(
      source,
      contains(
        'g_framePlacementChanged.exchange(false, '
        'std::memory_order_relaxed)',
      ),
    );
    expect(source, contains('bridge_extractLabels(renderedState);'));
    expect(source, isNot(contains('g_lastExtractZoom')));
    expect(source, isNot(contains('g_labelExtractionRequested')));
  });

  test('native symbol export separates map anchors from screen offsets', () {
    final renderer = File(
      'vendor/maplibre-native/include/mbgl/renderer/renderer.hpp',
    ).readAsStringSync();
    final placement = File(
      'vendor/maplibre-native/src/mbgl/text/placement.cpp',
    ).readAsStringSync();
    final labels = File('native/src/bridge_labels.cpp').readAsStringSync();

    expect(renderer, contains('Point<float> anchorPoint;'));
    expect(placement, contains('.anchorPoint = collisionIndex.projectPoint('));
    expect(labels, contains('label.textOffsetX = screenX - anchorX;'));
    expect(labels, contains('label.iconOffsetY = screenY - anchorY;'));
    expect(renderer, contains('std::u16string lineBrokenText;'));
    expect(
      placement,
      contains('.lineBrokenText = symbol.getLineBrokenText(),'),
    );
    expect(labels, contains('sym.lineBrokenText.empty() ? sym.key'));
    final layout = File(
      'vendor/maplibre-native/src/mbgl/layout/symbol_layout.cpp',
    ).readAsStringSync();
    expect(layout, contains('result.lineBrokenText = feature.originalText;'));
    expect(layout, contains("std::erase(result.lineBrokenText, u'\\n');"));
  });
}

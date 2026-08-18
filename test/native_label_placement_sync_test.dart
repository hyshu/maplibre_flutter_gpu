import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native label snapshots refresh after every rendered frame', () {
    final source = File('native/src/maplibre_bridge.cpp').readAsStringSync();
    final orchestrator = File(
      'vendor/maplibre-native/src/mbgl/renderer/render_orchestrator.cpp',
    ).readAsStringSync();

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
    expect(
      source.indexOf('bridge_extractLabels(renderedState);'),
      greaterThan(
        source.indexOf(
          'g_framePlacementChanged.exchange(false, '
          'std::memory_order_relaxed)',
        ),
      ),
    );
    expect(source, isNot(contains('g_lastExtractZoom')));
    expect(source, isNot(contains('g_labelExtractionRequested')));
    expect(
      orchestrator,
      isNot(contains('placementChanged = placedSymbolDataCollected ||')),
    );
    expect(
      orchestrator,
      contains('placementChanged = placedSymbolDataCollectionChanged ||'),
    );
    expect(orchestrator, contains('!placementController.placementIsRecent('));
    expect(orchestrator, contains('refreshPlacedSymbolData('));
  });

  test('camera-only symbol refresh skips collision placement', () {
    final renderer = File(
      'vendor/maplibre-native/include/mbgl/renderer/renderer.hpp',
    ).readAsStringSync();
    final placement = File('vendor/maplibre-native/src/mbgl/text/placement.cpp')
        .readAsStringSync();
    final collision = File(
      'vendor/maplibre-native/src/mbgl/text/collision_index.cpp',
    ).readAsStringSync();

    expect(placement, contains('void Placement::refreshPlacedSymbolData('));
    expect(placement, contains('projection.projectFeature('));
    expect(
      placement,
      contains('evaluateSizeForFeature(ctx.partiallyEvaluatedTextSize'),
    );
    expect(placement, contains('calculateVariableRenderShift('));
    expect(placement, contains('ctx.hasIconTextFit'));
    expect(collision, contains('void CollisionIndex::projectFeature('));
    final refreshStart = collision.indexOf(
      'void CollisionIndex::projectFeature(',
    );
    final refreshEnd = collision.indexOf(
      'std::pair<bool, bool> CollisionIndex::placeLineFeature(',
      refreshStart,
    );
    final refreshBody = collision.substring(refreshStart, refreshEnd);
    expect(refreshBody, contains('placeLineFeature(feature,'));
    expect(refreshBody, isNot(contains('collisionGrid.hitTest')));
    expect(refreshBody, isNot(contains('insertFeature(')));
    expect(renderer, contains('uint32_t bucketInstanceID = 0;'));
    expect(renderer, contains('uint32_t symbolInstanceIndex = 0;'));
    expect(
      placement,
      contains('symbolsByBucket[data.bucketInstanceID].push_back(&data);'),
    );
    expect(
      placement,
      contains('bucket.symbolInstances[data->symbolInstanceIndex]'),
    );
    expect(placement, contains('symbol.getCrossTileID() != data->crossTileID'));
    final placementRefreshStart = placement.indexOf(
      'void Placement::refreshPlacedSymbolData(',
    );
    final placementRefreshEnd = placement.indexOf(
      'const CollisionIndex& Placement::getCollisionIndex()',
      placementRefreshStart,
    );
    final placementRefreshBody = placement.substring(
      placementRefreshStart,
      placementRefreshEnd,
    );
    expect(
      placementRefreshBody,
      isNot(contains('bucket.getSymbols(item.sortKeyRange)')),
    );
  });

  test('native symbol export separates map anchors from screen offsets', () {
    final renderer = File(
      'vendor/maplibre-native/include/mbgl/renderer/renderer.hpp',
    ).readAsStringSync();
    final placement = File('vendor/maplibre-native/src/mbgl/text/placement.cpp')
        .readAsStringSync();
    final labels = File('native/src/bridge_labels.cpp').readAsStringSync();

    expect(renderer, contains('Point<float> anchorPoint;'));
    expect(
      placement,
      contains('const auto anchorPoint = collisionIndex.projectPoint('),
    );
    expect(placement, contains('.anchorLatLng = anchorLatLng,'));
    expect(labels, contains('label.textOffsetX = textCenterX;'));
    expect(labels, contains('label.iconOffsetY = iconCenterY;'));
    expect(
      labels,
      allOf(
        contains('item.symbol->textPath,'),
        contains('item.label.textOffsetX,'),
        contains('item.label.textOffsetY)'),
      ),
    );
    expect(renderer, contains('std::u16string lineBrokenText;'));
    expect(renderer, contains('std::u16string logicalLineBrokenText;'));
    expect(
      placement,
      contains('.lineBrokenText = symbol.getLineBrokenText(),'),
    );
    expect(
      placement,
      contains('.logicalLineBrokenText = exportData.logicalLineBrokenText,'),
    );
    expect(labels, contains('symbol.lineBrokenText.empty() ? symbol.key'));
    final layout = File(
      'vendor/maplibre-native/src/mbgl/layout/symbol_layout.cpp',
    ).readAsStringSync();
    expect(layout, contains('result.lineBrokenText = feature.originalText;'));
    expect(
      layout,
      contains('result.logicalLineBrokenText = result.lineBrokenText;'),
    );
    expect(layout, contains("std::erase(result.lineBrokenText, u'\\n');"));
  });

  test(
    'native Widget text keeps logical BiDi order and resolved direction',
    () {
      final shaping = File('vendor/maplibre-native/src/mbgl/text/shaping.cpp')
          .readAsStringSync();
      final bidi = File(
        'vendor/maplibre-native/platform/default/src/mbgl/text/bidi.cpp',
      ).readAsStringSync();
      final labels = File('native/src/bridge_labels.cpp').readAsStringSync();

      expect(shaping, contains('shaping.logicalLineBrokenText'));
      expect(shaping, contains('shaping.visualTextSections'));
      expect(shaping, contains('shaping.textRTL = bidi.isRTL'));
      expect(bidi, contains('UBIDI_DEFAULT_LTR'));
      expect(bidi, contains('ubidi_getBaseDirection'));
      expect(
        labels,
        contains('record.logicalTextOffset = refs.logicalText.offset;'),
      );
      expect(labels, contains('(symbol.textRTL ? kTextRTL : 0u)'));
    },
  );

  test('map paint translation uses tile projection at the symbol anchor', () {
    final labels = File('native/src/bridge_labels.cpp').readAsStringSync();

    expect(labels, contains('resolvePaintTranslation'));
    expect(labels, contains('renderedState ? *renderedState : currentState'));
    expect(labels, contains('RenderTile::translateVtxMatrix'));
    expect(labels, contains('projectToScreen(*state, tileMatrix'));
    expect(labels, contains('projectToScreen(*state, translated'));
    expect(
      labels,
      contains('anchor == mbgl::style::TranslateAnchorType::Viewport'),
    );
    expect(labels, isNot(contains('util::rotate(screenTextTranslate')));
  });

  test('line icons and unpadded visual centers are exported independently', () {
    final renderer = File(
      'vendor/maplibre-native/include/mbgl/renderer/renderer.hpp',
    ).readAsStringSync();
    final placement = File('vendor/maplibre-native/src/mbgl/text/placement.cpp')
        .readAsStringSync();
    final labels = File('native/src/bridge_labels.cpp').readAsStringSync();
    final layout = File(
      'vendor/maplibre-native/src/mbgl/layout/symbol_layout.cpp',
    ).readAsStringSync();
    final instance = File(
      'vendor/maplibre-native/src/mbgl/layout/symbol_instance.hpp',
    ).readAsStringSync();

    expect(
      instance,
      contains('std::optional<std::array<Point<float>, 2>> sourceLineSegment;'),
    );
    expect(layout, contains('auto instanceExportData = exportData;'));
    expect(layout, contains('const auto& sourceLine = sharedData->line;'));
    expect(layout, contains('instanceExportData.sourceLineSegment ='));
    expect(placement, contains('if (exportData.sourceLineSegment)'));
    expect(placement, contains('const auto& lineSegment ='));
    expect(placement, isNot(contains('const auto& line = symbol.line();')));
    expect(placement, contains('std::vector<Point<float>> projectedPath;'));
    expect(
      placement,
      contains('textAlongLine && textGeometry.path.size() < 2'),
    );
    expect(
      placement,
      contains('exportSourceLineGeometry(textGeometry, false);'),
    );
    expect(
      placement,
      contains('exportSourceLineGeometry(iconGeometry, true);'),
    );
    expect(
      placement,
      contains('ctx.getLayout().get<style::IconRotationAlignment>()'),
    );
    expect(placement, contains('const bool textAlongLine ='));
    expect(placement, contains('const bool iconAlongLine ='));
    expect(placement, contains('.alongLine = textAlongLine,'));
    expect(placement, contains('.iconAlongLine = iconAlongLine,'));
    expect(placement, contains('const Point<float> variableAnchorScreenShift'));
    expect(
      placement,
      contains('textVisual.offset += variableAnchorScreenShift;'),
    );
    expect(placement, contains('if (ctx.hasIconTextFit) iconVisual.offset +='));
    expect(renderer, contains('Point<float> textVisualOffset;'));
    expect(renderer, contains('Point<float> iconVisualOffset;'));
    expect(labels, contains('symbol.textVisualOffset.x'));
    expect(labels, contains('symbol.iconVisualOffset.y'));
    expect(
      layout,
      contains('hasIconTextFit && shapedIcon ? shapedIcon->right()'),
    );
    expect(layout, contains('icon = icon.applyTextFit();'));
    expect(instance, contains('float iconStretchFractionX = 1;'));
    expect(
      layout,
      contains('stretchExtent += stretch.second - stretch.first;'),
    );
    expect(
      placement,
      contains('const float fixedFraction = 1.0f - stretchFraction;'),
    );
    expect(
      placement,
      contains('const float shaderScale = std::max(fixedFraction, fontScale);'),
    );
    expect(
      placement,
      contains('iconVisual.width = width * scaleX.extentScale;'),
    );
    expect(
      placement,
      contains('iconVisual.height = height * scaleY.extentScale;'),
    );
  });

  test('native symbol paint uses current frame evaluated properties', () {
    final renderer = File(
      'vendor/maplibre-native/include/mbgl/renderer/renderer.hpp',
    ).readAsStringSync();
    final renderLayer = File(
      'vendor/maplibre-native/src/mbgl/renderer/layers/render_symbol_layer.cpp',
    ).readAsStringSync();
    final labels = File('native/src/bridge_labels.cpp').readAsStringSync();

    expect(renderer, contains('getEvaluatedLayerProperties'));
    expect(renderLayer, contains('unevaluated.evaluate(parameters'));
    expect(labels, contains('evaluated.get<mbgl::style::TextColor>()'));
    expect(labels, contains('evaluated.get<mbgl::style::IconTranslate>()'));
    expect(labels, isNot(contains('layer->getTextColor()')));
    expect(labels, isNot(contains('layer->getIconOpacity()')));
  });

  test(
    'native point transforms include shader perspective and map rotation',
    () {
      final layout = File(
        'vendor/maplibre-native/src/mbgl/layout/symbol_layout.cpp',
      ).readAsStringSync();
      final instance = File(
        'vendor/maplibre-native/src/mbgl/layout/symbol_instance.hpp',
      ).readAsStringSync();
      final placement = File(
        'vendor/maplibre-native/src/mbgl/text/placement.cpp',
      ).readAsStringSync();

      expect(instance, contains('bool iconOffsetDefined = false;'));
      expect(
        layout,
        contains(
          'iconOffsetDefined = !leader.layout.get<IconOffset>().isUndefined();',
        ),
      );
      expect(layout, contains('.iconOffsetDefined = iconOffsetDefined,'));
      expect(placement, contains('const float cameraToAnchorDistance ='));
      expect(placement, contains('const float perspectiveRatio ='));
      expect(placement, contains('exportData.iconOffsetDefined'));
      expect(placement, contains('0.5f + 0.5f * distanceRatio'));
      expect(
        placement,
        contains(
          'const bool rotateInShader = rotateWithMap && !pitchWithMap &&',
        ),
      );
      expect(
        placement,
        matches(
          RegExp(
            r'ctx\.getLayout\(\)\.get<style::SymbolPlacement>\(\)\s*=='
            r'\s*style::SymbolPlacementType::Point',
          ),
        ),
      );
      expect(
        placement,
        contains('project(tileAnchor + Point<float>{1, 0}, tileMatrix).first'),
      );
      expect(
        placement,
        contains('widgetRotation += std::atan2(mapEastAxis.y, mapEastAxis.x);'),
      );
    },
  );

  test(
    'native export ranks allow-overlap, viewport-y, and sort-key paint order',
    () {
      final layout = File(
        'vendor/maplibre-native/src/mbgl/layout/symbol_layout.cpp',
      ).readAsStringSync();
      final renderer = File(
        'vendor/maplibre-native/include/mbgl/renderer/renderer.hpp',
      ).readAsStringSync();
      final placement = File(
        'vendor/maplibre-native/src/mbgl/text/placement.cpp',
      ).readAsStringSync();
      final labels = File('native/src/bridge_labels.cpp').readAsStringSync();

      expect(layout, contains('symbolZOrder == SymbolZOrderType::Auto'));
      expect(layout, contains('layout->get<TextAllowOverlap>()'));
      expect(layout, contains('layout->get<TextIgnorePlacement>()'));
      expect(renderer, contains('uint32_t renderGroup = 0;'));
      expect(renderer, contains('uint32_t renderOrder = 0;'));
      expect(placement, contains('getPaintOrderedSymbols'));
      expect(placement, contains('bucket.sortFeaturesByY'));
      expect(placement, contains('bucket.text.segments.size() <= 1'));
      expect(
        placement,
        contains('bucket.getSortedSymbols(static_cast<float>(bearing))'),
      );
      expect(placement, contains('bucket.getSymbols(params.sortKeyRange)'));
      expect(placement, contains('data.sortKeyRange->sortKey'));
      expect(placement, contains('symbolRenderOrders.find(&symbolInstance)'));
      expect(labels, contains('label.renderGroup = symbol.renderGroup;'));
      expect(labels, contains('label.renderOrder = symbol.renderOrder;'));
    },
  );
}

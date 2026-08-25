import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native separates content, scalar, and geometry generations', () {
    final source = File('native/src/bridge_labels.cpp').readAsStringSync();
    final publishStart = source.indexOf('void publishPendingLabels(');
    final publishEnd = source.indexOf('\n}\n\n} // namespace', publishStart);
    final publish = source.substring(publishStart, publishEnd);

    expect(publish, contains('const bool contentChanged = contentHashes != '));
    expect(publish, contains('if (contentChanged) {'));
    expect(publish, contains('appendStaticContent('));
    expect(publish, contains('copyContentRefs('));
    expect(publish, contains('++session.staticContentVersion;'));
    expect(publish, contains('++session.staticVersion;'));
    expect(publish, contains('++session.dynamicVersion;'));
    expect(publish, contains('left.renderOrder < right.renderOrder'));
    expect(publish, contains('session.frameSymbols[item.frameSymbolIndex]'));
    expect(publish, contains('if (!frameSymbol.pathsAppended)'));
    expect(source, contains('result.renderOrder = label.renderOrder;'));
    expect(source, contains('result.staticIndex = staticIndex;'));
    expect(
      source,
      contains('COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, tileWrap, 148)'),
    );
  });

  test('native reuses exporter scratch and caches stable symbol content', () {
    final source = File('native/src/bridge_labels.cpp').readAsStringSync();
    final sessionStart = source.indexOf('struct LabelSessionState {');
    final sessionEnd = source.indexOf(
      '\n};\n\nLayerPaintPlan makeLayerPaintPlan',
      sessionStart,
    );
    final session = source.substring(sessionStart, sessionEnd);
    final cacheStart = session.indexOf('cachedSharedContentHash(');
    final cacheEnd = session.indexOf(
      '\n    void pruneContentHashCache',
      cacheStart,
    );
    final cache = session.substring(cacheStart, cacheEnd);
    final missStart = cache.indexOf('if (found == contentHashCache.end())');
    final hitStart = cache.indexOf('} else {', missStart);
    final fullHash = cache.indexOf(
      'sharedContentHash(*frameSymbol.symbol)',
      missStart,
    );

    expect(source, contains('struct SymbolContentKey {'));
    expect(source, contains('uint32_t bucketInstanceID = 0;'));
    expect(source, contains('uint32_t symbolInstanceIndex = 0;'));
    expect(source, contains('uint32_t crossTileID = 0;'));
    expect(missStart, greaterThanOrEqualTo(0));
    expect(fullHash, greaterThan(missStart));
    expect(fullHash, lessThan(hitStart));
    expect(cache.substring(hitStart), isNot(contains('sharedContentHash(')));
    expect(cache, contains('frameSymbol.key.bucketInstanceID == 0'));
    expect(session, contains('std::vector<PendingLabel> pending;'));
    expect(session, contains('scratchStaticLabels'));
    expect(session, contains('scratchStaticBlob'));
    expect(session, contains('scratchDynamicLabels'));
    expect(session, contains('scratchDynamicBlob'));
    expect(session, contains('std::vector<std::size_t> order;'));
    expect(session, contains('contentCacheGeneration - retainedGenerations'));
    expect(session, contains('contentHashCache.size() > maxRetained'));
    expect(session, contains('contentCacheGeneration % 64 != 0'));
    expect(source, contains('session.staticLabels.swap(staticLabels);'));
    expect(source, contains('session.staticBlob.swap(staticBlob);'));
    expect(source, contains('session.dynamicLabels.swap(dynamicLabels);'));
    expect(source, contains('session.dynamicBlob.swap(dynamicBlob);'));
    expect(source, contains('releaseStorage(session.contentHashCache);'));
    expect(source, contains('releaseStorage(session.layerMetadata);'));
    expect(source, isNot(contains('std::stable_sort(order.begin()')));
    expect(source, contains('sameLayerOrder = session.layerOrder[i] =='));
  });

  test('native plans paint and caches per-symbol dependencies', () {
    final source = File('native/src/bridge_labels.cpp').readAsStringSync();
    final dependencyStart = source.indexOf('bool expressionUsesFeatureState(');
    final dependencyEnd = source.indexOf(
      '\n}\n\ntemplate <typename T>\nstruct PaintPropertyPlan',
      dependencyStart,
    );
    final dependency = source.substring(dependencyStart, dependencyEnd);
    final extractStart = source.indexOf('void bridge_extractLabels(');
    final extract = source.substring(extractStart);
    final symbolLoopStart = extract.indexOf(
      'for (const auto& symbol : placedSymbols)',
    );
    final framePlan = extract.substring(0, symbolLoopStart);
    final symbolLoop = extract.substring(symbolLoopStart);

    expect(source, contains('struct LayerPaintPlan {'));
    expect(source, contains('struct PaintPropertyPlan {'));
    expect(source, contains('uint16_t dynamicMask = 0;'));
    expect(source, contains('uint16_t featureStateMask = 0;'));
    expect(source, contains('property.match('));
    expect(dependency, contains('expression.getOperator() == "feature-state"'));
    expect(dependency, contains('expression.eachChild('));
    expect(dependency, contains('expressionUsesFeatureState(child)'));
    expect(framePlan, contains('makeLayerPaintPlan('));
    expect(framePlan, contains('getEvaluatedLayerProperties(layerID)'));
    expect(symbolLoop, contains('layerPlansForSymbol(session, symbol)'));
    expect(symbolLoop, contains('featureStateMask == 0'));
    expect(symbolLoop, contains('featureStateForSymbol(session, symbol'));
    expect(symbolLoop, isNot(contains('getEvaluatedLayerProperties(')));
    expect(symbolLoop, isNot(contains('getStyle().getLayer(')));
    expect(source, contains('if (symbol.bucketInstanceID == 0)'));
    expect(source, contains('session.bucketLayerPlans.try_emplace('));
    expect(source, contains('pruneBucketLayerPlans()'));
    expect(source, contains('item->second.plans.clear();'));
    expect(source, contains('item->second.lastSeenGeneration'));
    expect(source, contains('renderer.getFeatureState('));
    expect(source, contains('session.featureStates.try_emplace('));
    expect(source, contains('session.paintTranslationMatrices.try_emplace('));
    expect(source, contains('layerPaintPlans.clear();'));
    expect(source, contains('featureStates.clear();'));
    expect(source, contains('paintTranslationMatrices.clear();'));
  });

  test('Dart skips content decoding while content version is stable', () {
    final bindings = File('lib/src/native/bindings/label_bindings.dart')
        .readAsStringSync();
    final splitStart = bindings.indexOf(
      'List<LabelData>? _tryGetSplitPlacedLabels',
    );
    final split = bindings.substring(splitStart);
    final scalarBranch = split.indexOf(
      '_cachedLabelStaticContentVersion == contentVersion',
    );
    final scalarDecode = split.indexOf(
      'decodeLabelStaticScalarExports(',
      scalarBranch,
    );
    final blobRead = split.indexOf(
      '_getLabelStaticBlobSize!.call()',
      scalarDecode,
    );

    expect(scalarBranch, greaterThanOrEqualTo(0));
    expect(scalarDecode, greaterThan(scalarBranch));
    expect(blobRead, greaterThan(scalarDecode));
    expect(
      split.substring(scalarDecode, blobRead),
      isNot(contains('decodeLabelStaticExports(')),
    );
    expect(split, contains('if (nextStatics.length != count) return null;'));
    expect(bindings, contains('if (labels != null) return labels;'));
    expect(bindings, contains('return _getLegacyPlacedLabels();'));
  });
}

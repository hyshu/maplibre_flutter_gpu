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
    expect(publish, contains('refsBySymbol.find(item.symbol)'));
    expect(publish, contains('pathsBySymbol.find(item.symbol)'));
    expect(source, contains('result.renderOrder = label.renderOrder;'));
    expect(source, contains('result.staticIndex = staticIndex;'));
    expect(
      source,
      contains('COMMAND_EXPORT_ABI_OFFSET(LabelDynamicExport, reserved, 148)'),
    );
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

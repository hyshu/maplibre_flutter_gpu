import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/state/map_viewport.dart';

import 'support/source_files.dart';

void main() {
  test('map initialization has no fixed startup delay', () {
    expect(
      SourceFiles.mapWidgetOnly,
      isNot(contains('Duration(milliseconds: 500)')),
    );
  });

  group('MapLibreMap viewport sizing', () {
    test('uses finite LayoutBuilder constraints as logical map size', () {
      const constraints = BoxConstraints.tightFor(width: 200, height: 100);

      expect(mapLayoutSize(constraints), const Size(200, 100));
    });

    test('rejects unbounded and empty layouts', () {
      expect(mapLayoutSize(const BoxConstraints()), isNull);
      expect(
        mapLayoutSize(const BoxConstraints.tightFor(width: 0, height: 0)),
        isNull,
      );
    });

    test('matches native logical and physical viewport dimensions', () {
      final dimensions = viewportDimensions(const Size(200.75, 100.25), 1.5);

      expect(dimensions.logicalWidth, 200);
      expect(dimensions.logicalHeight, 100);
      expect(dimensions.physicalWidth, 300);
      expect(dimensions.physicalHeight, 150);
    });

    test('uses a safe DPR fallback', () {
      final dimensions = viewportDimensions(const Size(200, 100), 0);

      expect(dimensions.physicalWidth, 200);
      expect(dimensions.physicalHeight, 100);
    });
  });
}

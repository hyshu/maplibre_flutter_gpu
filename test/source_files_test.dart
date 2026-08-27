import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('every declared source path still exists', () {
    // Contract tests read these files by path. When one moves, this test is
    // the single place that fails, instead of a dozen tests whose subject has
    // nothing to do with the move.
    for (final paths in <List<String>>[
      SourceFiles.rendererPaths,
      SourceFiles.mapWidgetPaths,
      SourceFiles.ffiPaths,
    ]) {
      for (final path in paths) {
        expect(
          () => SourceFiles.readForTest(path),
          returnsNormally,
          reason: 'declared source path is unreadable: $path',
        );
      }
    }
    expect(SourceFiles.mapWidgetOnly, isNotEmpty);
    expect(SourceFiles.gpuPainterOnly, isNotEmpty);
    expect(SourceFiles.ffi, isNotEmpty);
  });

  test('renderer set spans every file the renderer is split across', () {
    final renderer = SourceFiles.renderer;
    // One marker per file in the set, so dropping a path from the list fails
    // here rather than silently weakening the tests that consume it.
    expect(renderer, contains('class GpuFrameRenderer'));
    expect(renderer, contains('class MapPipelineRegistry'));
  });

  test('map widget set spans the widget, painter, and extracted state', () {
    final mapWidget = SourceFiles.mapWidget;
    expect(mapWidget, contains('class MapLibreMap extends StatefulWidget'));
    expect(mapWidget, contains('class MapGpuPainter('));
    for (final marker in <String>[
      'class MapLabelSource',
      'class MapRenderScheduler',
      'class MapStyleSession',
      'class MultiPointerTracker',
      'class PanFlingTracker',
      'class MapViewportCoalescer',
    ]) {
      expect(mapWidget, contains(marker));
    }
  });

  test('a missing path reports where to fix it', () {
    expect(
      () => SourceFiles.readForTest('lib/src/definitely_not_here.dart'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('test/support/source_files.dart'),
        ),
      ),
    );
  });
}

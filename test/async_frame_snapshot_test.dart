import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final ffi = File('lib/src/native/maplibre_ffi.dart').readAsStringSync();
  final signatures = File('lib/src/native/signatures.dart').readAsStringSync();
  final painter = File('lib/src/widgets/map_gpu_painter.dart')
      .readAsStringSync();
  final map = File('lib/src/widgets/maplibre_map.dart').readAsStringSync();
  final controller = File('lib/src/controller/maplibre_map_controller.dart')
      .readAsStringSync();

  test('async snapshot ABI is optional and generation-aware', () {
    for (final symbol in [
      'maplibre_async_render_supported',
      'maplibre_render_frame_async',
      'maplibre_frame_acquire',
      'maplibre_frame_release',
    ]) {
      expect(ffi, contains("'$symbol'"));
    }
    expect(ffi, contains("lookUpGroup('asynchronous frame snapshots'"));
    expect(ffi, contains("'MAPLIBRE_ENABLE_ASYNC_RENDERING'"));
    expect(ffi, contains('_enableAsyncRendering &&'));
    expect(signatures, contains('typedef Uint64VoidN = Uint64 Function();'));
    expect(
      signatures,
      contains('typedef VoidUint64N = Void Function(Uint64 value);'),
    );
  });

  test('widget transfers one generation lease through the painter', () {
    final provider = painter.indexOf('frameSnapshotProvider()');
    final metadata = painter.indexOf('bridge.frameGetMetadata()', provider);
    final release = painter.indexOf('activeSnapshot.release()', metadata);

    expect(provider, greaterThanOrEqualTo(0));
    expect(painter, isNot(contains('bridge.frameAcquire()')));
    expect(metadata, greaterThan(provider));
    expect(release, greaterThan(metadata));
    expect(painter.substring(metadata, release), contains('} finally {'));
    expect(painter, contains('lastPaintedGeneration'));
    expect(map, contains('bridge.acquireFrameSnapshot()'));
    expect(map, contains('_pendingFrameSnapshot?.release();'));
  });

  test('state advances only after acquiring a new snapshot', () {
    final renderStart = map.indexOf('void renderGesture()');
    final renderEnd = map.indexOf('\n  @override', renderStart + 1);
    final body = map.substring(renderStart, renderEnd);
    final acquire = body.indexOf('bridge.acquireFrameSnapshot()');
    final stateRead = body.indexOf('controller?.notifyCameraChanged(');

    expect(body, contains('if (usesAsyncRendering)'));
    expect(body, contains('bridge.frameBegin();'));
    expect(body, contains('bridge.frameEnd();'));
    expect(acquire, greaterThanOrEqualTo(0));
    expect(stateRead, greaterThan(acquire));
    expect(
      body.substring(acquire, stateRead),
      allOf(
        contains('if (acquiredSnapshot == null)'),
        contains(
          'acquiredSnapshot.generation == _lastProcessedFrameGeneration',
        ),
        contains('return;'),
      ),
    );
    expect(
      body.lastIndexOf('bridge.renderFrameAsync();'),
      greaterThan(body.indexOf('_gpuFrame.value++')),
    );
  });

  test('snapshot releases before native bridge destruction', () {
    final dispose = map.substring(
      map.indexOf('void dispose() {'),
      map.indexOf('\n  }', map.indexOf('void dispose() {')),
    );
    expect(
      dispose.indexOf('_pendingFrameSnapshot?.release();'),
      lessThan(dispose.indexOf('_bridge.destroy();')),
    );
  });

  test('lease becomes inactive before native release can fail', () {
    final leaseStart = ffi.indexOf('final class NativeFrameSnapshotLease');
    final leaseEnd = ffi.indexOf('\nclass MaplibreBridge', leaseStart);
    final lease = ffi.substring(leaseStart, leaseEnd);

    expect(
      lease.indexOf('_bridge = null;'),
      lessThan(lease.indexOf('bridge.frameRelease(generation);')),
    );
  });

  test('lease release bypasses the owner-thread support probe', () {
    final releaseStart = ffi.indexOf('void frameRelease(int generation)');
    final releaseEnd = ffi.indexOf('\n  }', releaseStart);
    final release = ffi.substring(releaseStart, releaseEnd);

    expect(
      release,
      contains("_symbols.provides('asynchronous frame snapshots')"),
    );
    expect(release, isNot(contains('supportsAsyncRendering')));
    expect(release, contains('_frameRelease!.call(generation);'));
  });

  test('native wake registration follows the synchronous startup pump', () {
    final initialize = map.substring(
      map.indexOf('Future<void> _initMap()'),
      map.indexOf('bool _startNativeMap('),
    );
    expect(
      initialize.indexOf('await _pumpUntilStyleLoaded();'),
      lessThan(
        initialize.indexOf(
          '_bridge.setRenderRequestHandler(_onNativeRenderRequested);',
        ),
      ),
    );
    final bind = map.substring(
      map.indexOf('void _bindNativeMap('),
      map.indexOf('Future<void> _pumpUntilStyleLoaded()'),
    );
    expect(bind, isNot(contains('setRenderRequestHandler')));
    expect(
      initialize.indexOf('_rendered = true;'),
      lessThan(
        initialize.indexOf(
          '_bridge.setRenderRequestHandler(_onNativeRenderRequested);',
        ),
      ),
    );
  });

  test('startup frames cannot be acquired without a painter', () {
    final render = map.substring(
      map.indexOf('void renderGesture()'),
      map.indexOf('\n  @override', map.indexOf('void renderGesture()') + 1),
    );
    expect(render, contains('if (!_initialized || !_rendered) return;'));
    expect(
      map,
      contains('mounted && _initialized && _rendered ? _bridge : null'),
    );
  });

  test('backgrounded painter keeps its lease for the forced resume frame', () {
    final paintStart = painter.indexOf('void paint(');
    final paintEnd = painter.indexOf('\n  @override', paintStart + 1);
    final paint = painter.substring(paintStart, paintEnd);
    final activeGuard = paint.indexOf('if (!gpuRenderingAllowed()) {');
    final cachedFrame = paint.indexOf('_drawLastImage(canvas, size);');
    final snapshot = paint.indexOf('frameSnapshotProvider()');
    final release = paint.indexOf('activeSnapshot.release()');

    expect(activeGuard, greaterThanOrEqualTo(0));
    expect(cachedFrame, greaterThan(activeGuard));
    expect(cachedFrame, lessThan(snapshot));
    expect(snapshot, greaterThan(activeGuard));
    expect(release, greaterThan(snapshot));
    expect(map, contains('_initialized && _rendered && _renders.isAppActive'));
    expect(map, contains('gpuRenderingAllowed: _gpuRenderingAllowed'));
  });

  test('viewport resize discards an old-size generation before repaint', () {
    final resizeStart = map.indexOf('void _applyViewport(');
    final resizeEnd = map.indexOf(
      'var _programmaticCameraIdlePending',
      resizeStart,
    );
    final resize = map.substring(resizeStart, resizeEnd);
    final pending = resize.indexOf(
      '_pendingFrameSnapshot ?? bridge.acquireFrameSnapshot()',
    );
    final discard = resize.indexOf('_pendingFrameSnapshot = null;', pending);
    final setSize = resize.indexOf('bridge.setSize(', discard);
    final release = resize.indexOf('staleSnapshot?.release();', setSize);
    final render = resize.indexOf('renderGesture();', release);

    expect(pending, greaterThanOrEqualTo(0));
    expect(discard, greaterThan(pending));
    expect(setSize, greaterThan(discard));
    expect(release, greaterThan(setSize));
    expect(render, greaterThan(release));
    expect(resize, isNot(contains('_lastProcessedFrameGeneration =')));
    expect(
      map.substring(map.indexOf('void _scheduleViewportUpdate('), resizeStart),
      contains('WidgetsBinding.instance.addPostFrameCallback'),
    );
  });

  test('style mutation drops the pending lease before native entry', () {
    expect(
      map,
      contains('beforeStyleMutation: _releaseFrameSnapshotBeforeMutation'),
    );
    final releaseStart = map.indexOf('void _releasePendingFrameSnapshot()');
    final releaseEnd = map.indexOf('\n  }', releaseStart);
    final release = map.substring(releaseStart, releaseEnd);
    expect(
      release.indexOf('_pendingFrameSnapshot = null;'),
      lessThan(release.indexOf('snapshot?.release();')),
    );
    expect(controller, contains('if (callback != null) await callback();'));
  });

  test('reentrant style mutation waits for frame queries to finish', () {
    final applying = map.indexOf('_applyingFrameSnapshot = true;');
    final camera = map.indexOf('controller?.notifyCameraChanged(', applying);
    final labels = map.indexOf('_labels.syncFromNative(bridge)', camera);
    final finish = map.indexOf('_finishApplyingFrameSnapshot();', labels);

    expect(camera, greaterThan(applying));
    expect(labels, greaterThan(camera));
    expect(finish, greaterThan(labels));
    expect(map, contains('_releaseSnapshotAfterApply = true;'));
    expect(map, contains('return (_styleMutationBarrier ??= .new()).future;'));
    final finishMethod = map.substring(
      map.indexOf('void _finishApplyingFrameSnapshot()'),
      map.indexOf('List<LabelData> _placedLabelsForController()'),
    );
    expect(
      finishMethod.indexOf('_releasePendingFrameSnapshot();'),
      lessThan(finishMethod.indexOf('barrier?.complete();')),
    );
  });

  test('controller labels come from the Dart-owned raw snapshot', () {
    expect(map, contains('placedLabelsProvider: _placedLabelsForController'));
    expect(
      controller,
      contains(
        'return _placedLabelsProvider?.call() ?? _bridge.getPlacedLabels();',
      ),
    );
  });
}

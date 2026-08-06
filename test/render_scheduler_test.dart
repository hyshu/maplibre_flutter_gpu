import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';
import 'package:maplibre_flutter_gpu/src/state/map_render_scheduler.dart';

void main() {
  test('programmatic camera renders are coalesced by frame', () {
    final map = SourceFiles.mapWidgetOnly;
    final start = map.indexOf('void _onProgrammaticCameraChange()');
    final end = map.indexOf(
      'void _emitProgrammaticCameraIdleIfSettled()',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final callback = map.substring(start, end);
    expect(callback, contains('_renders.scheduleNativeRender(force: true);'));
    expect(callback, isNot(contains('renderGesture();')));
    expect(callback, isNot(contains('scheduleRepaint();')));
  });

  test('event-driven partial maps stop until native invalidation', () {
    expect(
      shouldScheduleFrame(
        needsRepaint: false,
        cameraMoving: false,
        flingAnimating: false,
        supportsEventDrivenRendering: true,
        styleLoaded: true,
        mapIdle: false,
      ),
      isFalse,
    );
  });

  test('time-dependent rendering continues while otherwise settled', () {
    for (final state in <({bool repaint, bool camera, bool fling})>[
      (repaint: true, camera: false, fling: false),
      (repaint: false, camera: true, fling: false),
      (repaint: false, camera: false, fling: true),
    ]) {
      expect(
        shouldScheduleFrame(
          needsRepaint: state.repaint,
          cameraMoving: state.camera,
          flingAnimating: state.fling,
          supportsEventDrivenRendering: true,
          styleLoaded: true,
          mapIdle: true,
        ),
        isTrue,
      );
    }
  });

  test('an idle frame does not settle an active camera transition', () {
    expect(
      isMapRenderSettled(
        styleLoaded: true,
        mapIdle: true,
        cameraMoving: true,
        flingAnimating: false,
      ),
      isFalse,
    );
    expect(
      isMapRenderSettled(
        styleLoaded: true,
        mapIdle: true,
        cameraMoving: false,
        flingAnimating: false,
      ),
      isTrue,
    );
  });

  test('older native bridge keeps compatibility polling', () {
    expect(
      shouldScheduleFrame(
        needsRepaint: false,
        cameraMoving: false,
        flingAnimating: false,
        supportsEventDrivenRendering: false,
        styleLoaded: true,
        mapIdle: false,
      ),
      isTrue,
    );
  });

  test('native bridge exposes dirty wake without asynchronous rendering', () {
    final native = File('native/src/maplibre_bridge.cpp').readAsStringSync();
    expect(native, contains('class BridgeFrontend final'));
    expect(native, contains('g_renderDirty.store(true'));
    expect(native, contains('maplibre_set_render_request_callback'));
    expect(native, contains('maplibre_process_events'));
    expect(native, contains('maplibre_frame_needs_repaint'));
    expect(
      RegExp(r'std::nullopt,\s*false\s*\)').hasMatch(native),
      isTrue,
      reason: 'HeadlessFrontend must not render on its own',
    );
  });

  test('painter repaints by frame identity instead of every rebuild', () {
    final map = SourceFiles.mapWidgetOnly;
    final painter = SourceFiles.gpuPainterOnly;
    expect(
      RegExp(r'shouldRepaint\([^)]*\)\s*=>\s*true').hasMatch(painter),
      isFalse,
    );
    expect(painter, contains('frameSeq != oldDelegate.frameSeq'));
    expect(painter, contains('resources != oldDelegate.resources'));
    expect(
      painter,
      contains('frameSnapshotProvider != oldDelegate.frameSnapshotProvider'),
    );
    expect(map, contains('RepaintBoundary('));
  });
}

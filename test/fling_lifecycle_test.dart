import 'package:flutter_test/flutter_test.dart';

import 'support/source_files.dart';

void main() {
  test('fling reuses one AnimationController for the coordinator lifetime', () {
    final source = SourceFiles.gestureCoordinatorOnly;

    expect(
      source,
      contains('late final AnimationController _flingController;'),
    );
    expect(RegExp(r'AnimationController\(').allMatches(source), hasLength(1));
    expect(source, contains('..addListener(_onFlingTick)'));
    expect(source, contains('..addStatusListener(_onFlingStatus)'));

    final start = source.indexOf('void _startFling(Offset velocity)');
    final tick = source.indexOf('void _onFlingTick()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(tick, greaterThan(start));
    final startFling = source.substring(start, tick);
    expect(startFling, isNot(contains('AnimationController(')));
    expect(startFling, isNot(contains('.dispose()')));
    expect(startFling, isNot(contains('addListener')));
    expect(startFling, isNot(contains('addStatusListener')));
    // The throw's own kinematics — velocity, easing, progress reset — are
    // covered in test/pan_fling_tracker_test.dart. What matters here is that
    // starting a fling resets that state before the controller runs, so a
    // second throw does not inherit the first one's progress.
    expect(
      startFling.indexOf('_pan.beginFling(velocity)'),
      lessThan(startFling.indexOf('_flingController.forward(from: 0.0)')),
    );
    expect(startFling, contains('_flingController.forward(from: 0.0)'));

    final status = source.indexOf('void _onFlingStatus(', tick);
    expect(status, greaterThan(tick));
    // Both callbacks fire from the ticker, which can run for a frame after the
    // map is torn down. Each one re-reads the host's bridge, which is null once
    // the map cannot accept a camera move.
    final tickCallback = source.substring(tick, status);
    expect(tickCallback, contains('host.gestureBridge'));
    expect(tickCallback, contains('if (bridge == null) return;'));

    final statusCallback = source.substring(status);
    expect(statusCallback, contains('host.gestureBridge == null'));
    // Fling end renders once; placement-version synchronization happens inside
    // the common render path.
    expect(statusCallback, isNot(contains('requestLabelExtraction')));
    expect(statusCallback, contains('host.endCameraGesture()'));

    expect(source, isNot(contains('_flingController?.')));
  });

  test('the map disposes the coordinator before tearing down the bridge', () {
    final source = SourceFiles.mapWidgetOnly;
    final disposeStart = source.indexOf('void dispose() {');
    final disposeEnd = source.indexOf('\n  }', disposeStart);
    expect(disposeStart, greaterThanOrEqualTo(0));
    expect(disposeEnd, greaterThan(disposeStart));
    final dispose = source.substring(disposeStart, disposeEnd);
    // The ticker can fire once more between these two lines. Releasing it
    // first is what stops a fling tick from reaching a destroyed bridge.
    expect(dispose, contains('_gestures.dispose()'));
    expect(
      dispose.indexOf('_gestures.dispose()'),
      lessThan(dispose.indexOf('_bridge.destroy()')),
    );
  });

  test('pan and fling consume native placement snapshots through render', () {
    final source = SourceFiles.gestureCoordinatorOnly;

    final scaleEnd = source.indexOf('void onScaleEnd(ScaleEndDetails details)');
    final doubleTapDown = source.indexOf(
      'void onDoubleTapDown(TapDownDetails details)',
      scaleEnd,
    );
    expect(scaleEnd, greaterThanOrEqualTo(0));
    expect(doubleTapDown, greaterThan(scaleEnd));
    final scaleEndBody = source.substring(scaleEnd, doubleTapDown);
    expect(scaleEndBody, isNot(contains('requestLabelExtraction')));
    expect(scaleEndBody, contains('_renderGestureNow()'));
    expect(scaleEndBody, contains('startedFling'));
    // Idle/extract only when motion actually ended without a fling.
    expect(scaleEndBody, contains('if (!startedFling)'));
    expect(scaleEndBody, contains('host.endCameraGesture()'));

    final tick = source.indexOf('void _onFlingTick()');
    final status = source.indexOf('void _onFlingStatus(', tick);
    final tickBody = source.substring(tick, status);
    expect(tickBody, contains('host.renderGesture()'));
    expect(tickBody, isNot(contains('requestLabelExtraction')));
  });

  test('high-rate single-pointer gestures coalesce rendering by frame', () {
    final source = SourceFiles.gestureCoordinatorOnly;
    expect(source, contains('void _scheduleGestureRender()'));
    expect(source, contains('if (_gestureRenderScheduled) return;'));
    expect(source, contains('scheduleFrameCallback((_)'));
    expect(source, contains('if (cameraChanged) _scheduleGestureRender();'));
    expect(source, contains('bridge.moveBy(delta.dx, delta.dy);'));
    expect(source, contains('_scheduleGestureRender();'));
  });

  test('tap zoom gestures use the native camera paths', () {
    final coordinator = SourceFiles.gestureCoordinatorOnly;
    final widget = SourceFiles.mapWidgetOnly;

    expect(coordinator, contains('bridge.scaleByAnimated('));
    expect(coordinator, contains('host.gestureOptions.doubleTapZoomDuration'));
    expect(coordinator, contains('_zoomByTap(-1, twoFingerTap)'));
    expect(coordinator, contains('quickZoomScaleDelta('));
    expect(coordinator, contains('_suppressNextDoubleTap = true'));
    expect(coordinator, contains('void _armQuickZoomFromRawTap('));
    expect(coordinator, contains('elapsed < kDoubleTapMinTime'));
    expect(coordinator, contains('elapsed > kDoubleTapTimeout'));
    expect(coordinator, contains('void _scheduleQuickZoomUpdate()'));
    expect(coordinator, contains('if (_quickZoomUpdateScheduled) return;'));
    expect(coordinator, contains('void _applyPendingQuickZoom()'));
    expect(widget, isNot(contains('onDoubleTapCancel:')));
  });

  test('pointer down stops an active fling before gesture recognition', () {
    final source = SourceFiles.gestureCoordinatorOnly;
    final down = source.indexOf('void onPointerDown(PointerDownEvent event)');
    final end = source.indexOf('void onPointerEnd(PointerEvent event)', down);
    expect(down, greaterThanOrEqualTo(0));
    expect(end, greaterThan(down));
    final body = source.substring(down, end);
    expect(body, contains('if (_flingController.isAnimating)'));
    expect(body, contains('_flingController.stop()'));
    expect(body, contains('_pan.clearPanSamples()'));
    expect(body, contains('host.endCameraGesture()'));
  });

  test('disabling fling motion cancels an active fling after rebuild', () {
    final coordinator = SourceFiles.gestureCoordinatorOnly;
    final widget = SourceFiles.mapWidgetOnly;
    final cancelStart = coordinator.indexOf('void cancelFlingAndEndGesture()');
    final disposeStart = coordinator.indexOf('void dispose()', cancelStart);
    expect(cancelStart, greaterThanOrEqualTo(0));
    expect(disposeStart, greaterThan(cancelStart));
    final cancel = coordinator.substring(cancelStart, disposeStart);
    expect(cancel, contains('if (!_flingController.isAnimating) return;'));
    expect(cancel, contains('_flingController.stop()'));
    expect(cancel, contains('host.renderGesture()'));
    expect(cancel, contains('host.endCameraGesture()'));

    final scaleCancelStart = coordinator.indexOf(
      'void cancelScaleGestureAndEndGesture()',
    );
    final scaleCancelEnd = coordinator.indexOf(
      'void dispose()',
      scaleCancelStart,
    );
    expect(scaleCancelStart, greaterThanOrEqualTo(0));
    expect(scaleCancelEnd, greaterThan(scaleCancelStart));
    final scaleCancel = coordinator.substring(scaleCancelStart, scaleCancelEnd);
    expect(scaleCancel, contains('_suppressScaleUntilPointersReleased = true'));
    expect(scaleCancel, contains('if (!_scaleGestureActive) return;'));
    expect(scaleCancel, contains('_scaleGestureActive = false'));
    expect(scaleCancel, contains('host.endCameraGesture()'));

    final updateStart = widget.indexOf(
      'void didUpdateWidget(covariant MapLibreMap oldWidget)',
    );
    final dispose = widget.indexOf(
      '\n  @override\n  void dispose()',
      updateStart,
    );
    expect(updateStart, greaterThanOrEqualTo(0));
    expect(dispose, greaterThan(updateStart));
    final update = widget.substring(updateStart, dispose);
    expect(update, contains('!widget.scrollGesturesEnabled'));
    expect(update, contains('!widget.gestureOptions.flingEnabled'));
    expect(update, contains('_gestures.isFlinging'));
    expect(update, contains('scaleGesturesWereEnabled'));
    expect(update, contains('_gestures.cancelFlingAndEndGesture()'));
    expect(update, contains('_gestures.cancelScaleGestureAndEndGesture()'));
    expect(
      update.indexOf('_gestures.cancelFlingAndEndGesture()'),
      lessThan(update.indexOf('oldWidget.styleString != widget.styleString')),
    );
  });

  test('all continuous gestures disabled removes the scale recognizer', () {
    final source = SourceFiles.mapWidgetOnly;
    expect(source, contains('final scaleGesturesEnabled ='));
    expect(source, contains('widget.scrollGesturesEnabled ||'));
    expect(source, contains('widget.zoomGesturesEnabled ||'));
    expect(source, contains('widget.rotateGesturesEnabled ||'));
    expect(source, contains('widget.tiltGesturesEnabled;'));
    expect(source, contains('onScaleStart: scaleGesturesEnabled'));
    expect(source, contains('? _gestures.onScaleStart'));
    expect(source, contains('onScaleUpdate: scaleGesturesEnabled'));
    expect(source, contains('? _gestures.onScaleUpdate'));
    expect(source, contains('onScaleEnd: scaleGesturesEnabled'));
    expect(source, contains('? _gestures.onScaleEnd'));
  });

  test('disabled pointer input stays suppressed until every pointer ends', () {
    final source = SourceFiles.gestureCoordinatorOnly;
    expect(source, contains('var _suppressScaleUntilPointersReleased = false'));
    expect(
      source,
      contains(
        '_suppressScaleUntilPointersReleased =\n          '
        '!settings.scrollEnabled &&',
      ),
    );
    expect(
      source,
      contains('if (_suppressScaleUntilPointersReleased) return;'),
    );
    expect(
      source,
      contains(
        'if (_pointerPositions.isEmpty) {\n'
        '      _suppressScaleUntilPointersReleased = false;',
      ),
    );
  });

  test('the repaint loop stays armed while a fling is still running', () {
    final source = SourceFiles.mapWidgetOnly;
    final loop = source.indexOf('void scheduleRepaint()');
    final next = source.indexOf('void _onNativeRenderRequested()', loop);
    expect(loop, greaterThanOrEqualTo(0));
    expect(next, greaterThan(loop));
    final loopBody = source.substring(loop, next);
    // Timer arming, frame coalescing and the resume replay moved into
    // MapRenderScheduler; test/map_render_scheduler_test.dart covers them.
    // What stays here is the fling-aware idle decision, and the fact that a
    // scheduled render is a render *plus* a re-arm — dropping the re-arm would
    // stall a map that is still settling.
    expect(loopBody, contains('_renders.scheduleRepaint(interval)'));
    final renderCallback = source.substring(
      source.indexOf('_renders = MapRenderScheduler('),
      loop,
    );
    expect(renderCallback, contains('renderGesture()'));
    expect(renderCallback, contains('_finishScheduledRender()'));
    expect(loopBody, contains('isMapIdle()'));
    expect(loopBody, contains('_gestures.isFlinging'));
    expect(loopBody, contains('isMapRenderSettled('));
    expect(loopBody, contains('flingAnimating: flingAnimating'));
    expect(loopBody, isNot(contains('requestLabelExtraction()')));
  });

  test('a render projects labels only after syncing the newest snapshot', () {
    final source = SourceFiles.mapWidgetOnly;
    // Version gating and reconcile behavior now live in
    // test/label_source_test.dart, which exercises them against a fake bridge.
    // What remains widget-level is the order of the two calls: projecting
    // before syncing would place the new camera's labels using the previous
    // snapshot's anchors.
    final render = source.indexOf('void renderGesture()');
    final renderEnd = source.indexOf('\n  }', render);
    expect(render, greaterThanOrEqualTo(0));
    expect(renderEnd, greaterThan(render));
    final renderBody = source.substring(render, renderEnd);
    final syncCall = renderBody.indexOf('_labels.syncFromNative(');
    final projectCall = renderBody.indexOf('_labels.cacheScreenPositions(');
    expect(syncCall, greaterThanOrEqualTo(0));
    expect(projectCall, greaterThan(syncCall));
    expect(
      renderBody,
      contains('_labels.hasDifferentSpriteAtlas('),
      reason: 'static native frames must not reproject unchanged labels',
    );
    expect(renderBody, contains('_labels.entries.isNotEmpty'));
    expect(
      renderBody,
      contains('_gpuFrame.value++'),
      reason: 'a GPU frame should repaint without rebuilding the map widget',
    );
    expect(
      renderBody,
      contains('controller?.cameraPosition?.zoom ?? _bridge.getCameraZoom()'),
      reason: 'the camera snapshot zoom should avoid a second native query',
    );
  });
}

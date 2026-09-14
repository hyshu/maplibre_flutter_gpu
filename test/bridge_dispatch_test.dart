import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';

/// Records bridge calls without loading a native library.
class _RecordingBridge implements MaplibreBridge {
  final List<String> calls = [];

  @override
  void setStyle(String styleValue) => calls.add('setStyle($styleValue)');

  @override
  String? getStyle() {
    calls.add('getStyle');

    return '{}';
  }

  @override
  bool isStyleLoaded() {
    calls.add('isStyleLoaded');

    return true;
  }

  @override
  FrameCommandMetadata frameGetMetadata() {
    calls.add('frameGetMetadata');

    return (
      commands: nullptr,
      commandCount: 3,
      commandStride: 16,
      clearColor: null,
    );
  }

  @override
  NativeFrameSnapshotLease? acquireFrameSnapshot() {
    calls.add('acquireFrameSnapshot');

    return null;
  }

  @override
  void frameRelease(int generation) => calls.add('frameRelease($generation)');

  @override
  Offset latLonToScreen(double lat, double lon) {
    calls.add('latLonToScreen($lat, $lon)');

    return Offset(lat, lon);
  }

  @override
  void setRenderRequestHandler(void Function() handler) {
    calls.add('setRenderRequestHandler');
    handler();
  }

  @override
  void clearRenderRequestHandler() => calls.add('clearRenderRequestHandler');

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected ${invocation.memberName}');
}

void main() {
  // Public binding operations must dispatch through MaplibreBridge so callers
  // can substitute an implementation without loading native symbols.
  group('style methods dispatch through the implementing type', () {
    test('a fake receives calls made through the bridge interface', () {
      final fake = _RecordingBridge();
      final MaplibreBridge bridge = fake;

      bridge.setStyle('{"version":8}');
      bridge.getStyle();
      bridge.isStyleLoaded();

      expect(fake.calls, [
        'setStyle({"version":8})',
        'getStyle',
        'isStyleLoaded',
      ]);
    });

    test('the fake, not the real binding, produces the result', () {
      final MaplibreBridge bridge = _RecordingBridge();

      expect(bridge.getStyle(), '{}');
      expect(bridge.isStyleLoaded(), isTrue);
    });
  });

  test('frame metadata and snapshot methods dispatch through the bridge', () {
    final fake = _RecordingBridge();
    final MaplibreBridge bridge = fake;

    expect(bridge.frameGetMetadata().commandCount, 3);
    expect(bridge.acquireFrameSnapshot(), isNull);
    bridge.frameRelease(9);

    expect(fake.calls, [
      'frameGetMetadata',
      'acquireFrameSnapshot',
      'frameRelease(9)',
    ]);
  });

  test('coordinate projection dispatches through the bridge', () {
    final fake = _RecordingBridge();
    final MaplibreBridge bridge = fake;

    expect(bridge.latLonToScreen(35, 139), const Offset(35, 139));
    expect(fake.calls, ['latLonToScreen(35.0, 139.0)']);
  });

  test('render callback registration dispatches through the bridge', () {
    final fake = _RecordingBridge();
    final MaplibreBridge bridge = fake;
    var wakes = 0;

    bridge.setRenderRequestHandler(() => wakes++);
    bridge.clearRenderRequestHandler();

    expect(wakes, 1);
    expect(fake.calls, [
      'setRenderRequestHandler',
      'clearRenderRequestHandler',
    ]);
  });
}

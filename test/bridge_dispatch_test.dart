import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';

/// A stand-in for the native bridge, declared the way the controller tests
/// declare theirs: `implements`, so no native library is ever loaded.
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
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected ${invocation.memberName}');
}

void main() {
  // The bridge's domain methods live in mixins, and this is the property that
  // forced that choice over extensions. Extension methods are not part of a
  // type's interface and are dispatched statically: a fake would neither be
  // required to provide them nor be consulted when one is called through a
  // `MaplibreBridge` reference, so every test double would silently fall
  // through to the real FFI. Mixin methods are ordinary interface members.
  //
  // If these methods are ever moved to an extension, the `@override`
  // annotations above stop resolving and this file fails to compile — which
  // is the intended alarm.
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

      // The real binding would need a loaded native library to answer this;
      // reaching a value at all proves the override won.
      expect(bridge.getStyle(), '{}');
      expect(bridge.isStyleLoaded(), isTrue);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/maplibre_ffi.dart';
import 'package:maplibre_flutter_gpu/src/native/symbol_table.dart';

void main() {
  test('current Android native ABI permits asynchronous rendering', () {
    var probes = 0;

    expect(
      nativeAsyncRenderingSupported(
        isAndroid: true,
        symbols: _symbols(),
        queryNativeSupport: () {
          probes++;

          return 1;
        },
        enabled: true,
      ),
      isTrue,
    );
    expect(probes, 1);
  });

  for (final scenario in [
    (
      name: 'non-Android',
      android: false,
      enabled: true,
      snapshots: true,
      camera: true,
    ),
    (
      name: 'explicit optout',
      android: true,
      enabled: false,
      snapshots: true,
      camera: true,
    ),
    (
      name: 'old camera ABI',
      android: true,
      enabled: true,
      snapshots: true,
      camera: false,
    ),
    (
      name: 'missing snapshots',
      android: true,
      enabled: true,
      snapshots: false,
      camera: true,
    ),
    (
      name: 'legacy native library',
      android: true,
      enabled: true,
      snapshots: false,
      camera: false,
    ),
  ]) {
    test('${scenario.name} stays synchronous without querying native', () {
      expect(
        nativeAsyncRenderingSupported(
          isAndroid: scenario.android,
          symbols: _symbols(
            snapshots: scenario.snapshots,
            camera: scenario.camera,
          ),
          queryNativeSupport: () =>
              throw StateError('Native probe must not run'),
          enabled: scenario.enabled,
        ),
        isFalse,
      );
    });
  }

  test(
    'incomplete snapshot lookup cannot enable partially resolved functions',
    () {
      final symbols = _symbols();
      symbols.lookUpGroup('asynchronous frame snapshots', () {
        throw ArgumentError('maplibre_frame_release is absent');
      });

      expect(
        nativeAsyncRenderingSupported(
          isAndroid: true,
          symbols: symbols,
          queryNativeSupport: () =>
              throw StateError('Native probe must not run'),
          enabled: true,
        ),
        isFalse,
      );
    },
  );

  test('available symbols still require native backend support', () {
    expect(
      nativeAsyncRenderingSupported(
        isAndroid: true,
        symbols: _symbols(),
        queryNativeSupport: () => 0,
        enabled: true,
      ),
      isFalse,
    );
    expect(
      nativeAsyncRenderingSupported(
        isAndroid: true,
        symbols: _symbols(),
        queryNativeSupport: null,
        enabled: true,
      ),
      isFalse,
    );
  });

  test(
    'compiled rendering flag defaults on and honors an explicit override',
    () {
      const expected = bool.fromEnvironment(
        'MAPLIBRE_ENABLE_ASYNC_RENDERING',
        defaultValue: true,
      );
      var probes = 0;

      expect(
        nativeAsyncRenderingSupported(
          isAndroid: true,
          symbols: _symbols(),
          queryNativeSupport: () {
            probes++;

            return 1;
          },
        ),
        expected,
      );
      expect(probes, expected ? 1 : 0);
    },
  );
}

NativeSymbolTable _symbols({bool snapshots = true, bool camera = true}) {
  final symbols = NativeSymbolTable();
  if (snapshots) symbols.lookUpGroup('asynchronous frame snapshots', () {});
  if (camera) symbols.lookUpGroup('camera snapshot preservation', () {});

  return symbols;
}

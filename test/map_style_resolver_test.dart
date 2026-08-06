import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/controller/style_resolver.dart';

void main() {
  test('raw JSON and URLs pass through unchanged', () async {
    const raw = '  {"version":8,"sources":{},"layers":[]}';
    const url = 'https://tiles.example/style.json';

    expect(await resolveMapStyleString(raw), raw);
    expect(await resolveMapStyleString(url), url);
  });

  test('relative paths load from the Flutter asset loader', () async {
    String? loadedPath;
    final result = await resolveMapStyleString(
      'assets/map/style.json',
      assetLoader: (path) async {
        loadedPath = path;

        return '{"version":8}';
      },
    );

    expect(loadedPath, 'assets/map/style.json');
    expect(result, '{"version":8}');
  });

  test('file URIs pass through and absolute paths become file URLs', () async {
    expect(
      await resolveMapStyleString('file:///tmp/map-style.json'),
      'file:///tmp/map-style.json',
    );
    expect(
      await resolveMapStyleString('/tmp/other-style.json'),
      'file:///tmp/other-style.json',
    );
  });

  test('empty styles are rejected', () async {
    await expectLater(resolveMapStyleString('  '), throwsArgumentError);
  });

  group('resolveRequestedStyle', () {
    test('resolves the style the map is still asking for', () async {
      final result = await resolveRequestedStyle(
        requestedStyle: () => 'https://example.com/a.json',
        isAlive: () => true,
      );
      expect(result?.requested, 'https://example.com/a.json');
      expect(result?.resolved, 'https://example.com/a.json');
    });

    test('restarts when the request changes mid-resolution', () async {
      var current = 'first.json';
      final loaded = <String>[];
      final result = await resolveRequestedStyle(
        requestedStyle: () => current,
        isAlive: () => true,
        assetLoader: (path) async {
          loaded.add(path);
          // The widget rebuilds with a new style while the first is loading.
          if (path == 'first.json') current = 'second.json';

          return '{"version":8,"from":"$path"}';
        },
      );
      expect(loaded, ['first.json', 'second.json']);
      expect(result?.requested, 'second.json');
      expect(result?.resolved, contains('second.json'));
    });

    test('a failure that has been superseded is retried, not thrown', () async {
      var current = 'missing.json';
      final result = await resolveRequestedStyle(
        requestedStyle: () => current,
        isAlive: () => true,
        assetLoader: (path) async {
          if (path == 'missing.json') {
            current = 'good.json';
            throw StateError('no such asset');
          }
          return '{"version":8}';
        },
      );
      expect(result?.requested, 'good.json');
    });

    test('a failure for the style still being asked for propagates', () async {
      await expectLater(
        resolveRequestedStyle(
          requestedStyle: () => 'missing.json',
          isAlive: () => true,
          assetLoader: (_) async => throw StateError('no such asset'),
        ),
        throwsStateError,
      );
    });

    test('a map torn down mid-resolution yields nothing', () async {
      var alive = true;
      final result = await resolveRequestedStyle(
        requestedStyle: () => 'style.json',
        isAlive: () => alive,
        assetLoader: (_) async {
          alive = false;

          return '{"version":8}';
        },
      );
      expect(result, isNull);
    });
  });
}

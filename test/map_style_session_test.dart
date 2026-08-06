import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/state/map_style_session.dart';

/// Stands in for a `SpriteAtlas`: the session only ever disposes it.
class _FakeAtlas {
  _FakeAtlas(this.name);

  final String name;
  int disposeCount = 0;

  @override
  String toString() => 'atlas($name)';
}

/// Hands out a completer per style source so a test can decide the order in
/// which concurrent loads resolve.
class _ScriptedLoader {
  final Map<String, Completer<_FakeAtlas?>> pending =
      <String, Completer<_FakeAtlas?>>{};
  final List<String?> baseUrls = <String?>[];

  Future<_FakeAtlas?> load(String styleSource, {String? baseStyleUrl}) {
    baseUrls.add(baseStyleUrl);

    return (pending[styleSource] = Completer<_FakeAtlas?>()).future;
  }
}

({
  MapStyleSession<_FakeAtlas> session,
  _ScriptedLoader loader,
  List<_FakeAtlas> disposed,
})
_session() {
  final loader = _ScriptedLoader();
  final disposed = <_FakeAtlas>[];

  return (
    session: MapStyleSession<_FakeAtlas>(
      loadAtlas: loader.load,
      disposeAtlas: (atlas) {
        atlas.disposeCount++;
        disposed.add(atlas);
      },
    ),
    loader: loader,
    disposed: disposed,
  );
}

void main() {
  group('loaded latch', () {
    test('reports the transition exactly once', () {
      // The caller fires the style-loaded callback and applies the camera
      // constraints off this; a second true would double-fire both.
      final session = _session().session;

      expect(session.isLoaded, isFalse);
      expect(session.markLoaded(), isTrue);
      expect(session.markLoaded(), isFalse);
      expect(session.isLoaded, isTrue);
    });

    test('a new style arms the latch again', () {
      final session = _session().session..markLoaded();

      session.beginStyleChange();

      expect(session.isLoaded, isFalse);
      expect(session.markLoaded(), isTrue);
    });
  });

  group('sprite atlas adoption', () {
    test('a completed load is adopted and reported', () async {
      final s = _session();
      final adopted = s.session.loadSpriteAtlas('style-a', baseStyleUrl: 'u');
      s.loader.pending['style-a']!.complete(_FakeAtlas('a'));

      expect(await adopted, isTrue);
      expect(s.session.spriteAtlas?.name, 'a');
      expect(s.loader.baseUrls, <String?>['u']);
      expect(s.disposed, isEmpty);
    });

    test('a load that resolves to nothing is not adopted', () async {
      final s = _session();
      final adopted = s.session.loadSpriteAtlas('style-a');
      s.loader.pending['style-a']!.complete(null);

      expect(await adopted, isFalse);
      expect(s.session.spriteAtlas, isNull);
    });

    test('replacing the atlas disposes the previous one', () async {
      final s = _session();
      final first = _FakeAtlas('a');
      final firstLoad = s.session.loadSpriteAtlas('style-a');
      s.loader.pending['style-a']!.complete(first);
      await firstLoad;

      final secondLoad = s.session.loadSpriteAtlas('style-b');
      s.loader.pending['style-b']!.complete(_FakeAtlas('b'));
      await secondLoad;

      expect(s.session.spriteAtlas?.name, 'b');
      expect(first.disposeCount, 1);
    });
  });

  group('staleness', () {
    test(
      'an atlas that lost to a newer style is dropped and disposed',
      () async {
        // Styles can be swapped while the previous sprite sheet is still
        // downloading. Adopting the late one would paint the old style's icons
        // over the new map, and nothing else holds the image to free it.
        final s = _session();
        final slow = s.session.loadSpriteAtlas('style-a');
        final fast = s.session.loadSpriteAtlas('style-b');

        s.loader.pending['style-b']!.complete(_FakeAtlas('b'));
        expect(await fast, isTrue);

        final stale = _FakeAtlas('a');
        s.loader.pending['style-a']!.complete(stale);

        expect(await slow, isFalse);
        expect(stale.disposeCount, 1);
        expect(s.session.spriteAtlas?.name, 'b');
      },
    );

    test('beginStyleChange invalidates an in-flight load', () async {
      final s = _session();
      final load = s.session.loadSpriteAtlas('style-a');

      s.session.beginStyleChange();
      final stale = _FakeAtlas('a');
      s.loader.pending['style-a']!.complete(stale);

      expect(await load, isFalse);
      expect(stale.disposeCount, 1);
      expect(s.session.spriteAtlas, isNull);
    });

    test('beginStyleChange disposes the atlas already in use', () {
      final s = _session();
      final atlas = _FakeAtlas('a');
      unawaited(s.session.loadSpriteAtlas('style-a'));
      s.loader.pending['style-a']!.complete(atlas);

      return Future<void>.delayed(Duration.zero, () {
        s.session.beginStyleChange();
        expect(atlas.disposeCount, 1);
        expect(s.session.spriteAtlas, isNull);
      });
    });

    test('a dead caller gets no atlas, and the atlas is freed', () async {
      // The widget can be unmounted mid-download; holding the image would leak
      // it for as long as the session object survives.
      final s = _session();
      final load = s.session.loadSpriteAtlas('style-a', isAlive: () => false);
      final atlas = _FakeAtlas('a');
      s.loader.pending['style-a']!.complete(atlas);

      expect(await load, isFalse);
      expect(atlas.disposeCount, 1);
      expect(s.session.spriteAtlas, isNull);
    });
  });

  group('dispose', () {
    test('frees the atlas and refuses a load already in flight', () async {
      final s = _session();
      final load = s.session.loadSpriteAtlas('style-a');

      s.session.dispose();
      final atlas = _FakeAtlas('a');
      s.loader.pending['style-a']!.complete(atlas);

      expect(await load, isFalse);
      expect(atlas.disposeCount, 1);
    });

    test('disposes the adopted atlas exactly once', () async {
      final s = _session();
      final atlas = _FakeAtlas('a');
      final load = s.session.loadSpriteAtlas('style-a');
      s.loader.pending['style-a']!.complete(atlas);
      await load;
      s.session.markLoaded();

      s.session.dispose();
      s.session.dispose();

      expect(atlas.disposeCount, 1);
      expect(s.session.spriteAtlas, isNull);
      expect(s.session.isLoaded, isFalse);
      expect(s.session.markLoaded(), isFalse);
    });

    test('rejects style changes and new loads permanently', () async {
      final s = _session();

      s.session.dispose();
      s.session.beginStyleChange();

      expect(await s.session.loadSpriteAtlas('style-a'), isFalse);
      expect(s.loader.pending, isEmpty);
      expect(s.session.spriteAtlas, isNull);
    });
  });
}

// Owns the loaded state and sprite atlas for the current style.
//
// Generation checks prevent an atlas from being adopted after its style has
// been replaced.
library;

/// Loads an atlas referenced by a style source.
typedef SpriteAtlasLoader<A> = Future<A?> Function(
  String styleSource, {
  String? baseStyleUrl,
});

/// Manages loaded state and sprite atlas ownership for one active style.
class MapStyleSession<A extends Object> {
  MapStyleSession({required this._loadAtlas, required this._disposeAtlas});

  final SpriteAtlasLoader<A> _loadAtlas;
  final void Function(A atlas) _disposeAtlas;

  A? _atlas;
  var _loaded = false;
  var _disposed = false;
  var _generation = 0;

  /// The atlas for the current style, or null before one has been adopted.
  A? get spriteAtlas => _atlas;

  /// Whether native has reported the current style as fully loaded.
  bool get isLoaded => _loaded;

  /// Marks the current style as loaded.
  ///
  /// Returns true only for the first call for the current style. Returns false
  /// after this session is disposed.
  bool markLoaded() {
    if (_disposed || _loaded) return false;
    _loaded = true;

    return true;
  }

  /// Invalidates the current style and any atlas load still in progress.
  ///
  /// Releases the current atlas and clears the loaded state. Does nothing after
  /// this session is disposed.
  void beginStyleChange() {
    if (_disposed) return;
    _generation += 1;
    _loaded = false;
    _disposeCurrentAtlas();
  }

  /// Loads and adopts the atlas referenced by [styleSource].
  ///
  /// Returns false when no atlas is produced, the request becomes stale,
  /// [isAlive] reports that the owner is gone, or this session is disposed. Any
  /// unadopted atlas is disposed. Loader errors propagate to the caller.
  Future<bool> loadSpriteAtlas(
    String styleSource, {
    String? baseStyleUrl,
    bool Function()? isAlive,
  }) async {
    if (_disposed) return false;
    final generation = ++_generation;
    final atlas = await _loadAtlas(styleSource, baseStyleUrl: baseStyleUrl);
    if (atlas == null) return false;
    if (_disposed || generation != _generation || !(isAlive?.call() ?? true)) {
      _disposeAtlas(atlas);

      return false;
    }
    _disposeCurrentAtlas();
    _atlas = atlas;

    return true;
  }

  /// Releases owned state and permanently invalidates all atlas loads.
  ///
  /// Repeated calls do nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    _loaded = false;
    _disposeCurrentAtlas();
  }

  void _disposeCurrentAtlas() {
    final atlas = _atlas;
    _atlas = null;
    if (atlas != null) _disposeAtlas(atlas);
  }
}

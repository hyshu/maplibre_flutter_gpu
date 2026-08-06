part of '../maplibre_ffi.dart';

/// Runtime reads and mutations of the loaded style.
///
/// Operations throw an [UnsupportedError] when their native callback is
/// unavailable. Methods that surface MapLibre style errors throw a
/// [StateError].
mixin MaplibreBridgeStyleBindings {
  BridgeSessionLifecycle get _lifecycle;
  NativeSymbolTable get _symbols;
  Pointer<Int32> get _styleBoolOutput;

  // The bridge resolves these optional native callbacks.
  StyleStringVoidD? _styleLastError;
  StyleSetD? _styleSet;
  StyleStringVoidD? _styleGetJson;
  StyleStringVoidD? _styleGetLayerIds;
  StyleStringVoidD? _styleGetSourceIds;
  StyleStringVoidD? _styleGetSourceAttributions;
  StyleSetVisibilityD? _styleSetLayerVisibility;
  StyleGetVisibilityD? _styleGetLayerVisibility;
  StyleSetFilterD? _styleSetFilter;
  StyleGetFilterD? _styleGetFilter;
  StyleAddLayerD? _styleAddLayer;
  StyleLayerJsonD? _styleSetLayerProperties;
  StyleLayerIdD? _styleRemoveLayer;
  Int32VoidD? _isStyleLoaded;

  /// Whether MapLibre has parsed and loaded the current style document.
  ///
  /// Returns true when the native status check is unavailable.
  bool isStyleLoaded() {
    _lifecycle.ensureActive();
    final callback = _isStyleLoaded;

    return callback == null || callback() != 0;
  }

  /// Starts loading a style URL or raw style JSON.
  ///
  /// Use [isStyleLoaded] to check for completion.
  void setStyle(String styleValue) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(_styleSet, 'setStyle');
    final value = styleValue.toNativeUtf8();
    try {
      if (callback(value) == 0) _throwStyleError('setStyle failed');
    } finally {
      calloc.free(value);
    }
  }

  /// Returns the current style as JSON, or null when it cannot be read.
  String? getStyle() {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(_styleGetJson, 'getStyle');
    final value = callback();

    return value.address == 0 ? null : value.toDartString();
  }

  /// Returns the IDs of all layers in the current style.
  List<String> getLayerIds() => _readStyleStringList(
    _styleGetLayerIds,
    'getLayerIds is not supported by the loaded native library',
  );

  /// Returns the IDs of all sources in the current style.
  List<String> getSourceIds() => _readStyleStringList(
    _styleGetSourceIds,
    'getSourceIds is not supported by the loaded native library',
  );

  /// Returns attribution HTML resolved from the current style sources.
  List<String> getSourceAttributions() => _readStyleStringList(
    _styleGetSourceAttributions,
    'getSourceAttributions is not supported by the loaded native library',
  );

  /// Sets whether [layerId] is visible.
  void setLayerVisibility(String layerId, bool visible) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(
      _styleSetLayerVisibility,
      'setLayerVisibility',
    );
    final id = layerId.toNativeUtf8();
    try {
      if (callback(id, visible ? 1 : 0) == 0) {
        _throwStyleError('setLayerVisibility failed');
      }
    } finally {
      calloc.free(id);
    }
  }

  /// Returns whether [layerId] is visible.
  ///
  /// Returns null when the layer does not exist.
  bool? getLayerVisibility(String layerId) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(
      _styleGetLayerVisibility,
      'getLayerVisibility',
    );
    final id = layerId.toNativeUtf8();
    try {
      final status = callback(id, _styleBoolOutput);
      if (status < 0) _throwStyleError('getLayerVisibility failed');
      if (status == 0) return null;

      return _styleBoolOutput.value != 0;
    } finally {
      calloc.free(id);
    }
  }

  /// Attempts to set the JSON filter for [layerId].
  ///
  /// The JSON value `null` clears the filter. Returns false when MapLibre
  /// rejects the filter without converting the style error to an exception.
  bool setLayerFilterJson(String layerId, String filterJson) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(_styleSetFilter, 'setFilter');
    final id = layerId.toNativeUtf8();
    final filter = filterJson.toNativeUtf8();
    try {
      return callback(id, filter) != 0;
    } finally {
      calloc.free(filter);
      calloc.free(id);
    }
  }

  /// Sets the JSON filter for [layerId].
  ///
  /// The JSON value `null` clears the filter.
  void setFilterJson(String layerId, String filterJson) {
    if (!setLayerFilterJson(layerId, filterJson)) {
      _throwStyleError('setFilter failed');
    }
  }

  /// Returns the filter for [layerId] as JSON.
  String? getLayerFilterJson(String layerId) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(_styleGetFilter, 'getFilter');
    final id = layerId.toNativeUtf8();
    try {
      final value = callback(id);
      if (value.address == 0) _throwStyleError('getFilter failed');

      return value.toDartString();
    } finally {
      calloc.free(id);
    }
  }

  /// Adds the layer represented by [layerJson].
  ///
  /// When [belowLayerId] is provided, the new layer is inserted immediately
  /// before it in style order.
  void addStyleLayerJson(String layerJson, {String? belowLayerId}) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(
      _styleAddLayer,
      'addLayer',
      feature: 'runtime layer creation',
    );
    final layer = layerJson.toNativeUtf8();
    final before = belowLayerId?.toNativeUtf8() ?? nullptr.cast<Utf8>();
    try {
      if (callback(layer, before) == 0) _throwStyleError('addLayer failed');
    } finally {
      if (before.address != 0) calloc.free(before);
      calloc.free(layer);
    }
  }

  /// Applies the properties in a JSON object to [layerId].
  void setStyleLayerPropertiesJson(String layerId, String propertiesJson) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(
      _styleSetLayerProperties,
      'setLayerProperties',
      feature: 'runtime layer creation',
    );
    final id = layerId.toNativeUtf8();
    final properties = propertiesJson.toNativeUtf8();
    try {
      if (callback(id, properties) == 0) {
        _throwStyleError('setLayerProperties failed');
      }
    } finally {
      calloc.free(properties);
      calloc.free(id);
    }
  }

  /// Removes [layerId] from the current style.
  void removeStyleLayer(String layerId) {
    _lifecycle.ensureActive();
    final callback = _symbols.requireSymbol(
      _styleRemoveLayer,
      'removeLayer',
      feature: 'runtime layer creation',
    );
    final id = layerId.toNativeUtf8();
    try {
      if (callback(id) == 0) _throwStyleError('removeLayer failed');
    } finally {
      calloc.free(id);
    }
  }

  /// Reads a native JSON array and retains its string elements.
  List<String> _readStyleStringList(
    StyleStringVoidD? callback,
    String unsupportedMessage,
  ) {
    _lifecycle.ensureActive();
    if (callback == null) throw UnsupportedError(unsupportedMessage);
    final value = callback();
    if (value.address == 0) _throwStyleError(unsupportedMessage);
    final decoded = jsonDecode(value.toDartString());
    if (decoded is! List) {
      throw StateError('MapLibre returned an invalid style ID list');
    }
    return decoded.whereType<String>().toList(growable: false);
  }

  /// Throws the latest native style error or [fallback] when none is present.
  Never _throwStyleError(String fallback) {
    final value = _styleLastError?.call();
    final message = value == null || value.address == 0
        ? fallback
        : value.toDartString();
    throw StateError(message.isEmpty ? fallback : message);
  }
}

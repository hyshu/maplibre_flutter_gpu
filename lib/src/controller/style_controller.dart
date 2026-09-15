part of 'maplibre_map_controller.dart';

mixin _StyleController on _ControllerBinding {
  var _styleChangeGeneration = 0;

  /// Starts loading a replacement map style from `styleString`.
  ///
  /// `styleString` can be raw style JSON, a URL, an absolute file path, a
  /// `file:` URI, or a Flutter asset path. Relative paths are loaded from the
  /// asset bundle before the style is passed to MapLibre.
  ///
  /// For the current request, the returned future completes after the input has
  /// been resolved and MapLibre has accepted the style request. It does not wait
  /// for the style to finish loading. Use [MapLibreMap.onStyleLoadedCallback] to
  /// observe that event. When style requests overlap, an older pending future
  /// completes without applying its style.
  ///
  /// Throws an [ArgumentError] when `styleString` is empty. Asset-loading errors
  /// are propagated. Throws a [StateError] when MapLibre rejects the style.
  Future<void> setStyle(String styleString) async {
    _ensureNotDisposed();
    final generation = ++_styleChangeGeneration;
    final resolvedStyle = await resolveMapStyleString(styleString);
    _ensureNotDisposed();

    if (generation != _styleChangeGeneration) return;

    final callback = _onStyleChangeRequested;
    await _prepareStyleMutation();

    if (generation != _styleChangeGeneration) return;

    if (callback != null) {
      await callback(styleString, resolvedStyle);
    } else {
      _bridge.setStyle(resolvedStyle);
    }
  }

  /// Returns the current style as JSON.
  ///
  /// The returned future completes with `null` when MapLibre cannot provide the
  /// style document. It does not wait for an in-progress style load to finish.
  Future<String?> getStyle() async {
    _ensureNotDisposed();

    return _bridge.getStyle();
  }

  /// Returns the IDs of all layers in the current style, in style order.
  ///
  /// Each returned element is a [String]. Non-string elements are omitted. The
  /// future throws a [FormatException] when MapLibre returns malformed JSON and
  /// a [StateError] when the decoded value is not a list.
  Future<List> getLayerIds() async {
    _ensureNotDisposed();

    return _bridge.getLayerIds();
  }

  /// Returns the IDs of all sources in the current style.
  ///
  /// Non-string elements are omitted. The future throws a [FormatException]
  /// when MapLibre returns malformed JSON and a [StateError] when the decoded
  /// value is not a list.
  Future<List<String>> getSourceIds() async {
    _ensureNotDisposed();

    return _bridge.getSourceIds();
  }

  /// Returns attribution HTML resolved from the current style sources.
  ///
  /// This includes attribution loaded through TileJSON source URLs. Empty and
  /// duplicate values are omitted. The returned list is empty when no source
  /// declares attribution.
  Future<List<String>> getSourceAttributions() async {
    _ensureNotDisposed();
    final values = _bridge.getSourceAttributions();

    return values
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  /// Shows or hides the layer identified by `layerId`.
  ///
  /// The returned future completes after MapLibre accepts the change and a map
  /// update has been requested. It does not wait for the next frame to render.
  ///
  /// Throws a [StateError] when the layer does not exist or MapLibre rejects the
  /// change.
  Future<void> setLayerVisibility(String layerId, bool visible) async {
    _ensureNotDisposed();
    await _prepareStyleMutation();
    _bridge.setLayerVisibility(layerId, visible);
    _onStyleMutationRequested?.call();
  }

  /// Returns whether the layer identified by `layerId` is visible.
  ///
  /// The returned future completes with `null` when the layer does not exist.
  /// It throws a [StateError] when MapLibre cannot read the visibility value.
  Future<bool?> getLayerVisibility(String layerId) async {
    _ensureNotDisposed();

    return _bridge.getLayerVisibility(layerId);
  }

  /// Adds a fill-extrusion layer such as a 3D building layer.
  ///
  /// `sourceId` identifies an existing source and `layerId` identifies the new
  /// layer. If `belowLayerId` is provided, the new layer is inserted immediately
  /// before that layer in style order. `sourceLayer` selects a layer within a
  /// vector source.
  ///
  /// `minzoom` is inclusive and `maxzoom` is exclusive. `filter` must be a
  /// JSON-encodable MapLibre filter expression. `enableInteraction` has no
  /// effect because this package does not expose interactive layer events.
  ///
  /// The returned future completes after MapLibre accepts the layer and a map
  /// update has been requested. It does not wait for the next frame to render.
  /// Throws a [StateError] when an identifier, source, property, or expression is
  /// rejected.
  Future<void> addFillExtrusionLayer(
    String sourceId,
    String layerId,
    FillExtrusionLayerProperties properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    bool enableInteraction = true,
  }) => addLayer(
    sourceId,
    layerId,
    properties,
    belowLayerId: belowLayerId,
    sourceLayer: sourceLayer,
    minzoom: minzoom,
    maxzoom: maxzoom,
    filter: filter,
    enableInteraction: enableInteraction,
  );

  /// Adds the style layer described by `properties`.
  ///
  /// Only [FillExtrusionLayerProperties] is supported. Other property types
  /// cause an [UnsupportedError]. `sourceId` identifies an existing source and
  /// `layerId` identifies the new layer. If `belowLayerId` is provided, the new
  /// layer is inserted immediately before that layer in style order.
  ///
  /// `sourceLayer` selects a layer within a vector source. `minzoom` is
  /// inclusive and `maxzoom` is exclusive. `filter` must be a JSON-encodable
  /// MapLibre filter expression. `enableInteraction` has no effect because this
  /// package does not expose interactive layer events.
  ///
  /// The returned future completes after MapLibre accepts the layer and a map
  /// update has been requested. It does not wait for the next frame to render.
  /// Throws a [StateError] when an identifier, source, property, or expression is
  /// rejected.
  Future<void> addLayer(
    String sourceId,
    String layerId,
    LayerProperties properties, {
    String? belowLayerId,
    bool enableInteraction = true,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
  }) async {
    _ensureNotDisposed();
    if (properties is! FillExtrusionLayerProperties) {
      throw UnsupportedError(
        'Only FillExtrusionLayerProperties is currently supported',
      );
    }
    final values = properties.toJson();
    final visibility = values.remove('visibility');
    final layer = <String, dynamic>{
      'id': layerId,
      'type': 'fill-extrusion',
      'source': sourceId,
      'source-layer': ?sourceLayer,
      'minzoom': ?minzoom,
      'maxzoom': ?maxzoom,
      'filter': ?filter,
      if (visibility != null) 'layout': {'visibility': visibility},
      'paint': values,
    };
    await _prepareStyleMutation();
    _bridge.addStyleLayerJson(jsonEncode(layer), belowLayerId: belowLayerId);
    _onStyleMutationRequested?.call();
  }

  /// Applies `properties` to the layer identified by `layerId`.
  ///
  /// A `null` property value resets that property to its style-spec default.
  /// Property values must be JSON encodable. The returned future completes after
  /// MapLibre accepts the properties and a map update has been requested. It
  /// does not wait for the next frame to render.
  ///
  /// Throws a [StateError] when the layer does not exist or a property value is
  /// rejected.
  Future<void> setLayerProperties(
    String layerId,
    LayerProperties properties,
  ) async {
    _ensureNotDisposed();
    await _prepareStyleMutation();
    _bridge.setStyleLayerPropertiesJson(
      layerId,
      jsonEncode(properties.toJson(skipNulls: false)),
    );
    _onStyleMutationRequested?.call();
  }

  /// Removes the style layer identified by `layerId`.
  ///
  /// The returned future completes after MapLibre accepts the removal and a map
  /// update has been requested. It does not wait for the next frame to render.
  /// Throws a [StateError] when the layer does not exist or cannot be removed.
  Future<void> removeLayer(String layerId) async {
    _ensureNotDisposed();
    await _prepareStyleMutation();
    _bridge.removeStyleLayer(layerId);
    _onStyleMutationRequested?.call();
  }

  /// Replaces a layer's filter with `filter`, a decoded MapLibre filter
  /// expression such as `['==', ['get', 'class'], 'street']`.
  ///
  /// A `null` filter clears the current filter. The value must be JSON
  /// encodable. The returned future completes after MapLibre accepts the filter
  /// and a map update has been requested. It does not wait for the next frame to
  /// render.
  ///
  /// Throws a [StateError] when the layer does not exist or MapLibre rejects the
  /// expression. Use [setLayerFilter] when rejection is an expected outcome.
  Future<void> setFilter(String layerId, Object? filter) async {
    await _applyFilterJson(
      layerId,
      jsonEncode(filter),
      throwWhenUnapplied: true,
    );
  }

  /// Attempts to replace a layer's filter using raw JSON in `filter`.
  ///
  /// The JSON value `null` clears the filter. The returned future completes with
  /// `true` when the filter was applied. It completes with `false` when the layer
  /// does not exist or MapLibre rejects the expression. A `false` result leaves
  /// the style unchanged.
  Future<bool> setLayerFilter(String layerId, String filter) =>
      _applyFilterJson(layerId, filter, throwWhenUnapplied: false);

  /// The one path to native for both filter setters.
  ///
  /// `throwWhenUnapplied` selects which failure contract applies. The native
  /// call and the repaint that follows a real change are shared, so the two
  /// public methods cannot drift on when the map redraws.
  Future<bool> _applyFilterJson(
    String layerId,
    String filterJson, {
    required bool throwWhenUnapplied,
  }) async {
    _ensureNotDisposed();
    if (throwWhenUnapplied) {
      // The bridge raises MapLibre's own error text, which is more useful than
      // anything reconstructable from a bool.
      await _prepareStyleMutation();
      _bridge.setFilterJson(layerId, filterJson);
      _onStyleMutationRequested?.call();

      return true;
    }
    await _prepareStyleMutation();
    final applied = _bridge.setLayerFilterJson(layerId, filterJson);
    if (applied) _onStyleMutationRequested?.call();

    return applied;
  }

  /// Returns the decoded filter for the layer identified by `layerId`.
  ///
  /// The returned future completes with `null` when the layer has no filter. It
  /// throws a [StateError] when the layer does not exist or its filter cannot be
  /// read. It throws a [FormatException] when MapLibre returns invalid JSON.
  Future<Object?> getFilter(String layerId) async {
    _ensureNotDisposed();
    final filter = _bridge.getLayerFilterJson(layerId);

    return filter == null ? null : jsonDecode(filter);
  }

  Future<void> _prepareStyleMutation() async {
    final callback = _beforeStyleMutation;
    if (callback != null) await callback();
    _ensureNotDisposed();
  }

  void _disposeStyle() {
    _styleChangeGeneration++;
  }
}

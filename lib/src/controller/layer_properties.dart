/// Properties accepted by a MapLibre style layer.
abstract interface class LayerProperties {
  Map<String, dynamic> toJson({bool skipNulls = true});
}

/// Paint and layout properties for a `heatmap` layer.
///
/// Values accept constants and MapLibre style expressions. Weight and radius
/// can depend on feature properties. Color expressions use `heatmap-density`.
class const HeatmapLayerProperties({
  /// Kernel radius in logical pixels.
  final dynamic heatmapRadius,

  /// Contribution of each point to the accumulated density.
  final dynamic heatmapWeight,

  /// Multiplier applied to the accumulated density before color mapping.
  final dynamic heatmapIntensity,

  /// Color ramp evaluated from density values between zero and one.
  final dynamic heatmapColor,

  /// Opacity applied after the density has been mapped to color.
  final dynamic heatmapOpacity,

  /// Layout visibility, either `visible` or `none`.
  final dynamic visibility,
}) implements LayerProperties {
  /// Replaces properties whose values in `changes` are non-null.
  HeatmapLayerProperties copyWith(HeatmapLayerProperties changes) => .new(
    heatmapRadius: changes.heatmapRadius ?? heatmapRadius,
    heatmapWeight: changes.heatmapWeight ?? heatmapWeight,
    heatmapIntensity: changes.heatmapIntensity ?? heatmapIntensity,
    heatmapColor: changes.heatmapColor ?? heatmapColor,
    heatmapOpacity: changes.heatmapOpacity ?? heatmapOpacity,
    visibility: changes.visibility ?? visibility,
  );

  /// Encodes style property names, retaining reset values when `skipNulls`
  /// is false.
  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) {
    final result = <String, dynamic>{};

    void add(String name, dynamic value) {
      if (value != null || !skipNulls) result[name] = value;
    }

    add('heatmap-radius', heatmapRadius);
    add('heatmap-weight', heatmapWeight);
    add('heatmap-intensity', heatmapIntensity);
    add('heatmap-color', heatmapColor);
    add('heatmap-opacity', heatmapOpacity);
    add('visibility', visibility);

    return result;
  }

  /// Reads style property names while leaving expression values unchanged.
  factory fromJson(Map<String, dynamic> json) => .new(
    heatmapRadius: json['heatmap-radius'],
    heatmapWeight: json['heatmap-weight'],
    heatmapIntensity: json['heatmap-intensity'],
    heatmapColor: json['heatmap-color'],
    heatmapOpacity: json['heatmap-opacity'],
    visibility: json['visibility'],
  );
}

/// Paint and layout properties for a `hillshade` layer.
///
/// Values accept constants and zoom expressions.
/// Multidirectional shading accepts arrays of light directions, altitudes,
/// highlight colors, and shadow colors for up to four lights. Shorter arrays
/// repeat their last value. Feature expressions are not supported.
class const HillshadeLayerProperties({
  /// Color applied to terrain accents by the `standard` method.
  final dynamic hillshadeAccentColor,

  /// Strength of the shading, between zero and one.
  final dynamic hillshadeExaggeration,

  /// Color or array of colors for slopes facing the lights.
  final dynamic hillshadeHighlightColor,

  /// Light altitude or array of altitudes from zero to 90 degrees above the
  /// horizon. Used by `basic`, `combined`, and `multidirectional` shading.
  final dynamic hillshadeIlluminationAltitude,

  /// Reference for light directions, either `map` or `viewport`.
  final dynamic hillshadeIlluminationAnchor,

  /// Light direction or array of directions from zero to 359 clockwise degrees
  /// from north.
  /// North is the top of the viewport when the anchor is `viewport`.
  final dynamic hillshadeIlluminationDirection,

  /// Shading algorithm, one of `standard`, `basic`, `combined`, `igor`, or
  /// `multidirectional`.
  final dynamic hillshadeMethod,

  /// Color or array of colors for slopes facing away from the lights.
  final dynamic hillshadeShadowColor,

  /// Layout visibility, either `visible` or `none`.
  final dynamic visibility,
}) implements LayerProperties {
  /// Replaces properties whose values in `changes` are non-null.
  HillshadeLayerProperties copyWith(HillshadeLayerProperties changes) => .new(
    hillshadeAccentColor: changes.hillshadeAccentColor ?? hillshadeAccentColor,
    hillshadeExaggeration:
        changes.hillshadeExaggeration ?? hillshadeExaggeration,
    hillshadeHighlightColor:
        changes.hillshadeHighlightColor ?? hillshadeHighlightColor,
    hillshadeIlluminationAltitude:
        changes.hillshadeIlluminationAltitude ?? hillshadeIlluminationAltitude,
    hillshadeIlluminationAnchor:
        changes.hillshadeIlluminationAnchor ?? hillshadeIlluminationAnchor,
    hillshadeIlluminationDirection:
        changes.hillshadeIlluminationDirection ??
        hillshadeIlluminationDirection,
    hillshadeMethod: changes.hillshadeMethod ?? hillshadeMethod,
    hillshadeShadowColor: changes.hillshadeShadowColor ?? hillshadeShadowColor,
    visibility: changes.visibility ?? visibility,
  );

  /// Encodes style property names, retaining reset values when `skipNulls`
  /// is false.
  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) {
    final result = <String, dynamic>{};

    void add(String name, dynamic value) {
      if (value != null || !skipNulls) result[name] = value;
    }

    add('hillshade-accent-color', hillshadeAccentColor);
    add('hillshade-exaggeration', hillshadeExaggeration);
    add('hillshade-highlight-color', hillshadeHighlightColor);
    add('hillshade-illumination-altitude', hillshadeIlluminationAltitude);
    add('hillshade-illumination-anchor', hillshadeIlluminationAnchor);
    add('hillshade-illumination-direction', hillshadeIlluminationDirection);
    add('hillshade-method', hillshadeMethod);
    add('hillshade-shadow-color', hillshadeShadowColor);
    add('visibility', visibility);

    return result;
  }

  /// Reads style property names while leaving expression values unchanged.
  factory fromJson(Map<String, dynamic> json) => .new(
    hillshadeAccentColor: json['hillshade-accent-color'],
    hillshadeExaggeration: json['hillshade-exaggeration'],
    hillshadeHighlightColor: json['hillshade-highlight-color'],
    hillshadeIlluminationAltitude: json['hillshade-illumination-altitude'],
    hillshadeIlluminationAnchor: json['hillshade-illumination-anchor'],
    hillshadeIlluminationDirection: json['hillshade-illumination-direction'],
    hillshadeMethod: json['hillshade-method'],
    hillshadeShadowColor: json['hillshade-shadow-color'],
    visibility: json['visibility'],
  );
}

/// Paint and layout properties for a `fill-extrusion` layer.
///
/// Values are intentionally `dynamic`: MapLibre properties accept both
/// constants and style expressions such as `['get', 'height']`.
class const FillExtrusionLayerProperties({
  final dynamic fillExtrusionOpacity,
  final dynamic fillExtrusionColor,
  final dynamic fillExtrusionTranslate,
  final dynamic fillExtrusionTranslateAnchor,
  final dynamic fillExtrusionPattern,
  final dynamic fillExtrusionHeight,
  final dynamic fillExtrusionBase,
  final dynamic fillExtrusionVerticalGradient,
  final dynamic visibility,
}) implements LayerProperties {
  FillExtrusionLayerProperties copyWith(
    FillExtrusionLayerProperties changes,
  ) => .new(
    fillExtrusionOpacity: changes.fillExtrusionOpacity ?? fillExtrusionOpacity,
    fillExtrusionColor: changes.fillExtrusionColor ?? fillExtrusionColor,
    fillExtrusionTranslate:
        changes.fillExtrusionTranslate ?? fillExtrusionTranslate,
    fillExtrusionTranslateAnchor:
        changes.fillExtrusionTranslateAnchor ?? fillExtrusionTranslateAnchor,
    fillExtrusionPattern: changes.fillExtrusionPattern ?? fillExtrusionPattern,
    fillExtrusionHeight: changes.fillExtrusionHeight ?? fillExtrusionHeight,
    fillExtrusionBase: changes.fillExtrusionBase ?? fillExtrusionBase,
    fillExtrusionVerticalGradient:
        changes.fillExtrusionVerticalGradient ?? fillExtrusionVerticalGradient,
    visibility: changes.visibility ?? visibility,
  );

  @override
  Map<String, dynamic> toJson({bool skipNulls = true}) {
    final result = <String, dynamic>{};

    void add(String name, dynamic value) {
      if (value != null || !skipNulls) result[name] = value;
    }

    add('fill-extrusion-opacity', fillExtrusionOpacity);
    add('fill-extrusion-color', fillExtrusionColor);
    add('fill-extrusion-translate', fillExtrusionTranslate);
    add('fill-extrusion-translate-anchor', fillExtrusionTranslateAnchor);
    add('fill-extrusion-pattern', fillExtrusionPattern);
    add('fill-extrusion-height', fillExtrusionHeight);
    add('fill-extrusion-base', fillExtrusionBase);
    add('fill-extrusion-vertical-gradient', fillExtrusionVerticalGradient);
    add('visibility', visibility);

    return result;
  }

  factory fromJson(Map<String, dynamic> json) => .new(
    fillExtrusionOpacity: json['fill-extrusion-opacity'],
    fillExtrusionColor: json['fill-extrusion-color'],
    fillExtrusionTranslate: json['fill-extrusion-translate'],
    fillExtrusionTranslateAnchor: json['fill-extrusion-translate-anchor'],
    fillExtrusionPattern: json['fill-extrusion-pattern'],
    fillExtrusionHeight: json['fill-extrusion-height'],
    fillExtrusionBase: json['fill-extrusion-base'],
    fillExtrusionVerticalGradient: json['fill-extrusion-vertical-gradient'],
    visibility: json['visibility'],
  );
}

/// Properties accepted by a MapLibre style layer.
abstract interface class LayerProperties {
  Map<String, dynamic> toJson({bool skipNulls = true});
}

/// Paint and layout properties for a `fill-extrusion` layer.
///
/// Values are intentionally `dynamic`: MapLibre properties accept both
/// constants and style expressions such as `['get', 'height']`.
class FillExtrusionLayerProperties implements LayerProperties {
  const FillExtrusionLayerProperties({
    this.fillExtrusionOpacity,
    this.fillExtrusionColor,
    this.fillExtrusionTranslate,
    this.fillExtrusionTranslateAnchor,
    this.fillExtrusionPattern,
    this.fillExtrusionHeight,
    this.fillExtrusionBase,
    this.fillExtrusionVerticalGradient,
    this.visibility,
  });

  final dynamic fillExtrusionOpacity;
  final dynamic fillExtrusionColor;
  final dynamic fillExtrusionTranslate;
  final dynamic fillExtrusionTranslateAnchor;
  final dynamic fillExtrusionPattern;
  final dynamic fillExtrusionHeight;
  final dynamic fillExtrusionBase;
  final dynamic fillExtrusionVerticalGradient;
  final dynamic visibility;

  FillExtrusionLayerProperties copyWith(
    FillExtrusionLayerProperties changes,
  ) => FillExtrusionLayerProperties(
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

  factory FillExtrusionLayerProperties.fromJson(Map<String, dynamic> json) =>
      FillExtrusionLayerProperties(
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

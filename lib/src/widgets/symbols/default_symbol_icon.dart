part of 'default_symbol_builders.dart';

/// Builds the default style-derived sprite for a placed symbol.
///
/// Returns null when [MapSymbol.icon] is null.
Widget? buildDefaultSymbolIcon(BuildContext context, MapSymbol symbol) {
  final icon = symbol.icon;
  if (icon == null) return null;
  final data = symbol.data;
  if (data.iconOpacity <= 0) return const SizedBox.shrink();
  final hasTextFit = data.iconFitWidth > 0 && data.iconFitHeight > 0;
  final iconScale = data.iconScale.isFinite && data.iconScale > 0
      ? data.iconScale
      : 1.0;
  final fitSize = hasTextFit
      ? icon.fittedContentSize(
              Size(
                data.iconFitWidth / iconScale,
                data.iconFitHeight / iconScale,
              ),
            ) *
            iconScale
      : null;
  Widget result = SpriteIconWidget(
    icon: icon,
    scale: data.iconScale,
    opacity: data.iconOpacity,
    tint: data.iconColor,
    fitSize: fitSize,
    fitSizeConstrained: true,
    haloColor: data.iconHaloColor,
    haloWidth: data.iconHaloWidth,
    haloBlur: data.iconHaloBlur,
  );
  // Only map-aligned line icons inherit the path direction.
  if (data.iconRotationWithMap && (data.iconAlongLine || data.alongLine)) {
    final path = data.iconPath.isNotEmpty ? data.iconPath : data.textPath;
    final pathAngle = _pathAngle(
      path,
      data.iconAngle,
      keepUpright: data.iconKeepUpright,
    );
    result = _applyLineSymbolTransform(
      result,
      data.iconTransform,
      pathAngle + data.iconRotation,
    );
  } else {
    result = _applyPointSymbolTransform(result, data.iconTransform);
  }

  return _applySymbolTranslation(
    result,
    data.iconTranslateX,
    data.iconTranslateY,
  );
}

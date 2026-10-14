part of 'symbol_overlay.dart';

class const _DefaultSymbolVisuals({
  required final LabelData data,
  required final SpriteIcon? sprite,
  required final SpriteAtlas? spriteAtlas,
  required final Widget? icon,
  required final Widget? text,
}) {
  factory from(BuildContext context, MapSymbol symbol) => .new(
    data: symbol.data,
    sprite: symbol.icon,
    spriteAtlas: symbol.spriteAtlas,
    icon: buildDefaultSymbolIcon(context, symbol),
    text: buildDefaultSymbolText(context, symbol),
  );

  _DefaultSymbolVisuals update(BuildContext context, MapSymbol symbol) {
    final sameSprite = identical(sprite, symbol.icon);
    final sameSpriteAtlas = identical(spriteAtlas, symbol.spriteAtlas);
    final sameIconContent = _sameDefaultIconContent(data, symbol.data);
    final sameIconVisual =
        sameIconContent &&
        _sameAffineTransform(data.iconTransform, symbol.data.iconTransform);
    final sameTextContent = _sameDefaultTextContent(data, symbol.data);
    final sameTextVisual =
        sameTextContent &&
        _sameAffineTransform(data.textTransform, symbol.data.textTransform);
    if (SymbolProfileCounters.enabled) {
      if (!sameTextVisual || !sameSpriteAtlas) {
        SymbolProfileCounters.add(SymbolProfileCounters.textVisualMisses);
      }
      if (!sameIconVisual || !sameSprite) {
        SymbolProfileCounters.add(SymbolProfileCounters.iconVisualMisses);
      }
      if ((sameTextContent && !sameTextVisual) ||
          (sameIconContent && !sameIconVisual)) {
        SymbolProfileCounters.add(SymbolProfileCounters.transformOnlyMisses);
      }
    }
    if (sameIconVisual && sameTextVisual && sameSprite && sameSpriteAtlas) {
      return this;
    }

    return .new(
      data: symbol.data,
      sprite: symbol.icon,
      spriteAtlas: symbol.spriteAtlas,
      icon: sameIconVisual && sameSprite
          ? icon
          : buildDefaultSymbolIcon(context, symbol),
      text: sameTextVisual && sameSpriteAtlas
          ? text
          : buildDefaultSymbolText(context, symbol),
    );
  }
}

// Content comparisons exclude the affine transforms, which change on every
// rotated or pitched camera frame while the built widget content does not.
bool _sameDefaultIconContent(LabelData left, LabelData right) =>
    identical(left, right) ||
    left.iconScale == right.iconScale &&
        left.iconOpacity == right.iconOpacity &&
        left.iconR == right.iconR &&
        left.iconG == right.iconG &&
        left.iconB == right.iconB &&
        left.iconA == right.iconA &&
        left.iconHaloR == right.iconHaloR &&
        left.iconHaloG == right.iconHaloG &&
        left.iconHaloB == right.iconHaloB &&
        left.iconHaloA == right.iconHaloA &&
        left.iconHaloWidth == right.iconHaloWidth &&
        left.iconHaloBlur == right.iconHaloBlur &&
        left.iconFitWidth == right.iconFitWidth &&
        left.iconFitHeight == right.iconFitHeight &&
        left.iconRotationWithMap == right.iconRotationWithMap &&
        left.iconAlongLine == right.iconAlongLine &&
        left.alongLine == right.alongLine &&
        left.iconAngle == right.iconAngle &&
        left.iconKeepUpright == right.iconKeepUpright &&
        left.iconRotation == right.iconRotation &&
        left.iconTranslateX == right.iconTranslateX &&
        left.iconTranslateY == right.iconTranslateY &&
        (!_iconFollowsPath(left) ||
            _sameLabelPath(left.iconPath, right.iconPath) &&
                _sameLabelPath(left.textPath, right.textPath));

// Only map-aligned line icons read a path; see buildDefaultSymbolIcon.
bool _iconFollowsPath(LabelData data) =>
    data.iconRotationWithMap && (data.iconAlongLine || data.alongLine);

bool _sameDefaultTextContent(LabelData left, LabelData right) =>
    identical(left, right) ||
    left.textPlaced == right.textPlaced &&
        left.text == right.text &&
        left.visualText == right.visualText &&
        left.fontSize == right.fontSize &&
        left.textR == right.textR &&
        left.textG == right.textG &&
        left.textB == right.textB &&
        left.textA == right.textA &&
        left.haloR == right.haloR &&
        left.haloG == right.haloG &&
        left.haloB == right.haloB &&
        left.haloA == right.haloA &&
        left.haloWidth == right.haloWidth &&
        left.haloBlur == right.haloBlur &&
        left.textOpacity == right.textOpacity &&
        left.letterSpacing == right.letterSpacing &&
        left.lineHeight == right.lineHeight &&
        left.maxWidth == right.maxWidth &&
        left.textW == right.textW &&
        left.textFont == right.textFont &&
        _sameStrings(left.textFonts, right.textFonts) &&
        _sameTextSections(left.textSections, right.textSections) &&
        _sameTextSections(left.visualTextSections, right.visualTextSections) &&
        left.alongLine == right.alongLine &&
        left.vertical == right.vertical &&
        left.textRotation == right.textRotation &&
        left.textKeepUpright == right.textKeepUpright &&
        left.textJustify == right.textJustify &&
        left.textDirection == right.textDirection &&
        left.textTranslateX == right.textTranslateX &&
        left.textTranslateY == right.textTranslateY &&
        (!left.alongLine ||
            left.angle == right.angle &&
                _sameLabelPath(left.textPath, right.textPath));

bool _sameAffineTransform(
  LabelAffineTransform left,
  LabelAffineTransform right,
) =>
    identical(left, right) ||
    left.xx == right.xx &&
        left.xy == right.xy &&
        left.yx == right.yx &&
        left.yy == right.yy;

bool _sameLabelPath(List<LabelPathPoint> left, List<LabelPathPoint> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].x != right[index].x || left[index].y != right[index].y) {
      return false;
    }
  }

  return true;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }

  return true;
}

bool _sameTextSections(
  List<LabelTextSection> left,
  List<LabelTextSection> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.start != b.start ||
        a.end != b.end ||
        a.fontScale != b.fontScale ||
        a.color != b.color ||
        a.imageId != b.imageId ||
        !_sameStrings(a.fonts, b.fonts)) {
      return false;
    }
  }

  return true;
}

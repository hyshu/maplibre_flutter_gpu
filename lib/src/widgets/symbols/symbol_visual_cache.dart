part of 'symbol_overlay.dart';

class const _DefaultSymbolVisuals({
  required final LabelData data,
  required final DefaultTextScale textScale,
  required final SpriteIcon? sprite,
  required final SpriteAtlas? spriteAtlas,
  required final Widget? icon,
  required final DefaultSymbolTextContent? textContent,
  required final Widget? text,
}) {
  /// Builds the visuals of [symbol], shaping text exactly when [exact].
  factory from(BuildContext context, MapSymbol symbol, {required bool exact}) {
    final textScale = DefaultTextScale.of(
      symbol.data,
      symbol.key,
      exact: exact,
    );
    final textContent = buildDefaultSymbolTextContent(
      context,
      symbol,
      textScale,
    );

    return .new(
      data: symbol.data,
      textScale: textScale,
      sprite: symbol.icon,
      spriteAtlas: symbol.spriteAtlas,
      icon: buildDefaultSymbolIcon(context, symbol),
      textContent: textContent,
      text: textContent == null
          ? null
          : placeDefaultSymbolText(textContent, symbol.data, textScale),
    );
  }

  _DefaultSymbolVisuals update(
    BuildContext context,
    MapSymbol symbol, {
    required bool exact,
    required DefaultTextReshapeBudget budget,
  }) {
    final sameSprite = identical(sprite, symbol.icon);
    final sameSpriteAtlas = identical(spriteAtlas, symbol.spriteAtlas);
    final sameIconContent = _sameDefaultIconContent(data, symbol.data);
    final sameIconVisual =
        sameIconContent &&
        _sameAffineTransform(data.iconTransform, symbol.data.iconTransform);
    final nextTextScale = DefaultTextScale.of(
      symbol.data,
      symbol.key,
      previous: textScale,
      exact: exact,
      budget: budget,
    );
    final sameTextShaping =
        _sameDefaultTextContent(data, symbol.data) &&
        textScale.shapesLike(nextTextScale);
    // Inline images compensate for the label scale in their shaped dimensions.
    final sameInlineImageSizes =
        textScale.ratio == nextTextScale.ratio ||
        !data.textSections.any((section) => section.imageId != null);
    // Content built for whole device pixels differs from scaled content.
    final sameTextContent =
        sameTextShaping &&
        sameInlineImageSizes &&
        textScale.pixelAligns(data) == nextTextScale.pixelAligns(symbol.data);
    // With unchanged content, the ratio only changes the placement transform.
    final sameTextVisual =
        sameTextContent &&
        textScale.ratio == nextTextScale.ratio &&
        _sameAffineTransform(data.textTransform, symbol.data.textTransform);
    if (SymbolProfileCounters.enabled) {
      if (!sameTextVisual || !sameSpriteAtlas) {
        SymbolProfileCounters.add(SymbolProfileCounters.textVisualMisses);
      }
      if (!sameIconVisual || !sameSprite) {
        SymbolProfileCounters.add(SymbolProfileCounters.iconVisualMisses);
      }
      if ((sameTextShaping && !sameTextVisual) ||
          (sameIconContent && !sameIconVisual)) {
        SymbolProfileCounters.add(SymbolProfileCounters.transformOnlyMisses);
      }
    }
    if (sameIconVisual && sameTextVisual && sameSprite && sameSpriteAtlas) {
      return this;
    }
    final content = textContent;
    final DefaultSymbolTextContent? nextContent;
    final Widget? nextText;
    if (sameTextVisual && sameSpriteAtlas) {
      nextContent = content;
      nextText = text;
    } else if (sameTextContent &&
        sameSpriteAtlas &&
        content?.placement != .self) {
      // Only the transform changed, which the placement applies around the
      // unchanged content.
      nextContent = content;
      nextText = content == null
          ? null
          : placeDefaultSymbolText(content, symbol.data, nextTextScale);
    } else {
      nextContent = buildDefaultSymbolTextContent(
        context,
        symbol,
        nextTextScale,
      );
      nextText = nextContent == null
          ? null
          : placeDefaultSymbolText(nextContent, symbol.data, nextTextScale);
    }

    return .new(
      data: symbol.data,
      textScale: nextTextScale,
      sprite: symbol.icon,
      spriteAtlas: symbol.spriteAtlas,
      icon: sameIconVisual && sameSprite
          ? icon
          : buildDefaultSymbolIcon(context, symbol),
      textContent: nextContent,
      text: nextText,
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

// Sizes, halo widths, and the collision width are compared through
// DefaultTextScale, which quantizes them.
bool _sameDefaultTextContent(LabelData left, LabelData right) =>
    identical(left, right) ||
    left.textPlaced == right.textPlaced &&
        left.text == right.text &&
        left.visualText == right.visualText &&
        left.textR == right.textR &&
        left.textG == right.textG &&
        left.textB == right.textB &&
        left.textA == right.textA &&
        left.haloR == right.haloR &&
        left.haloG == right.haloG &&
        left.haloB == right.haloB &&
        left.haloA == right.haloA &&
        left.textOpacity == right.textOpacity &&
        left.letterSpacing == right.letterSpacing &&
        left.lineHeight == right.lineHeight &&
        left.maxWidth == right.maxWidth &&
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

part of 'default_symbol_builders.dart';

/// Builds the default style-derived text for a placed symbol.
///
/// Returns null when no non-empty text label was placed.
Widget? buildDefaultSymbolText(BuildContext context, MapSymbol symbol) {
  final data = symbol.data;
  if (!data.textPlaced || data.text.isEmpty) return null;
  if (data.textOpacity <= 0) return const SizedBox.shrink();
  final scale = DefaultTextScale.of(data, symbol.key);
  final fontSize = scale.fontSize;
  final fonts = data.textFonts.isNotEmpty ? data.textFonts : [data.textFont];
  final font = _mapLibreFonts(fonts);
  final fillStyle = TextStyle(
    fontSize: fontSize,
    color: data.textColor,
    fontFamily: font.family,
    fontFamilyFallback: font.fallback,
    fontWeight: font.weight,
    fontStyle: font.style,
    letterSpacing: data.letterSpacing * fontSize,
    height: data.lineHeight,
  );
  Widget text;
  if (data.alongLine && data.textPath.length >= 2) {
    final visualSections = data.visualTextSections.isNotEmpty
        ? data.visualTextSections
        : data.visualText == data.text
        ? data.textSections
        : const <LabelTextSection>[];
    final visualParts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.visualText,
      sections: visualSections,
    );
    text = _buildPathText(data, visualParts, scale);
  } else if (data.vertical) {
    final parts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.text,
      sections: data.textSections,
    );
    text = _buildVerticalText(data, parts, scale);
    text = _applyPointSymbolTransform(text, data.textTransform, scale.ratio);
  } else {
    final parts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.text,
      sections: data.textSections,
    );
    text = _buildPointText(data, parts, fillStyle, scale);
    text = data.alongLine
        ? _applyLineSymbolTransform(
            text,
            data.textTransform,
            _pathAngle(
                  data.textPath,
                  data.angle,
                  keepUpright: data.textKeepUpright,
                ) +
                data.textRotation,
            scale.ratio,
          )
        : _applyPointSymbolTransform(text, data.textTransform, scale.ratio);
  }
  final opacity = data.textOpacity.clamp(0.0, 1.0);
  if (opacity < 1) text = Opacity(opacity: opacity, child: text);

  // Assistive technology reads each label once. The glyph, halo, and inline
  // image widgets underneath would otherwise each announce a fragment.
  return Semantics(
    container: true,
    excludeSemantics: true,
    label: _symbolSemanticsLabel(data),
    textDirection: data.textDirection,
    child: _applySymbolTranslation(
      text,
      data.textTranslateX,
      data.textTranslateY,
    ),
  );
}

/// The logical label text without the placeholders of inline images.
String _symbolSemanticsLabel(LabelData data) {
  final text = data.text;
  final imageSections = [
    for (final section in data.textSections)
      if (section.imageId != null) section,
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (imageSections.isEmpty) return text;
  final buffer = StringBuffer();
  var offset = 0;
  for (final section in imageSections) {
    final start = section.start.clamp(offset, text.length);
    final end = section.end.clamp(start, text.length);
    buffer.write(text.substring(offset, start));
    offset = end;
  }
  buffer.write(text.substring(offset));

  return buffer.toString();
}

class const _SymbolTextPart({
  required final String text,
  required final TextStyle style,
  final SpriteIcon? image,
  final double imageScale = 1,
  final bool imageSection = false,
});

List<_SymbolTextPart> _symbolTextParts(
  MapSymbol symbol,
  TextStyle baseStyle,
  List<String> baseFonts, {
  required String text,
  required List<LabelTextSection> sections,
}) {
  final data = symbol.data;
  if (sections.isEmpty) return [_SymbolTextPart(text: text, style: baseStyle)];
  final sortedSections = sections.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final parts = <_SymbolTextPart>[];
  var offset = 0;
  for (final section in sortedSections) {
    final start = section.start.clamp(offset, text.length);
    final end = section.end.clamp(start, text.length);
    if (start > offset) {
      parts.add(
        _SymbolTextPart(text: text.substring(offset, start), style: baseStyle),
      );
    }
    final scale = section.fontScale.isFinite && section.fontScale > 0
        ? section.fontScale
        : 1.0;
    final sectionFonts = section.fonts.isEmpty ? baseFonts : section.fonts;
    final font = _mapLibreFonts(sectionFonts);
    final style = baseStyle.copyWith(
      fontSize: (baseStyle.fontSize ?? data.fontSize) * scale,
      color: section.color ?? baseStyle.color,
      fontFamily: font.family,
      fontFamilyFallback: font.fallback,
      fontWeight: font.weight,
      fontStyle: font.style,
    );
    final imageId = section.imageId;
    parts.add(
      _SymbolTextPart(
        text: text.substring(start, end),
        style: style,
        image: imageId == null ? null : symbol.spriteAtlas?[imageId],
        imageScale: scale,
        imageSection: imageId != null,
      ),
    );
    offset = end;
  }
  if (offset < text.length) {
    parts.add(_SymbolTextPart(text: text.substring(offset), style: baseStyle));
  }

  return parts;
}

Widget _buildPointText(
  LabelData data,
  List<_SymbolTextPart> parts,
  TextStyle baseStyle,
  DefaultTextScale scale,
) {
  final fontSize = scale.fontSize;
  final boxWidth = scale.boxWidth;
  final maxWidth = boxWidth > 0
      ? boxWidth
      : (data.maxWidth > 0 ? data.maxWidth * fontSize : fontSize * 8);
  Widget label(bool halo) => _formattedText(
    data,
    parts,
    baseStyle,
    scale,
    halo: halo,
    maxLines: data.alongLine ? 1 : null,
  );
  final visual = scale.haloWidth > 0
      ? Stack(
          alignment: Alignment.center,
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [label(true), label(false)],
        )
      : label(false);

  return SizedBox(width: maxWidth, child: visual);
}

Widget _formattedText(
  LabelData data,
  List<_SymbolTextPart> parts,
  TextStyle baseStyle,
  DefaultTextScale scale, {
  required bool halo,
  int? maxLines,
}) {
  final align = switch (data.textJustify) {
    .left => TextAlign.left,
    .right => TextAlign.right,
    .auto || .center => TextAlign.center,
  };
  if (parts.length == 1 && !parts.single.imageSection) {
    return _pointText(
      parts.single.text,
      style: halo
          ? _haloStyle(parts.single.style, scale, data.haloColor)
          : parts.single.style,
      align: align,
      direction: data.textDirection,
      maxLines: maxLines,
    );
  }

  return Text.rich(
    TextSpan(
      style: halo ? _haloStyle(baseStyle, scale, data.haloColor) : baseStyle,
      children: [
        for (final part in parts) _textPartSpan(part, data, scale, halo),
      ],
    ),
    textAlign: align,
    textDirection: data.textDirection,
    softWrap: false,
    maxLines: maxLines,
    overflow: TextOverflow.visible,
  );
}

// Inline images are laid out in shaped units so the label's scale ratio
// returns them to their evaluated size.
InlineSpan _textPartSpan(
  _SymbolTextPart part,
  LabelData data,
  DefaultTextScale scale,
  bool halo,
) {
  final image = part.image;
  if (!part.imageSection) {
    return TextSpan(
      text: part.text,
      style: halo ? _haloStyle(part.style, scale, data.haloColor) : part.style,
    );
  }
  if (image == null) return const WidgetSpan(child: SizedBox.shrink());
  final imageScale = part.imageScale / scale.ratio;
  final size = image.displaySize * imageScale;

  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: halo
        ? image.sdf && scale.haloWidth > 0
              ? SpriteIconWidget(
                  icon: image,
                  scale: imageScale,
                  tint: const Color(0x00000000),
                  haloColor: data.haloColor,
                  haloWidth: scale.haloWidth,
                  haloBlur: scale.haloBlur,
                )
              : SizedBox.fromSize(size: size)
        : SpriteIconWidget(
            icon: image,
            scale: imageScale,
            tint: part.style.color,
          ),
  );
}

TextStyle _haloStyle(TextStyle style, DefaultTextScale scale, Color color) =>
    style.copyWith(
      foreground: _haloPaint(scale.haloWidth, scale.haloBlur, color),
    );

// Glyphs stack top to bottom, centered horizontally, with Latin glyphs
// rotated a quarter turn, as MapLibre lays out vertical text.
Widget _buildVerticalText(
  LabelData data,
  List<_SymbolTextPart> parts,
  DefaultTextScale scale,
) {
  final shaped = _shapeGlyphs(parts, data.textDirection, scale);
  var width = 0.0;
  var height = 0.0;
  for (final glyph in shaped) {
    width = math.max(width, glyph.size.width);
    height += glyph.size.height;
  }
  final glyphs = <SymbolGlyph>[];
  var top = 0.0;
  for (final glyph in shaped) {
    final rotates = glyph.image == null && _rotateVerticalGlyph(glyph.text);
    glyphs.add(
      SymbolGlyph(
        text: glyph.text,
        style: glyph.style,
        image: glyph.image,
        imageScale: glyph.imageScale,
        size: glyph.size,
        center: Offset(width / 2, top + glyph.size.height / 2),
        transform: rotates
            ? Matrix4.rotationZ(math.pi / 2)
            : Matrix4.identity(),
      ),
    );
    top += glyph.size.height;
  }

  return SymbolGlyphRun(
    glyphs: glyphs,
    desiredSize: Size(math.max(1, width), math.max(1, height)),
    direction: data.textDirection,
    haloColor: data.haloColor,
    haloWidth: scale.haloWidth,
    haloBlur: scale.haloBlur,
  );
}

bool _rotateVerticalGlyph(String grapheme) {
  final rune = grapheme.runes.firstOrNull;
  if (rune == null) return false;

  return rune > 0x20 && rune < 0x2e80;
}

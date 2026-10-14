part of 'default_symbol_builders.dart';

/// Builds the default style-derived text for a placed symbol.
///
/// Returns null when no non-empty text label was placed. Text shapes at a
/// grid-snapped size and scales to the evaluated size, so a zoom reuses the
/// shaped text, at the cost of scaling by up to about 1.6% at rest. The
/// overlay's own default labels additionally re-shape exactly once a zoom
/// settles.
Widget? buildDefaultSymbolText(BuildContext context, MapSymbol symbol) {
  final scale = DefaultTextScale.of(symbol.data, symbol.key);
  final content = buildDefaultSymbolTextContent(context, symbol, scale);
  if (content == null) return null;

  return placeDefaultSymbolText(content, symbol.data, scale);
}

/// How built label content is placed on screen. Internal.
@internal
enum DefaultTextPlacement {
  /// The content applies its own transform.
  self,

  /// A point transform applies around the content center.
  point,

  /// A line rotation and pitch scale apply around the content center.
  line,
}

/// Label content whose placement changes without rebuilding it. Internal.
@internal
class const DefaultSymbolTextContent({
  required final Widget widget,
  required final DefaultTextPlacement placement,
});

/// Builds the label content of [symbol] shaped by [scale].
///
/// Returns null when no non-empty text label was placed. The content carries
/// the label's semantics and opacity but not its transform or translation,
/// which [placeDefaultSymbolText] applies. Internal.
@internal
DefaultSymbolTextContent? buildDefaultSymbolTextContent(
  BuildContext context,
  MapSymbol symbol,
  DefaultTextScale scale,
) {
  final data = symbol.data;
  if (!data.textPlaced || data.text.isEmpty) return null;
  if (data.textOpacity <= 0) {
    return const DefaultSymbolTextContent(
      widget: SizedBox.shrink(),
      placement: .self,
    );
  }
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
  var placement = DefaultTextPlacement.point;
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
    placement = .self;
  } else if (data.vertical) {
    final parts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.text,
      sections: data.textSections,
    );
    text = _buildVerticalText(data, parts, scale);
  } else {
    final parts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.text,
      sections: data.textSections,
    );
    text = _buildPointText(
      data,
      parts,
      fillStyle,
      scale,
      pixelAligned: scale.pixelAligns(data),
    );
    if (data.alongLine) placement = .line;
  }
  final opacity = data.textOpacity.clamp(0.0, 1.0);
  if (opacity < 1) text = Opacity(opacity: opacity, child: text);

  // Assistive technology reads each label once. The glyph, halo, and inline
  // image widgets underneath would otherwise each announce a fragment.
  return DefaultSymbolTextContent(
    widget: Semantics(
      container: true,
      excludeSemantics: true,
      label: _symbolSemanticsLabel(data),
      textDirection: data.textDirection,
      child: text,
    ),
    placement: placement,
  );
}

/// Places [content] with the symbol's transform and translation. Internal.
@internal
Widget placeDefaultSymbolText(
  DefaultSymbolTextContent content,
  LabelData data,
  DefaultTextScale scale,
) {
  final placed = switch (content.placement) {
    .self => content.widget,
    .point => _applyPointSymbolTransform(
      content.widget,
      data.textTransform,
      ratio: scale.ratio,
      stable: true,
    ),
    .line => _applyLineSymbolTransform(
      content.widget,
      data.textTransform,
      _pathAngle(data.textPath, data.angle, keepUpright: data.textKeepUpright) +
          data.textRotation,
      scale.ratio,
    ),
  };

  return _applySymbolTranslation(
    placed,
    data.textTranslateX,
    data.textTranslateY,
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

TextAlign _textAlign(LabelTextJustify justify) => switch (justify) {
  .left => .left,
  .right => .right,
  .auto || .center => .center,
};

// Text-only labels paint as one text block. Labels with inline images keep a
// widget tree, because the images are widgets.
Widget _buildPointText(
  LabelData data,
  List<_SymbolTextPart> parts,
  TextStyle baseStyle,
  DefaultTextScale scale, {
  required bool pixelAligned,
}) {
  final fontSize = scale.fontSize;
  final boxWidth = scale.boxWidth;
  final width = boxWidth > 0
      ? boxWidth
      : (data.maxWidth > 0 ? data.maxWidth * fontSize : fontSize * 8);
  final align = _textAlign(data.textJustify);
  final maxLines = data.alongLine ? 1 : null;
  if (parts.any((part) => part.imageSection)) {
    Widget label(bool halo) => _formattedText(
      data,
      parts,
      baseStyle,
      scale,
      align: align,
      halo: halo,
      maxLines: maxLines,
    );
    final visual = scale.haloWidth > 0
        ? Stack(
            alignment: Alignment.center,
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [label(true), label(false)],
          )
        : label(false);

    return SizedBox(width: width, child: visual);
  }
  var maxFontSize = fontSize;
  for (final part in parts) {
    maxFontSize = math.max(maxFontSize, part.style.fontSize ?? fontSize);
  }

  return _textBlock(
    span: parts.length == 1
        ? TextSpan(text: parts.single.text, style: parts.single.style)
        : TextSpan(
            style: baseStyle,
            children: [
              for (final part in parts)
                TextSpan(text: part.text, style: part.style),
            ],
          ),
    align: align,
    width: width,
    maxLines: maxLines,
    direction: data.textDirection,
    haloColor: data.haloColor,
    haloWidth: scale.haloWidth,
    haloBlur: scale.haloBlur,
    inkMargin: maxFontSize * 0.2,
    pixelAligned: pixelAligned,
  );
}

Widget _formattedText(
  LabelData data,
  List<_SymbolTextPart> parts,
  TextStyle baseStyle,
  DefaultTextScale scale, {
  required TextAlign align,
  required bool halo,
  int? maxLines,
}) => Text.rich(
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
  final glyphs = <SymbolGlyph>[];
  for (final part in parts) {
    if (part.imageSection) {
      final image = part.image;
      if (image == null) continue;
      final imageScale = part.imageScale / scale.ratio;
      glyphs.add(
        SymbolGlyph(
          text: '',
          style: part.style,
          image: image,
          imageScale: imageScale,
          size: image.displaySize * imageScale,
          center: Offset.zero,
        ),
      );
      continue;
    }
    for (final grapheme in part.text.characters) {
      if (grapheme == '\n' || grapheme == '\r') continue;
      glyphs.add(
        SymbolGlyph(
          text: grapheme,
          style: part.style.copyWith(height: 1),
          size: Size.zero,
          center: Offset.zero,
          angle: _rotateVerticalGlyph(grapheme) ? math.pi / 2 : 0,
        ),
      );
    }
  }

  return SymbolGlyphRun(
    glyphs: glyphs,
    desiredSize: Size.zero,
    vertical: true,
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

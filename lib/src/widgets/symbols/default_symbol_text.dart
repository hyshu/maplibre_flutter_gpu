part of 'default_symbol_builders.dart';

/// Builds the default style-derived text for a placed symbol.
///
/// Returns null when no non-empty text label was placed.
Widget? buildDefaultSymbolText(BuildContext context, MapSymbol symbol) {
  final data = symbol.data;
  if (!data.textPlaced || data.text.isEmpty) return null;
  if (data.textOpacity <= 0) return const SizedBox.shrink();
  final fontSize = data.fontSize;
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
    text = _buildPathText(data, visualParts);
  } else if (data.vertical) {
    final parts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.text,
      sections: data.textSections,
    );
    text = _buildVerticalText(data, parts);
    text = _applyPointSymbolTransform(text, data.textTransform);
  } else {
    final parts = _symbolTextParts(
      symbol,
      fillStyle,
      fonts,
      text: data.text,
      sections: data.textSections,
    );
    text = _buildPointText(data, parts, fillStyle);
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
          )
        : _applyPointSymbolTransform(text, data.textTransform);
  }
  final opacity = data.textOpacity.clamp(0.0, 1.0);
  if (opacity < 1) text = Opacity(opacity: opacity, child: text);

  return _applySymbolTranslation(
    text,
    data.textTranslateX,
    data.textTranslateY,
  );
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
) {
  final fontSize = data.fontSize;
  final boxWidth = data.textW;
  final maxWidth = boxWidth > 0
      ? boxWidth
      : (data.maxWidth > 0 ? data.maxWidth * fontSize : fontSize * 8);
  Widget label(bool halo) => _formattedText(
    data,
    parts,
    baseStyle,
    halo: halo,
    maxLines: data.alongLine ? 1 : null,
  );
  final visual = data.haloWidth > 0
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
  TextStyle baseStyle, {
  required bool halo,
  int? maxLines,
}) {
  final align = switch (data.textJustify) {
    .left => TextAlign.left,
    .right => TextAlign.right,
    .auto || .center => TextAlign.center,
  };
  if (parts.length == 1 && !parts.single.imageSection) {
    return Text(
      parts.single.text,
      style: halo ? _haloStyle(parts.single.style, data) : parts.single.style,
      textAlign: align,
      textDirection: data.textDirection,
      softWrap: false,
      maxLines: maxLines,
      overflow: TextOverflow.visible,
    );
  }

  return Text.rich(
    TextSpan(
      style: halo ? _haloStyle(baseStyle, data) : baseStyle,
      children: [for (final part in parts) _textPartSpan(part, data, halo)],
    ),
    textAlign: align,
    textDirection: data.textDirection,
    softWrap: false,
    maxLines: maxLines,
    overflow: TextOverflow.visible,
  );
}

InlineSpan _textPartSpan(_SymbolTextPart part, LabelData data, bool halo) {
  final image = part.image;
  if (!part.imageSection) {
    return TextSpan(
      text: part.text,
      style: halo ? _haloStyle(part.style, data) : part.style,
    );
  }
  if (image == null) return const WidgetSpan(child: SizedBox.shrink());
  final size = image.displaySize * part.imageScale;

  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: halo
        ? image.sdf && data.haloWidth > 0
              ? SpriteIconWidget(
                  icon: image,
                  scale: part.imageScale,
                  tint: const Color(0x00000000),
                  haloColor: data.haloColor,
                  haloWidth: data.haloWidth,
                  haloBlur: data.haloBlur,
                )
              : SizedBox.fromSize(size: size)
        : SpriteIconWidget(
            icon: image,
            scale: part.imageScale,
            tint: part.style.color,
          ),
  );
}

TextStyle _haloStyle(TextStyle style, LabelData data) => style.copyWith(
  foreground: Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = data.haloWidth * 2
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = data.haloBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, data.haloBlur)
        : null
    ..color = data.haloColor,
);

Widget _buildVerticalText(LabelData data, List<_SymbolTextPart> parts) {
  final children = <Widget>[];
  for (final part in parts) {
    if (part.imageSection) {
      final image = part.image;
      if (image == null) continue;
      children.add(
        SpriteIconWidget(
          icon: image,
          scale: part.imageScale,
          tint: part.style.color,
          haloColor: image.sdf ? data.haloColor : null,
          haloWidth: image.sdf ? data.haloWidth : 0,
          haloBlur: image.sdf ? data.haloBlur : 0,
        ),
      );
      continue;
    }
    for (final grapheme in part.text.characters) {
      if (grapheme == '\n' || grapheme == '\r') continue;
      Widget glyph = _glyphText(grapheme, part.style, data);
      if (_rotateVerticalGlyph(grapheme)) {
        glyph = Transform.rotate(angle: math.pi / 2, child: glyph);
      }
      children.add(glyph);
    }
  }

  return Column(mainAxisSize: MainAxisSize.min, children: children);
}

bool _rotateVerticalGlyph(String grapheme) {
  final rune = grapheme.runes.firstOrNull;
  if (rune == null) return false;

  return rune > 0x20 && rune < 0x2e80;
}

Widget _glyphText(String text, TextStyle style, LabelData data) {
  final fill = Text(
    text,
    style: style.copyWith(height: 1),
    textDirection: data.textDirection,
  );
  if (data.haloWidth <= 0) return fill;

  return Stack(
    alignment: Alignment.center,
    clipBehavior: Clip.none,
    children: [
      Text(
        text,
        style: _haloStyle(style.copyWith(height: 1), data),
        textDirection: data.textDirection,
      ),
      fill,
    ],
  );
}

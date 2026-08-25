import 'dart:ui' show Color, TextDirection;

/// Resolved horizontal alignment of shaped text.
enum LabelTextJustify { auto, center, left, right }

/// One formatted range using UTF-16 offsets into [LabelData.text].
class LabelTextSection {
  const LabelTextSection({
    required this.start,
    required this.end,
    this.fontScale = 1,
    this.fonts = const <String>[],
    this.color,
    this.imageId,
  });

  final int start;
  final int end;
  final double fontScale;
  final List<String> fonts;
  final Color? color;
  final String? imageId;
}

/// Screen-space point relative to a symbol widget's center.
class LabelPathPoint {
  const LabelPathPoint(this.x, this.y);

  final double x;
  final double y;
}

/// Screen-space affine basis for local widget coordinates.
class LabelAffineTransform {
  const LabelAffineTransform({
    this.xx = 1,
    this.xy = 0,
    this.yx = 0,
    this.yy = 1,
  });

  final double xx;
  final double xy;
  final double yx;
  final double yy;
}

/// A symbol placed by MapLibre with its anchors, evaluated paint properties,
/// and collision bounds.
class LabelData {
  /// Stable MapLibre CrossTileSymbolIndex identity.
  ///
  /// Zero and `0xffffffff` mean that the symbol has no stable identity.
  final int crossTileId;

  /// Horizontal world copy containing this placement.
  final int tileWrap;

  /// Latitude of the text anchor in degrees.
  final double lat;

  /// Longitude of the text anchor in degrees.
  final double lon;

  /// Latitude of the independently placed icon anchor in degrees.
  final double iconLat;

  /// Longitude of the independently placed icon anchor in degrees.
  final double iconLon;

  /// Evaluated text size in logical pixels.
  final double fontSize;

  /// Premultiplied red channel of the evaluated text color.
  final double textR;

  /// Premultiplied green channel of the evaluated text color.
  final double textG;

  /// Premultiplied blue channel of the evaluated text color.
  final double textB;

  /// Alpha channel of the evaluated text color.
  final double textA;

  /// Premultiplied red channel of the evaluated text halo color.
  final double haloR;

  /// Premultiplied green channel of the evaluated text halo color.
  final double haloG;

  /// Premultiplied blue channel of the evaluated text halo color.
  final double haloB;

  /// Alpha channel of the evaluated text halo color.
  final double haloA;

  /// Evaluated text halo width in logical pixels.
  final double haloWidth;

  /// Evaluated text opacity.
  final double textOpacity;

  /// Evaluated text halo blur radius in logical pixels.
  final double haloBlur;

  /// Evaluated text letter spacing in ems.
  final double letterSpacing;

  /// Evaluated text line height in ems.
  final double lineHeight;

  /// Evaluated text wrapping width in ems.
  final double maxWidth;

  /// First entry in the evaluated font stack.
  final String textFont;

  /// Full evaluated font stack in fallback order.
  final List<String> textFonts;

  /// Formatting ranges aligned with [text] UTF-16 offsets.
  final List<LabelTextSection> textSections;

  /// Formatting ranges aligned with [visualText] UTF-16 offsets.
  final List<LabelTextSection> visualTextSections;

  /// Projected line path relative to the text widget center.
  final List<LabelPathPoint> textPath;

  /// Projected line path relative to the icon widget center.
  final List<LabelPathPoint> iconPath;

  /// Width of the unpadded shaped text in logical pixels.
  final double textW;

  /// Height of the unpadded shaped text in logical pixels.
  final double textH;

  /// Width of the unpadded shaped icon in logical pixels.
  final double iconW;

  /// Height of the unpadded shaped icon in logical pixels.
  final double iconH;

  /// Evaluated icon-size.
  final double iconScale;

  /// Evaluated icon opacity.
  final double iconOpacity;

  /// Premultiplied red channel of the evaluated SDF icon color.
  final double iconR;

  /// Premultiplied green channel of the evaluated SDF icon color.
  final double iconG;

  /// Premultiplied blue channel of the evaluated SDF icon color.
  final double iconB;

  /// Alpha channel of the evaluated SDF icon color.
  final double iconA;

  /// Premultiplied channels of the evaluated SDF icon halo color.
  final double iconHaloR;
  final double iconHaloG;
  final double iconHaloB;
  final double iconHaloA;

  /// Evaluated SDF icon halo width and blur in logical pixels.
  final double iconHaloWidth;
  final double iconHaloBlur;

  /// Requested `icon-text-fit` dimensions before sprite constraints.
  ///
  /// Both values are zero when `icon-text-fit` is disabled.
  final double iconFitWidth;
  final double iconFitHeight;

  /// Horizontal offset from the text anchor to its center in logical pixels.
  final double textOffsetX;

  /// Vertical offset from the text anchor to its center in logical pixels.
  final double textOffsetY;

  /// Horizontal offset from the icon anchor to its center in logical pixels.
  final double iconOffsetX;

  /// Vertical offset from the icon anchor to its center in logical pixels.
  final double iconOffsetY;

  /// Whether MapLibre placed the text.
  final bool textPlaced;

  /// Whether MapLibre placed the icon.
  final bool iconPlaced;

  /// Whether the label follows a line such as a street.
  final bool alongLine;

  /// Whether the icon follows a line.
  final bool iconAlongLine;

  /// Label angle in radians for line placement.
  final double angle;

  /// Mean icon path angle in radians.
  final double iconAngle;

  /// Feature-evaluated style rotations in radians.
  final double textRotation;
  final double iconRotation;

  /// Paint translations resolved to screen logical pixels.
  final double textTranslateX;
  final double textTranslateY;
  final double iconTranslateX;
  final double iconTranslateY;

  /// Final point-symbol transforms. Style rotation is already included.
  final LabelAffineTransform textTransform;
  final LabelAffineTransform iconTransform;

  /// Resolved text justification.
  final LabelTextJustify textJustify;

  /// Whether native selected vertical writing.
  final bool vertical;

  /// Whether the sprite uses signed-distance-field rendering.
  final bool iconSdf;

  /// Resolved native alignment modes.
  final bool textPitchWithMap;
  final bool textRotationWithMap;
  final bool iconPitchWithMap;
  final bool iconRotationWithMap;

  /// Whether line symbols must remain upright while following their path.
  final bool textKeepUpright;
  final bool iconKeepUpright;

  /// Evaluated text displayed by the symbol.
  final String text;

  /// BiDi visual-order text used for manual line-path glyph placement.
  final String visualText;

  /// Resolved paragraph direction for Flutter text layout.
  final TextDirection textDirection;

  /// ID of the style layer that produced the symbol.
  final String layer;

  /// Position of [layer] in the style layer stack.
  final int layerIndex;

  /// Native paint group within [layer].
  ///
  /// Icons paint before text inside a group. Groups paint in ascending order.
  final int renderGroup;

  /// Back-to-front symbol order within [renderGroup].
  final int renderOrder;

  /// Evaluated icon-image ID, or an empty string when there is no icon.
  final String icon;

  /// Creates data for a symbol placed by MapLibre.
  const LabelData({
    this.crossTileId = 0,
    this.tileWrap = 0,
    required this.lat,
    required this.lon,
    this.iconLat = 0,
    this.iconLon = 0,
    required this.fontSize,
    required this.textR,
    required this.textG,
    required this.textB,
    required this.textA,
    required this.haloR,
    required this.haloG,
    required this.haloB,
    required this.haloA,
    required this.haloWidth,
    this.textOpacity = 1,
    this.haloBlur = 0,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.maxWidth = 10,
    this.textFont = '',
    this.textFonts = const <String>[],
    this.textSections = const <LabelTextSection>[],
    this.visualTextSections = const <LabelTextSection>[],
    this.textPath = const <LabelPathPoint>[],
    this.iconPath = const <LabelPathPoint>[],
    this.textW = 0,
    this.textH = 0,
    this.iconW = 0,
    this.iconH = 0,
    this.iconScale = 1,
    this.iconOpacity = 1,
    this.iconR = 0,
    this.iconG = 0,
    this.iconB = 0,
    this.iconA = 1,
    this.iconHaloR = 0,
    this.iconHaloG = 0,
    this.iconHaloB = 0,
    this.iconHaloA = 0,
    this.iconHaloWidth = 0,
    this.iconHaloBlur = 0,
    this.iconFitWidth = 0,
    this.iconFitHeight = 0,
    this.textOffsetX = 0,
    this.textOffsetY = 0,
    this.iconOffsetX = 0,
    this.iconOffsetY = 0,
    this.textPlaced = true,
    this.iconPlaced = false,
    this.alongLine = false,
    this.iconAlongLine = false,
    this.angle = 0,
    this.iconAngle = 0,
    this.textRotation = 0,
    this.iconRotation = 0,
    this.textTranslateX = 0,
    this.textTranslateY = 0,
    this.iconTranslateX = 0,
    this.iconTranslateY = 0,
    this.textTransform = const LabelAffineTransform(),
    this.iconTransform = const LabelAffineTransform(),
    this.textJustify = LabelTextJustify.center,
    this.vertical = false,
    this.iconSdf = false,
    this.textPitchWithMap = false,
    this.textRotationWithMap = false,
    this.iconPitchWithMap = false,
    this.iconRotationWithMap = false,
    this.textKeepUpright = true,
    this.iconKeepUpright = false,
    required this.text,
    String? visualText,
    this.textDirection = TextDirection.ltr,
    required this.layer,
    this.layerIndex = 0x7fffffff,
    this.renderGroup = 0,
    this.renderOrder = 0,
    this.icon = '',
  }) : visualText = visualText ?? text;

  /// Converts premultiplied color channels to a Flutter [Color].
  static Color _pmColor(double r, double g, double b, double a) {
    final ai = (a * 255).round().clamp(0, 255);
    if (ai == 0) return const Color(0x00000000);
    final ri = (r / a * 255).round().clamp(0, 255);
    final gi = (g / a * 255).round().clamp(0, 255);
    final bi = (b / a * 255).round().clamp(0, 255);

    return Color.fromARGB(ai, ri, gi, bi);
  }

  /// Evaluated text color converted to straight alpha.
  Color get textColor => _pmColor(textR, textG, textB, textA);

  /// Evaluated text halo color converted to straight alpha.
  Color get haloColor => _pmColor(haloR, haloG, haloB, haloA);

  /// Evaluated SDF icon color converted to straight alpha.
  Color get iconColor => _pmColor(iconR, iconG, iconB, iconA);

  /// Evaluated SDF icon halo color converted to straight alpha.
  Color get iconHaloColor =>
      _pmColor(iconHaloR, iconHaloG, iconHaloB, iconHaloA);
}

import 'dart:ui' show Color, TextDirection;

/// Resolved horizontal alignment of shaped text.
enum LabelTextJustify { auto, center, left, right }

/// One formatted range using UTF-16 offsets into [LabelData.text].
class const LabelTextSection({
  required final int start,
  required final int end,
  final double fontScale = 1,
  final List<String> fonts = const [],
  final Color? color,
  final String? imageId,
});

/// Screen-space point relative to a symbol widget's center.
class const LabelPathPoint(final double x, final double y);

/// Screen-space affine basis for local widget coordinates.
class const LabelAffineTransform({
  final double xx = 1,
  final double xy = 0,
  final double yx = 0,
  final double yy = 1,
});

/// A symbol placed by MapLibre with its anchors, evaluated paint properties,
/// and collision bounds.
class const LabelData({
  /// Stable MapLibre CrossTileSymbolIndex identity.
  ///
  /// Zero and `0xffffffff` mean that the symbol has no stable identity.
  final int crossTileId = 0,

  /// Horizontal world copy containing this placement.
  final int tileWrap = 0,

  /// Latitude of the text anchor in degrees.
  required final double lat,

  /// Longitude of the text anchor in degrees.
  required final double lon,

  /// Latitude of the independently placed icon anchor in degrees.
  final double iconLat = 0,

  /// Longitude of the independently placed icon anchor in degrees.
  final double iconLon = 0,

  /// Evaluated text size in logical pixels.
  required final double fontSize,

  /// Premultiplied red channel of the evaluated text color.
  required final double textR,

  /// Premultiplied green channel of the evaluated text color.
  required final double textG,

  /// Premultiplied blue channel of the evaluated text color.
  required final double textB,

  /// Alpha channel of the evaluated text color.
  required final double textA,

  /// Premultiplied red channel of the evaluated text halo color.
  required final double haloR,

  /// Premultiplied green channel of the evaluated text halo color.
  required final double haloG,

  /// Premultiplied blue channel of the evaluated text halo color.
  required final double haloB,

  /// Alpha channel of the evaluated text halo color.
  required final double haloA,

  /// Evaluated text halo width in logical pixels.
  required final double haloWidth,

  /// Evaluated text opacity.
  final double textOpacity = 1,

  /// Evaluated text halo blur radius in logical pixels.
  final double haloBlur = 0,

  /// Evaluated text letter spacing in ems.
  final double letterSpacing = 0,

  /// Evaluated text line height in ems.
  final double lineHeight = 1.2,

  /// Evaluated text wrapping width in ems.
  final double maxWidth = 10,

  /// First entry in the evaluated font stack.
  final String textFont = '',

  /// Full evaluated font stack in fallback order.
  final List<String> textFonts = const [],

  /// Formatting ranges aligned with [text] UTF-16 offsets.
  final List<LabelTextSection> textSections = const [],

  /// Formatting ranges aligned with [visualText] UTF-16 offsets.
  final List<LabelTextSection> visualTextSections = const [],

  /// Projected line path relative to the text widget center.
  final List<LabelPathPoint> textPath = const [],

  /// Projected line path relative to the icon widget center.
  final List<LabelPathPoint> iconPath = const [],

  /// Width of the unpadded shaped text in logical pixels.
  final double textW = 0,

  /// Height of the unpadded shaped text in logical pixels.
  final double textH = 0,

  /// Width of the unpadded shaped icon in logical pixels.
  final double iconW = 0,

  /// Height of the unpadded shaped icon in logical pixels.
  final double iconH = 0,

  /// Evaluated icon-size.
  final double iconScale = 1,

  /// Evaluated icon opacity.
  final double iconOpacity = 1,

  /// Premultiplied red channel of the evaluated SDF icon color.
  final double iconR = 0,

  /// Premultiplied green channel of the evaluated SDF icon color.
  final double iconG = 0,

  /// Premultiplied blue channel of the evaluated SDF icon color.
  final double iconB = 0,

  /// Alpha channel of the evaluated SDF icon color.
  final double iconA = 1,

  /// Premultiplied red channel of the evaluated SDF icon halo color.
  final double iconHaloR = 0,

  /// Premultiplied green channel of the evaluated SDF icon halo color.
  final double iconHaloG = 0,

  /// Premultiplied blue channel of the evaluated SDF icon halo color.
  final double iconHaloB = 0,

  /// Alpha channel of the evaluated SDF icon halo color.
  final double iconHaloA = 0,

  /// Evaluated SDF icon halo width in logical pixels.
  final double iconHaloWidth = 0,

  /// Evaluated SDF icon halo blur in logical pixels.
  final double iconHaloBlur = 0,

  /// Requested `icon-text-fit` width before sprite constraints.
  ///
  /// Zero when `icon-text-fit` is disabled.
  final double iconFitWidth = 0,

  /// Requested `icon-text-fit` height before sprite constraints.
  ///
  /// Zero when `icon-text-fit` is disabled.
  final double iconFitHeight = 0,

  /// Horizontal offset from the text anchor to its center in logical pixels.
  final double textOffsetX = 0,

  /// Vertical offset from the text anchor to its center in logical pixels.
  final double textOffsetY = 0,

  /// Horizontal offset from the icon anchor to its center in logical pixels.
  final double iconOffsetX = 0,

  /// Vertical offset from the icon anchor to its center in logical pixels.
  final double iconOffsetY = 0,

  /// Whether MapLibre placed the text.
  final bool textPlaced = true,

  /// Whether MapLibre placed the icon.
  final bool iconPlaced = false,

  /// Whether the label follows a line such as a street.
  final bool alongLine = false,

  /// Whether the icon follows a line.
  final bool iconAlongLine = false,

  /// Label angle in radians for line placement.
  final double angle = 0,

  /// Mean icon path angle in radians.
  final double iconAngle = 0,

  /// Feature-evaluated text rotation in radians.
  final double textRotation = 0,

  /// Feature-evaluated icon rotation in radians.
  final double iconRotation = 0,

  /// Text paint translation resolved to screen logical pixels.
  final double textTranslateX = 0,
  final double textTranslateY = 0,

  /// Icon paint translation resolved to screen logical pixels.
  final double iconTranslateX = 0,
  final double iconTranslateY = 0,

  /// Final point-symbol text transform. Style rotation is already included.
  final LabelAffineTransform textTransform = const .new(),

  /// Final point-symbol icon transform. Style rotation is already included.
  final LabelAffineTransform iconTransform = const .new(),

  /// Resolved text justification.
  final LabelTextJustify textJustify = .center,

  /// Whether native selected vertical writing.
  final bool vertical = false,

  /// Whether the sprite uses signed-distance-field rendering.
  final bool iconSdf = false,

  /// Whether text pitch is aligned with the map.
  final bool textPitchWithMap = false,

  /// Whether text rotation is aligned with the map.
  final bool textRotationWithMap = false,

  /// Whether icon pitch is aligned with the map.
  final bool iconPitchWithMap = false,

  /// Whether icon rotation is aligned with the map.
  final bool iconRotationWithMap = false,

  /// Whether line text must remain upright while following its path.
  final bool textKeepUpright = true,

  /// Whether line icons must remain upright while following their path.
  final bool iconKeepUpright = false,

  /// Evaluated text displayed by the symbol.
  required final String text,

  String? visualText,

  /// Resolved paragraph direction for Flutter text layout.
  final TextDirection textDirection = .ltr,

  /// ID of the style layer that produced the symbol.
  required final String layer,

  /// Position of [layer] in the style layer stack.
  final int layerIndex = 0x7fff_ffff,

  /// Native paint group within [layer].
  ///
  /// Icons paint before text inside a group. Groups paint in ascending order.
  final int renderGroup = 0,

  /// Back-to-front symbol order within [renderGroup].
  final int renderOrder = 0,

  /// Evaluated icon-image ID, or an empty string when there is no icon.
  final String icon = '',
}) {
  this : visualText = visualText ?? text;

  /// BiDi visual-order text used for manual line-path glyph placement.
  final String visualText;

  /// Converts premultiplied color channels to a Flutter [Color].
  static Color _pmColor(double r, double g, double b, double a) {
    final ai = (a * 255).round().clamp(0, 255);
    if (ai == 0) return const .new(0x00000000);
    final ri = (r / a * 255).round().clamp(0, 255);
    final gi = (g / a * 255).round().clamp(0, 255);
    final bi = (b / a * 255).round().clamp(0, 255);

    return .fromARGB(ai, ri, gi, bi);
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

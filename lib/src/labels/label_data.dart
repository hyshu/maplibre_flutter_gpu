import 'dart:ui' show Color;

/// A symbol placed by MapLibre with its anchors, evaluated paint properties,
/// and collision bounds.
class LabelData {
  /// Stable MapLibre CrossTileSymbolIndex identity.
  ///
  /// Zero and `0xffffffff` mean that the symbol has no stable identity.
  final int crossTileId;

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

  /// Width of the text collision box in logical pixels.
  final double textW;

  /// Height of the text collision box in logical pixels.
  final double textH;

  /// Width of the icon collision box in logical pixels.
  final double iconW;

  /// Height of the icon collision box in logical pixels.
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

  /// Label angle in radians for line placement.
  final double angle;

  /// Evaluated text displayed by the symbol.
  final String text;

  /// ID of the style layer that produced the symbol.
  final String layer;

  /// Evaluated icon-image ID, or an empty string when there is no icon.
  final String icon;

  /// Creates data for a symbol placed by MapLibre.
  const LabelData({
    this.crossTileId = 0,
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
    this.textOffsetX = 0,
    this.textOffsetY = 0,
    this.iconOffsetX = 0,
    this.iconOffsetY = 0,
    this.textPlaced = true,
    this.iconPlaced = false,
    this.alongLine = false,
    this.angle = 0,
    required this.text,
    required this.layer,
    this.icon = '',
  });

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
}

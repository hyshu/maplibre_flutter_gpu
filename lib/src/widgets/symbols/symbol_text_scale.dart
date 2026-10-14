part of 'default_symbol_builders.dart';

/// Shaping values for one default label.
///
/// Text shapes at [fontSize], the evaluated size snapped to a grid, and the
/// built widget scales by [ratio] to the evaluated size. A zoom-interpolated
/// text size therefore reuses its shaped text until it crosses a grid line
/// instead of re-shaping on every frame. [haloWidth], [haloBlur], and
/// [boxWidth] are expressed in shaped units and quantized so unchanged styles
/// keep equal values while the ratio drifts.
///
/// This class is internal and is not exported by the package barrel.
@internal
class const DefaultTextScale({
  required final double fontSize,
  required final double ratio,
  required final double haloWidth,
  required final double haloBlur,

  /// The native collision width in shaped units, or zero when none applies.
  required final double boxWidth,
}) {
  /// Computes the shaping values of [data] for the symbol identified by [key].
  factory of(LabelData data, String key) {
    final evaluated = data.fontSize;
    final fontSize = snapFontSize(evaluated, key);
    final ratio = fontSize > 0 && evaluated.isFinite
        ? evaluated / fontSize
        : 1.0;

    return .new(
      fontSize: fontSize,
      ratio: ratio,
      haloWidth: _quantize(data.haloWidth / ratio, 8),
      haloBlur: _quantize(data.haloBlur / ratio, 8),
      boxWidth: data.textW > 0 ? _quantize(data.textW / ratio, 64) : 0,
    );
  }

  /// Whether [other] shapes the same text, ignoring the scale ratio.
  bool shapesLike(DefaultTextScale other) =>
      fontSize == other.fontSize &&
      haloWidth == other.haloWidth &&
      haloBlur == other.haloBlur &&
      boxWidth == other.boxWidth;

  static double _quantize(double value, int divisions) =>
      value.isFinite ? (value * divisions).roundToDouble() / divisions : value;

  /// Snaps [size] to the shaping grid of the symbol identified by [key].
  ///
  /// Grid lines are a power of two apart, so every integer size and every
  /// size on a grid line shapes exactly. The spacing halves with each octave
  /// below 32 pixels, keeping the ratio to the evaluated size within about
  /// 1.6% of one. A size between grid lines snaps to one of four grids
  /// shifted by a quarter step, chosen per symbol, so the labels of one
  /// layer cross grid lines in different frames rather than all at once.
  /// Four grids bound the number of distinct shaped sizes, and therefore the
  /// glyph rasters the engine keeps, per evaluated size.
  @visibleForTesting
  static double snapFontSize(double size, String key) {
    if (!size.isFinite || size <= 0) return size;
    final step = _gridStep(size);
    final steps = size / step;
    final rounded = steps.roundToDouble();
    if ((steps - rounded).abs() < 1e-3) return rounded * step;
    final phase = (key.hashCode & 3) / 4;

    return ((steps - phase).roundToDouble() + phase) * step;
  }

  static double _gridStep(double size) {
    var step = 1.0;
    var bound = 32.0;
    while (size < bound && step > 1 / 64) {
      step /= 2;
      bound /= 2;
    }
    while (size >= bound * 2 && step < 8) {
      step *= 2;
      bound *= 2;
    }

    return step;
  }
}

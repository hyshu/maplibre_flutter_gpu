part of 'default_symbol_builders.dart';

/// Limits how many default labels re-shape in one overlay build.
///
/// A label denied by the budget keeps its previous shaped size and scales to
/// the evaluated size instead, so the deferred shaping spreads over later
/// builds and one camera frame never re-shapes every label. Internal.
@internal
class DefaultTextReshapeBudget {
  DefaultTextReshapeBudget(this._remaining);

  int _remaining;

  /// Number of labels that kept a stale shaped size in this build.
  var deferred = 0;

  /// Claims one re-shape, or returns false once the budget is spent.
  bool take() {
    if (_remaining <= 0) {
      deferred++;

      return false;
    }
    _remaining--;

    return true;
  }
}

/// Shaping values for one default label.
///
/// Text shapes at [fontSize] and the built widget scales by [ratio] to the
/// evaluated size. While a zoom changes the evaluated size, [fontSize] stays
/// on a grid so a label reuses its shaped text until the size crosses a grid
/// line instead of re-shaping on every frame. [haloWidth], [haloBlur], and
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
  ///
  /// With [exact], text shapes at its evaluated size. Otherwise the size
  /// snaps to the shaping grid, except that [previous], the values the symbol
  /// shaped with before, keeps its size while the evaluated size stays within
  /// the grid tolerance of it. A label at rest therefore shapes exactly and
  /// keeps that text when a zoom begins. A size change that [budget] denies
  /// also keeps the previous size.
  factory of(
    LabelData data,
    String key, {
    DefaultTextScale? previous,
    bool exact = false,
    DefaultTextReshapeBudget? budget,
  }) {
    final evaluated = data.fontSize;
    var fontSize = exact
        ? evaluated
        : _keptFontSize(evaluated, previous, key) ??
              snapFontSize(evaluated, key);
    if (previous != null &&
        fontSize != previous.fontSize &&
        budget != null &&
        !budget.take()) {
      fontSize = previous.fontSize;
    }
    final ratio = fontSize > 0 && evaluated.isFinite
        ? evaluated / fontSize
        : 1.0;

    // Halo values are quantized coarsely so a label that keeps its shaped
    // size through a deferred re-shape does not rebuild for its halo.
    return .new(
      fontSize: fontSize,
      ratio: ratio,
      haloWidth: _quantize(data.haloWidth / ratio, 4),
      haloBlur: _quantize(data.haloBlur / ratio, 4),
      boxWidth: data.textW > 0 ? _quantize(data.textW / ratio, 64) : 0,
    );
  }

  /// Whether [other] shapes the same text, ignoring the scale ratio.
  bool shapesLike(DefaultTextScale other) =>
      fontSize == other.fontSize &&
      haloWidth == other.haloWidth &&
      haloBlur == other.haloBlur &&
      boxWidth == other.boxWidth;

  /// Whether the point text of [data] shaped with these values paints
  /// unscaled and unrotated, so its raster can land on whole device pixels.
  bool pixelAligns(LabelData data) =>
      ratio == 1 && !data.alongLine && _isIdentityTransform(data.textTransform);

  static double _quantize(double value, int divisions) =>
      value.isFinite ? (value * divisions).roundToDouble() / divisions : value;

  /// The size of [previous] when [size] lies within its tolerance, else null.
  static double? _keptFontSize(
    double size,
    DefaultTextScale? previous,
    String key,
  ) {
    final kept = previous?.fontSize;
    if (kept == null || kept <= 0 || !size.isFinite || size <= 0) return null;
    // The tolerance is at most half a grid step, the distance a snapped size
    // may lie from the evaluated one, and varies per symbol so the labels of
    // one layer leave their resting size in different frames.
    final tolerance =
        _gridStep(size) / size * (0.25 + ((key.hashCode >> 2) & 3) / 12);

    return (size / kept - 1).abs() <= tolerance ? kept : null;
  }

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

import 'package:flutter/foundation.dart';

/// Selects how tile level of detail falls off away from the camera.
enum TileLodMode {
  /// The finest tiles stay at the screen center and detail falls off with the
  /// distance from the center.
  standard,

  /// Detail falls off with the distance from the camera to each tile, so the
  /// tiles nearest a pitched camera stay finer than distant ones.
  distance,
}

/// Tile level-of-detail controls that reduce tile requests, uploads, and draw
/// calls in pitched views.
///
/// MapLibre applies the heuristic only while the camera pitch exceeds
/// [pitchThreshold]. The default threshold equals the default maximum tilt, so
/// detail reduction stays off until a lower threshold is configured.
@immutable
class const TileLodOptions({
  /// Radius around the view point, in tiles, that always keeps the finest
  /// zoom level. Ignored by [TileLodMode.distance].
  final double minRadius = 3,

  /// Scale factor for the distance to the view point. Values above one reduce
  /// detail closer to the view point.
  final double scale = 1,

  /// Camera pitch in degrees above which detail reduction applies. Zero
  /// applies it at every pitch.
  final double pitchThreshold = 60,

  /// Zoom level shift applied before the detail calculation. Negative values
  /// reduce detail, and minus one quarters the tile count for the same view.
  /// Ignored by [TileLodMode.distance].
  final double zoomShift = 0,

  /// The tile cover algorithm.
  final TileLodMode mode = TileLodMode.standard,
}) {
  this
    : assert(minRadius >= 0),
      assert(scale > 0),
      assert(pitchThreshold >= 0 && pitchThreshold <= 180);

  /// MapLibre's defaults, which never reduce detail within the default tilt
  /// range.
  static const defaults = TileLodOptions();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TileLodOptions &&
          other.minRadius == minRadius &&
          other.scale == scale &&
          other.pitchThreshold == pitchThreshold &&
          other.zoomShift == zoomShift &&
          other.mode == mode;

  @override
  int get hashCode =>
      Object.hash(minRadius, scale, pitchThreshold, zoomShift, mode);
}

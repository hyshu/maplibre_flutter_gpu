/// @docImport '../map_controls.dart';
library;

import 'package:flutter/material.dart';

/// A corner of the map viewport where a control can be placed.
///
/// Margins for a corner are measured inward from its horizontal and vertical
/// edges.
enum MapControlCorner {
  /// The upper-left corner.
  topLeft,

  /// The upper-right corner.
  topRight,

  /// The lower-left corner.
  bottomLeft,

  /// The lower-right corner.
  bottomRight;

  /// Whether this corner lies on the left edge.
  bool get isLeft => this == topLeft || this == bottomLeft;

  /// Whether this corner lies on the top edge.
  bool get isTop => this == topLeft || this == topRight;
}

/// A map corner used to position the compass control.
typedef CompassViewPosition = MapControlCorner;

/// A map corner used to position the attribution button.
typedef AttributionButtonPosition = MapControlCorner;

/// A map corner used to position the MapLibre logo.
typedef LogoViewPosition = MapControlCorner;

/// A map corner used to position the scale control.
typedef ScaleControlPosition = MapControlCorner;

/// Units used to format distances shown by a scale control.
enum ScaleControlUnit {
  /// Formats distances in meters or kilometers.
  metric,

  /// Formats distances in feet or miles.
  imperial,

  /// Formats distances in nautical miles.
  nautical,
}

/// Signature for building a compass control.
///
/// The `bearing` is measured in degrees clockwise from north. The `onPressed`
/// callback resets the map to north and is null when no map controller is
/// available.
typedef CompassWidgetBuilder = Widget Function(
  BuildContext context,
  double bearing,
  VoidCallback? onPressed,
);

/// Signature for building an attribution button.
///
/// The `onPressed` callback opens the configured attribution dialog when one
/// is available.
typedef AttributionButtonWidgetBuilder = Widget Function(
  BuildContext context,
  VoidCallback onPressed,
);

/// Called when a link in the default attribution dialog is tapped.
typedef AttributionLinkCallback = void Function(Uri uri);

/// Signature for building a scale control.
///
/// The `value` provides the formatted distance and intended logical width of
/// the scale bar.
typedef ScaleControlWidgetBuilder = Widget Function(
  BuildContext context,
  ScaleBarValue value,
);

/// Display values passed to a [ScaleControlWidgetBuilder].
@immutable
class const ScaleBarValue({
  /// The formatted distance, including its unit, shown by the scale bar.
  required final String label,

  /// The intended width of the scale bar in logical pixels.
  required final double width,
}) {
  @override
  bool operator ==(Object other) =>
      other is ScaleBarValue && other.label == label && other.width == width;

  @override
  int get hashCode => Object.hash(label, width);
}

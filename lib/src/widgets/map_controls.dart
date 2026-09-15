import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller/maplibre_map_controller.dart';
import 'controls/control_options.dart';
import 'controls/scale_bar.dart';
import 'controls/style_attribution.dart';

export 'controls/control_options.dart';
export 'controls/scale_bar.dart';
export 'controls/style_attribution.dart';

part 'controls/attribution_dialog.dart';
part 'controls/default_controls.dart';

double _finiteOrFallback(double value, double fallback) =>
    value.isFinite ? value : fallback;

double _finiteNonNegative(double value) =>
    value.isFinite && value >= 0 ? value : 0;

/// Lays out configured map controls at the corners of a viewport.
///
/// This internal widget expects [mapSize] to describe the same logical area as
/// its layout bounds. A null [controller] prevents the scale control from being
/// built and gives the compass builder a null reset callback.
class const MapLibreMapControls({
  super.key,

  /// The logical size used to calculate the scale control.
  required final Size mapSize,

  /// The controller used for compass actions and scale calculations.
  required final MapLibreMapController? controller,

  /// Whether the compass is shown.
  required final bool compassEnabled,

  /// Whether the MapLibre logo is shown.
  required final bool logoEnabled,

  /// The logo corner, or the lower-left corner when null.
  required final LogoViewPosition? logoViewPosition,

  /// The horizontal and vertical logo margins in logical pixels.
  ///
  /// Null and non-finite components use 8 logical pixels.
  required final math.Point<num>? logoViewMargins,

  /// The compass corner, or the upper-right corner when null.
  required final CompassViewPosition? compassViewPosition,

  /// The horizontal and vertical compass margins in logical pixels.
  ///
  /// Null and non-finite components use 8 logical pixels.
  required final math.Point<num>? compassViewMargins,

  /// Whether the attribution button is shown.
  required final bool attributionButtonEnabled,

  /// The attribution button corner, or the lower-right corner when null.
  required final AttributionButtonPosition? attributionButtonPosition,

  /// The horizontal and vertical attribution margins in logical pixels.
  ///
  /// Null and non-finite components use 8 logical pixels.
  required final math.Point<num>? attributionButtonMargins,

  /// Whether the scale control is shown.
  required final bool scaleControlEnabled,

  /// The corner used for the scale control.
  required final ScaleControlPosition scaleControlPosition,

  /// The unit used by the scale control.
  required final ScaleControlUnit scaleControlUnit,

  /// The horizontal and vertical scale margins in logical pixels.
  ///
  /// Defaults to 8 logical pixels on both axes. Non-finite components also use
  /// that value.
  final math.Point<num> scaleControlMargins = const math.Point<num>(8, 8),

  /// The maximum scale bar width in logical pixels.
  ///
  /// Defaults to 80 and must be finite and greater than zero.
  final double scaleControlMaxWidth = 80,

  /// Whether a scale control moves above an enabled logo in the same lower
  /// corner.
  ///
  /// Defaults to true.
  final bool scaleControlAvoidLogo = true,

  /// The additional bottom offset used to avoid the logo.
  ///
  /// Defaults to 27 logical pixels and must be finite and non-negative.
  final double scaleControlLogoOffset = 27,

  /// Called when a link in the default attribution dialog is tapped.
  ///
  /// A null callback leaves URLs visible and selectable without making their
  /// attribution rows interactive.
  final AttributionLinkCallback? onAttributionLinkTap,

  /// The compass builder, or null to hide the compass.
  ///
  /// Defaults to [buildDefaultCompass].
  final CompassWidgetBuilder? compassBuilder = buildDefaultCompass,

  /// The logo builder, or null to hide the logo.
  ///
  /// Defaults to [buildDefaultMapLibreLogo].
  final WidgetBuilder? logoBuilder = buildDefaultMapLibreLogo,

  /// The attribution button builder, or null to hide the button.
  ///
  /// Defaults to [buildDefaultAttributionButton].
  final AttributionButtonWidgetBuilder? attributionButtonBuilder =
      buildDefaultAttributionButton,

  /// The attribution dialog builder, or null to disable the dialog action.
  ///
  /// Defaults to [buildDefaultAttributionDialog].
  final WidgetBuilder? attributionDialogBuilder = buildDefaultAttributionDialog,

  /// The scale control builder, or null to hide the scale control.
  ///
  /// Defaults to [buildDefaultScaleControl].
  final ScaleControlWidgetBuilder? scaleControlBuilder =
      buildDefaultScaleControl,
}) extends StatelessWidget {
  this
    : assert(
        scaleControlMaxWidth > 0 && scaleControlMaxWidth < double.infinity,
      ),
      assert(
        scaleControlLogoOffset >= 0 && scaleControlLogoOffset < double.infinity,
      );

  static const _defaultMargin = math.Point<num>(8, 8);

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[];
    final bearing = controller?.cameraPosition?.bearing ?? 0;

    if (compassEnabled && compassBuilder != null) {
      controls.add(
        _positionedControl(
          corner: compassViewPosition ?? .topRight,
          margins: compassViewMargins,
          child: compassBuilder!(context, bearing, controller?.resetNorth),
        ),
      );
    }
    if (logoEnabled && logoBuilder != null) {
      controls.add(
        _positionedControl(
          corner: logoViewPosition ?? .bottomLeft,
          margins: logoViewMargins,
          child: logoBuilder!(context),
        ),
      );
    }

    if (attributionButtonEnabled && attributionButtonBuilder != null) {
      controls.add(
        _positionedControl(
          corner: attributionButtonPosition ?? .bottomRight,
          margins: attributionButtonMargins,
          child: attributionButtonBuilder!(
            context,
            () => _showAttribution(context),
          ),
        ),
      );
    }

    if (scaleControlEnabled &&
        scaleControlBuilder != null &&
        controller != null) {
      final scale = _scaleBar(controller!);
      if (scale.width > 0) {
        final logoCorner = logoViewPosition ?? .bottomLeft;
        // Move the scale bar above a logo that shares its bottom corner.
        final sharesBottomCorner =
            scaleControlAvoidLogo &&
            logoEnabled &&
            logoBuilder != null &&
            scaleControlPosition == logoCorner &&
            !scaleControlPosition.isTop;
        controls.add(
          _positionedControl(
            corner: scaleControlPosition,
            margins: scaleControlMargins,
            extraBottom: sharesBottomCorner
                ? _finiteNonNegative(scaleControlLogoOffset)
                : 0,
            child: scaleControlBuilder!(context, scale),
          ),
        );
      }
    }
    return Stack(children: controls);
  }

  /// Calculates the scale represented near the center of the viewport.
  ScaleBarValue _scaleBar(MapLibreMapController mapController) {
    if (!mapSize.width.isFinite ||
        !mapSize.height.isFinite ||
        mapSize.width <= 0 ||
        mapSize.height <= 0 ||
        !scaleControlMaxWidth.isFinite ||
        scaleControlMaxWidth <= 0) {
      return const ScaleBarValue(label: '', width: 0);
    }
    final sampleWidth = math
        .min(scaleControlMaxWidth, mapSize.width)
        .toDouble();
    final centerX = mapSize.width / 2;
    final centerY = mapSize.height / 2;
    try {
      final left = mapController.toLatLngOffset(
        Offset(centerX - sampleWidth / 2, centerY),
      );
      final right = mapController.toLatLngOffset(
        Offset(centerX + sampleWidth / 2, centerY),
      );

      return scaleBarValue(
        distanceMeters(left, right),
        scaleControlUnit,
        maxWidth: sampleWidth,
      );
    } on UnsupportedError {
      return const ScaleBarValue(label: '', width: 0);
    }
  }

  /// Positions a control using logical horizontal and vertical margins.
  Widget _positionedControl({
    required MapControlCorner corner,
    required Widget child,
    math.Point<num>? margins,
    double extraBottom = 0,
  }) {
    final margin = margins ?? _defaultMargin;
    final horizontal = _finiteOrFallback(
      margin.x.toDouble(),
      _defaultMargin.x.toDouble(),
    );
    final vertical = _finiteOrFallback(
      margin.y.toDouble(),
      _defaultMargin.y.toDouble(),
    );
    final bottomOffset = _finiteNonNegative(extraBottom);

    return Positioned(
      left: corner.isLeft ? horizontal : null,
      right: corner.isLeft ? null : horizontal,
      top: corner.isTop ? vertical : null,
      bottom: corner.isTop ? null : vertical + bottomOffset,
      child: child,
    );
  }

  /// Opens the configured attribution dialog when available.
  Future<void> _showAttribution(BuildContext context) async {
    final builder = attributionDialogBuilder;
    if (builder == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _AttributionControllerScope(
        controller: controller,
        onLinkTap: onAttributionLinkTap,
        child: Builder(builder: builder),
      ),
    );
  }
}

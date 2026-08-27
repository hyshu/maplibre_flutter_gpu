import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../geo/camera.dart';
import '../controller/maplibre_map_controller.dart';

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

/// Computes the great-circle distance between `a` and `b` in meters.
@visibleForTesting
double distanceMeters(LatLng a, LatLng b) {
  const earthRadiusMeters = 6371008.8;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final deltaLat = lat2 - lat1;
  var deltaLon = (b.longitude - a.longitude) * math.pi / 180;
  if (deltaLon > math.pi) deltaLon -= math.pi * 2;
  if (deltaLon < -math.pi) deltaLon += math.pi * 2;
  final sinLat = math.sin(deltaLat / 2);
  final sinLon = math.sin(deltaLon / 2);
  final haversine =
      sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;

  return earthRadiusMeters * 2 * math.asin(math.sqrt(haversine.clamp(0, 1)));
}

/// Selects a readable scale distance that fits within `maxWidth`.
///
/// The returned width is in logical pixels. An empty value is returned when
/// `metersAcrossMaxWidth` or `maxWidth` is not finite and positive.
@visibleForTesting
ScaleBarValue scaleBarValue(
  double metersAcrossMaxWidth,
  ScaleControlUnit unit, {
  double maxWidth = 80,
}) {
  if (!metersAcrossMaxWidth.isFinite ||
      metersAcrossMaxWidth <= 0 ||
      !maxWidth.isFinite ||
      maxWidth <= 0) {
    return const ScaleBarValue(label: '', width: 0);
  }

  late final double unitsAcrossMaxWidth;
  late final String suffix;
  switch (unit) {
    case ScaleControlUnit.metric:
      if (metersAcrossMaxWidth >= 1000) {
        unitsAcrossMaxWidth = metersAcrossMaxWidth / 1000;
        suffix = 'km';
      } else {
        unitsAcrossMaxWidth = metersAcrossMaxWidth;
        suffix = 'm';
      }
    case ScaleControlUnit.imperial:
      if (metersAcrossMaxWidth >= 1609.344) {
        unitsAcrossMaxWidth = metersAcrossMaxWidth / 1609.344;
        suffix = 'mi';
      } else {
        unitsAcrossMaxWidth = metersAcrossMaxWidth * 3.280839895;
        suffix = 'ft';
      }
    case ScaleControlUnit.nautical:
      unitsAcrossMaxWidth = metersAcrossMaxWidth / 1852;
      suffix = 'nm';
  }

  final niceUnits = _niceScaleFloor(unitsAcrossMaxWidth);
  final width = (niceUnits / unitsAcrossMaxWidth * maxWidth)
      .clamp(0, maxWidth)
      .toDouble();

  return ScaleBarValue(
    label: '${_formatScaleNumber(niceUnits)} $suffix',
    width: width,
  );
}

double _niceScaleFloor(double value) {
  final exponent = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final fraction = value / exponent;
  final niceFraction = fraction >= 5
      ? 5.0
      : fraction >= 2
      ? 2.0
      : 1.0;

  return niceFraction * exponent;
}

String _formatScaleNumber(double value) {
  if (value >= 10 || value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  if (value >= 1) return value.toStringAsFixed(1);

  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

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
          corner: compassViewPosition ?? CompassViewPosition.topRight,
          margins: compassViewMargins,
          child: compassBuilder!(context, bearing, controller?.resetNorth),
        ),
      );
    }
    if (logoEnabled && logoBuilder != null) {
      controls.add(
        _positionedControl(
          corner: logoViewPosition ?? LogoViewPosition.bottomLeft,
          margins: logoViewMargins,
          child: logoBuilder!(context),
        ),
      );
    }

    if (attributionButtonEnabled && attributionButtonBuilder != null) {
      controls.add(
        _positionedControl(
          corner:
              attributionButtonPosition ??
              AttributionButtonPosition.bottomRight,
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
        final logoCorner = logoViewPosition ?? LogoViewPosition.bottomLeft;
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

/// Builds the default compass control.
///
/// The control rotates with `bearing`, fades out while facing north, and calls
/// `onPressed` when pressed.
Widget buildDefaultCompass(
  BuildContext context,
  double bearing,
  VoidCallback? onPressed,
) => _CompassButton(bearing: bearing, onPressed: onPressed);

/// Builds the default non-interactive MapLibre logo.
Widget buildDefaultMapLibreLogo(BuildContext context) =>
    const IgnorePointer(child: _MapLibreLogo());

/// Builds the default attribution button.
///
/// Pressing the button calls `onPressed`.
Widget buildDefaultAttributionButton(
  BuildContext context,
  VoidCallback onPressed,
) => _AttributionButton(onPressed: onPressed);

/// Builds the default dialog from attribution declared by the active style.
///
/// Source attribution links call the configured handler when one is available.
Widget buildDefaultAttributionDialog(BuildContext context) =>
    _DefaultAttributionDialog(
      controller: _AttributionControllerScope.maybeControllerOf(context),
      onLinkTap: _AttributionControllerScope.maybeOnLinkTapOf(context),
    );

/// Parses attribution labels and links resolved from style sources.
///
/// Duplicate entries are omitted. Plain text is retained when an attribution
/// value contains no links.
@visibleForTesting
List<({String label, String? url})> parseStyleAttributions(
  Iterable<String> values,
) {
  final result = <({String label, String? url})>[];
  final seen = <(String, String?)>{};
  for (final value in values) {
    for (final entry in _parseAttribution(value)) {
      if (seen.add((entry.label, entry.url))) result.add(entry);
    }
  }

  return result;
}

List<({String label, String? url})> _parseAttribution(String value) {
  final anchorPattern = RegExp(
    r'<a\b([^>]*)>(.*?)</a\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  final result = <({String label, String? url})>[];
  for (final match in anchorPattern.allMatches(value)) {
    final label = _plainAttributionText(match.group(2)!);
    if (label.isEmpty) continue;
    final href = _hrefFromAttributes(match.group(1)!);
    result.add((label: label, url: href));
  }
  if (result.isEmpty) {
    final label = _plainAttributionText(value);
    if (label.isNotEmpty) result.add((label: label, url: null));
  }

  return result;
}

String? _hrefFromAttributes(String attributes) {
  final match = RegExp(
    r'''\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
    caseSensitive: false,
  ).firstMatch(attributes);
  final value = match?.group(1) ?? match?.group(2) ?? match?.group(3);
  final decoded = value == null ? '' : _decodeHtmlEntities(value).trim();

  return decoded.isEmpty ? null : decoded;
}

String _plainAttributionText(String value) =>
    _decodeHtmlEntities(value.replaceAll(RegExp(r'<[^>]*>'), ' '))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

String _decodeHtmlEntities(String value) {
  const named = {
    'amp': '&',
    'apos': "'",
    'copy': '©',
    'gt': '>',
    'lt': '<',
    'nbsp': ' ',
    'quot': '"',
    'reg': '®',
    'trade': '™',
  };

  return value.replaceAllMapped(
    RegExp(r'&(#(?:x[0-9a-f]+|\d+)|[a-z]+);', caseSensitive: false),
    (match) {
      final entity = match.group(1)!;
      if (!entity.startsWith('#')) {
        return named[entity.toLowerCase()] ?? match[0]!;
      }
      final hexadecimal = entity.length > 2 && entity[1].toLowerCase() == 'x';
      final codePoint = int.tryParse(
        entity.substring(hexadecimal ? 2 : 1),
        radix: hexadecimal ? 16 : 10,
      );

      return codePoint == null ? match[0]! : String.fromCharCode(codePoint);
    },
  );
}

/// Builds the default non-interactive scale control.
Widget buildDefaultScaleControl(BuildContext context, ScaleBarValue value) =>
    IgnorePointer(child: _ScaleBar(value: value));

class const _AttributionControllerScope({
  required final MapLibreMapController? controller,
  required final AttributionLinkCallback? onLinkTap,
  required super.child,
}) extends InheritedWidget {
  static MapLibreMapController? maybeControllerOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AttributionControllerScope>()
          ?.controller;

  static AttributionLinkCallback? maybeOnLinkTapOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AttributionControllerScope>()
          ?.onLinkTap;

  @override
  bool updateShouldNotify(_AttributionControllerScope oldWidget) =>
      controller != oldWidget.controller || onLinkTap != oldWidget.onLinkTap;
}

class const _DefaultAttributionDialog({
  required final MapLibreMapController? controller,
  required final AttributionLinkCallback? onLinkTap,
}) extends StatefulWidget {
  @override
  State<_DefaultAttributionDialog> createState() =>
      _DefaultAttributionDialogState();
}

class _DefaultAttributionDialogState extends State<_DefaultAttributionDialog> {
  late final Future<List<({String label, String? url})>> _attributions =
      _loadAttributions();

  Future<List<({String label, String? url})>> _loadAttributions() async {
    final values = await widget.controller?.getSourceAttributions();

    return values == null ? const [] : parseStyleAttributions(values);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Map attribution'),
    content: FutureBuilder<List<({String label, String? url})>>(
      future: _attributions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.square(
            dimension: 32,
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return const Text('Attribution is unavailable.');
        }
        final entries = snapshot.data ?? const [];
        if (entries.isEmpty) {
          return const Text('No attribution was provided by the active style.');
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final uri = entry.url == null ? null : Uri.tryParse(entry.url!);
              final canOpen =
                  uri != null && uri.hasScheme && widget.onLinkTap != null;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(entry.label),
                subtitle: entry.url == null ? null : SelectableText(entry.url!),
                trailing: canOpen ? const Icon(Icons.open_in_new) : null,
                onTap: canOpen ? () => widget.onLinkTap!(uri) : null,
              );
            },
          ),
        );
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

class const _CompassButton({
  required final double bearing,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final facingNorth = bearing.abs() < 0.01;

    return IgnorePointer(
      ignoring: facingNorth,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: facingNorth ? 0 : 1,
        child: Material(
          color: Colors.white.withValues(alpha: 0.9),
          elevation: 2,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Reset bearing to north',
            onPressed: onPressed,
            icon: Transform.rotate(
              angle: -bearing * math.pi / 180,
              child: const Icon(Icons.navigation, color: Color(0xFFE53935)),
            ),
          ),
        ),
      ),
    );
  }
}

class const _MapLibreLogo() extends StatelessWidget {
  @override
  Widget build(context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Text(
        'MapLibre',
        style: TextStyle(
          color: Color(0xFF263238),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class const _AttributionButton({required final VoidCallback onPressed})
    extends StatelessWidget {
  @override
  Widget build(context) => Material(
    color: Colors.white.withValues(alpha: 0.88),
    shape: const CircleBorder(),
    child: IconButton(
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      padding: EdgeInsets.zero,
      iconSize: 15,
      tooltip: 'Map attribution',
      onPressed: onPressed,
      icon: const Icon(Icons.info_outline),
    ),
  );
}

class const _ScaleBar({required final ScaleBarValue value})
    extends StatelessWidget {
  @override
  Widget build(context) => Semantics(
    label: 'Map scale ${value.label}',
    child: SizedBox(
      width: value.width,
      height: 25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.label,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.white, blurRadius: 2)],
            ),
          ),
          Container(
            height: 6,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.black, width: 2),
                right: BorderSide(color: Colors.black, width: 2),
                bottom: BorderSide(color: Colors.black, width: 2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

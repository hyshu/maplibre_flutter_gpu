part of '../map_controls.dart';

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

/// Builds the default non-interactive scale control.
Widget buildDefaultScaleControl(BuildContext context, ScaleBarValue value) =>
    IgnorePointer(child: _ScaleBar(value: value));

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
      style: IconButton.styleFrom(tapTargetSize: .shrinkWrap),
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
        crossAxisAlignment: .start,
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

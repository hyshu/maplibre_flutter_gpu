import 'package:flutter/widgets.dart';

import '../state/user_location_projection.dart';
import 'user_location_marker.dart';

/// Places a builder's marker at the cached frame location.
class UserLocationOverlay extends StatelessWidget {
  const UserLocationOverlay({
    required this.projection,
    required this.builder,
    super.key,
  });

  final UserLocationProjection projection;
  final MapUserLocationWidgetBuilder builder;

  @override
  Widget build(context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
      final state = projection.forLayout(size);
      final child = builder(context, state);
      if (child == null) return const SizedBox.shrink();

      return ClipRect(
        child: CustomSingleChildLayout(
          delegate: _LocationLayout(state.screenPosition),
          child: child,
        ),
      );
    },
  );
}

class _LocationLayout extends SingleChildLayoutDelegate {
  const _LocationLayout(this.position);

  final Offset position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      position - childSize.center(Offset.zero);

  @override
  bool shouldRelayout(_LocationLayout oldDelegate) =>
      oldDelegate.position != position;
}

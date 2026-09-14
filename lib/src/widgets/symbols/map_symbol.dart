/// @docImport 'symbol_overlay.dart';
library;

import 'package:flutter/foundation.dart' show internal;
import 'package:flutter/widgets.dart';

import '../../labels/label_data.dart';
import '../../sprites/sprite_atlas.dart';

/// Placement information for a symbol displayed by a [MapSymbolOverlay].
///
/// The [textPos] and [iconPos] anchors use logical pixels from the top-left of
/// the map viewport. Their x coordinates increase to the right and their y
/// coordinates increase downward. The overlay centers each builder's widget on
/// the corresponding anchor.
///
/// Each [key] must be unique within a [MapSymbolOverlay.symbols] list. Reusing a
/// key in later lists preserves the symbol's widget and fade state while its
/// placement changes.
class const MapSymbol({
  /// The stable identity of this symbol across placement updates.
  ///
  /// This value must be unique among the symbols in the same overlay.
  required final String key,

  /// The evaluated style data used to build this symbol.
  required final LabelData data,

  /// The text anchor in logical pixels from the viewport's top-left corner.
  ///
  /// A null value means that no text child is laid out for this symbol.
  required final Offset? textPos,

  /// The icon anchor in logical pixels from the viewport's top-left corner.
  ///
  /// A null value means that no icon child is laid out for this symbol.
  required final Offset? iconPos,

  /// The resolved sprite used by the default icon builder.
  ///
  /// This is null when the symbol has no sprite or its sprite is unavailable.
  /// A custom icon builder can still build a widget when [iconPos] is non-null.
  required final SpriteIcon? icon,

  /// Sprite atlas used to resolve images embedded in formatted text.
  ///
  /// This can be null when the active style has no sprite or its atlas is not
  /// available yet.
  final SpriteAtlas? spriteAtlas,

  /// Whether the symbol is present in the latest placement.
  ///
  /// A false value retains the symbol only long enough to fade out. The owner
  /// can remove it when [MapSymbolOverlay.onFadedOut] reports this [key].
  required final bool visible,

  /// Whether newly built children start transparent and fade in.
  ///
  /// This value affects a new keyed child and does not restart the fade when an
  /// existing child is rebuilt. Defaults to true.
  final bool fadeIn = true,
}) {
  /// The anchor used for viewport culling.
  ///
  /// The text anchor is preferred when both anchors are present. The overlay
  /// culls each component using its own anchor. This getter is available to
  /// clients that need one representative position.
  Offset? get anchor => textPos ?? iconPos;
}

/// Signature for building one visual part of a [MapSymbol].
///
/// The overlay calls this builder independently for its icon and text parts.
/// An icon widget is centered on [MapSymbol.iconPos], and a text widget is
/// centered on [MapSymbol.textPos]. Returning null omits that part.
///
/// When the same location appears more than once on screen, such as when
/// zooming out, the same symbol may be placed multiple times. Each placement
/// needs an independent widget and must not share a [GlobalKey].
///
/// Builder results receive pointer events while their symbol is visible.
/// Gesture handlers can consume those events instead of passing them to the
/// map beneath the overlay.
typedef SymbolWidgetBuilder = Widget? Function(
  BuildContext context,
  MapSymbol symbol,
);

/// Live keyed positions used by the map's position-only symbol updates.
///
/// Implementations keep the immutable visual snapshot separate from current
/// screen anchors. This interface is internal and is not exported by the
/// package barrel.
@internal
abstract interface class SymbolPositionList implements List<MapSymbol> {
  /// Returns the latest anchor for one symbol component.
  Offset? anchorFor(String key, {required bool icon});

  /// Returns [symbol] with its latest positions and placement data.
  MapSymbol positioned(MapSymbol symbol);
}

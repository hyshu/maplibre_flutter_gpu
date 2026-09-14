/// @docImport '../maplibre_map.dart';
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../labels/label_data.dart';
import '../../sprites/sprite_atlas.dart';
import 'default_symbol_builders.dart';
import 'map_symbol.dart';

part 'symbol_paint_item.dart';
part 'symbol_fades.dart';
part 'symbol_batch.dart';
part 'symbol_visual_cache.dart';
part 'symbol_positions.dart';

/// A widget that lays out icon and text widgets for placed map symbols.
///
/// Each builder result is centered on its corresponding [MapSymbol] anchor.
/// Each component is omitted when its own anchor lies outside the viewport
/// extended by [cullingPadding]. The other component remains visible when its
/// anchor is inside that area.
///
/// Children paint in MapLibre's exported order. Within each native paint group,
/// all icons paint before all text so overlapping components match symbol
/// layer compositing.
///
/// A disappearing symbol must remain in [symbols] with
/// [MapSymbol.visible] set to false for its children to fade out. Removing it
/// from [symbols] immediately removes its children without a fade. When a
/// fading child finishes, [onFadedOut] reports that the owner can discard the
/// hidden symbol.
///
/// Default icon and text children ignore pointer events so they do not block
/// the map. Widgets returned by custom builders receive pointer events while
/// their symbol is visible.
///
/// [MapLibreMap] creates this overlay for its placed symbols. Most applications
/// can customize those symbols through [MapLibreMap.symbolIconBuilder] and
/// [MapLibreMap.symbolTextBuilder] instead of constructing an overlay.
///
/// See also:
///
///  * [MapSymbol], which describes one placed symbol.
///  * [SymbolWidgetBuilder], which builds an icon or text child.
class const MapSymbolOverlay({
  super.key,

  /// The symbol snapshot used to build, cull, and identify the current children.
  ///
  /// Keys must be unique within this list. The list must not be mutated after it
  /// is passed to the overlay. Membership, visibility, style data, or available
  /// icon and text parts must be changed by rebuilding with a new list.
  required final List<MapSymbol> symbols,

  /// Supplies the latest positions for existing children during layout.
  ///
  /// This provider supports position-only updates without replacing the
  /// [symbols] snapshot. Its symbols must keep the same keys and available icon
  /// and text parts as [symbols]. Only their keys, [MapSymbol.iconPos], and
  /// [MapSymbol.textPos] are read from this provider.
  ///
  /// When null, layout uses [symbols].
  final List<MapSymbol> Function()? symbolsProvider,

  /// Notifies the overlay to read [symbolsProvider], recull its components, and
  /// reposition its children. Position changes normally update layout without
  /// rebuilding the overlay. The overlay rebuilds when a component crosses the
  /// culling boundary. Custom builder children rebuild independently so they
  /// continue to receive the latest positions.
  final Listenable? relayout,

  /// The logical viewport size used for symbol culling.
  ///
  /// This should match the map area covered by the overlay. Culling is
  /// recomputed after position-only [relayout] notifications.
  required final Size screenSize,

  /// Called when one of a hidden symbol's children finishes fading out.
  ///
  /// A symbol with both icon and text children can report the same key more
  /// than once. A hidden symbol that is culled or has no anchor is also reported
  /// after a post-frame grace period because it has no child to animate. The
  /// reported symbol may have become visible again, so removal handlers need
  /// idempotent, visibility-aware behavior.
  required final void Function(String key) onFadedOut,

  /// Builds each symbol's icon, or hides all icons when null.
  ///
  /// Defaults to the style-derived sprite builder.
  final SymbolWidgetBuilder? iconBuilder = buildDefaultSymbolIcon,

  /// Builds each symbol's text label, or hides all labels when null.
  ///
  /// Defaults to the style-derived text builder.
  final SymbolWidgetBuilder? textBuilder = buildDefaultSymbolText,

  /// The duration of symbol fade-in and fade-out transitions.
  ///
  /// Defaults to 150 milliseconds and must not be negative.
  final Duration fadeDuration = const Duration(milliseconds: 150),

  /// The area beyond each viewport edge in which symbols are retained.
  ///
  /// Culling tests each text and icon anchor independently, not the bounds of
  /// its built widget. The default extends the horizontal edges by 120 logical
  /// pixels and the vertical edges by 60 logical pixels. An [EdgeInsets] with
  /// any non-finite or negative component is treated as [EdgeInsets.zero].
  final EdgeInsets cullingPadding = const EdgeInsets.symmetric(
    horizontal: 120,
    vertical: 60,
  ),
}) extends StatefulWidget {
  this : assert(fadeDuration >= Duration.zero);

  @override
  State<MapSymbolOverlay> createState() => _MapSymbolOverlayState();
}

class _MapSymbolOverlayState extends State<MapSymbolOverlay>
    with SingleTickerProviderStateMixin {
  final _defaultVisuals = <String, _DefaultSymbolVisuals>{};
  final _liveKeys = <String>{};
  final _pendingCulledFadeKeys = <String>{};
  var _culledFadeDrainScheduled = false;
  final _positions = _SymbolPositionStore();
  late final _BatchedSymbolFadeController _batchedFades;
  Map<String, int> _componentMembership = const {};

  @override
  void initState() {
    super.initState();
    _batchedFades = .new(
      vsync: this,
      onFadedOut: (key) => widget.onFadedOut(key),
    );
    _refreshPositions();
    widget.relayout?.addListener(_handleRelayout);
  }

  @override
  void didUpdateWidget(covariant MapSymbolOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshPositions();
    if (!identical(oldWidget.relayout, widget.relayout)) {
      oldWidget.relayout?.removeListener(_handleRelayout);
      widget.relayout?.addListener(_handleRelayout);
    }
  }

  @override
  void dispose() {
    widget.relayout?.removeListener(_handleRelayout);
    _batchedFades.dispose();
    _positions.dispose();
    super.dispose();
  }

  void _handleRelayout() {
    if (!mounted) return;
    _refreshPositions();
    if (_componentMembershipChanged()) {
      setState(() {});

      return;
    }
    _positions.notifyPositionChange();
  }

  void _refreshPositions() =>
      _positions.update(widget.symbolsProvider?.call() ?? widget.symbols);

  @override
  Widget build(context) {
    final paintItems = <_SymbolPaintItem>[];
    final liveKeys = _liveKeys..clear();
    final cullingPadding = _validCullingPadding(widget.cullingPadding);
    final usesDefaultIcon = identical(
      widget.iconBuilder,
      buildDefaultSymbolIcon,
    );
    final usesDefaultText = identical(
      widget.textBuilder,
      buildDefaultSymbolText,
    );
    final componentMembership = <String, int>{};
    var paintOrdinal = 0;
    for (final symbol in widget.symbols) {
      liveKeys.add(symbol.key);
      if (symbol.visible) _pendingCulledFadeKeys.remove(symbol.key);
      final iconId = (symbol.key, true);
      final textId = (symbol.key, false);
      final iconPos = _positions.anchorFor(symbol.key, icon: true);
      final textPos = _positions.anchorFor(symbol.key, icon: false);
      final iconInBounds = _isAnchorInBounds(iconPos, cullingPadding);
      final textInBounds = _isAnchorInBounds(textPos, cullingPadding);
      var membership = 0;
      if (widget.iconBuilder != null && iconInBounds) membership |= 1;
      if (widget.textBuilder != null && textInBounds) membership |= 2;
      if (membership != 0) componentMembership[symbol.key] = membership;
      if (!iconInBounds && !textInBounds) {
        _completeCulledFade(symbol);
        continue;
      }
      _pendingCulledFadeKeys.remove(symbol.key);
      final skipsHiddenDefaults =
          !symbol.visible && widget.fadeDuration == Duration.zero;
      final defaults =
          (usesDefaultIcon || usesDefaultText) && !skipsHiddenDefaults
          ? _defaultVisuals.update(
              symbol.key,
              (cached) => cached.update(context, symbol),
              ifAbsent: () => .from(context, symbol),
            )
          : null;
      // Position icon and text independently while fading both together.
      final iconWidget = !iconInBounds
          ? null
          : usesDefaultIcon
          ? skipsHiddenDefaults
                ? symbol.icon == null
                      ? null
                      : const SizedBox.shrink()
                : defaults!.icon
          : widget.iconBuilder == null
          ? null
          : _PositionedSymbolBuilder(
              symbol: symbol,
              positions: _positions,
              builder: widget.iconBuilder!,
            );
      var hasPaintItem = false;
      if (iconWidget != null && iconPos != null) {
        hasPaintItem = true;
        paintItems.add(
          _SymbolPaintItem(
            id: iconId,
            layerIndex: symbol.data.layerIndex,
            renderGroup: symbol.data.renderGroup,
            componentOrder: 0,
            renderOrder: symbol.data.renderOrder,
            ordinal: paintOrdinal++,
            symbolKey: symbol.key,
            visible: symbol.visible,
            fadeIn: symbol.fadeIn,
            interactive: !usesDefaultIcon,
            child: iconWidget,
          ),
        );
      }
      final textWidget = !textInBounds
          ? null
          : usesDefaultText
          ? skipsHiddenDefaults
                ? !symbol.data.textPlaced || symbol.data.text.isEmpty
                      ? null
                      : const SizedBox.shrink()
                : defaults!.text
          : widget.textBuilder == null
          ? null
          : _PositionedSymbolBuilder(
              symbol: symbol,
              positions: _positions,
              builder: widget.textBuilder!,
            );
      if (textWidget != null && textPos != null) {
        hasPaintItem = true;
        paintItems.add(
          _SymbolPaintItem(
            id: textId,
            layerIndex: symbol.data.layerIndex,
            renderGroup: symbol.data.renderGroup,
            componentOrder: 1,
            renderOrder: symbol.data.renderOrder,
            ordinal: paintOrdinal++,
            symbolKey: symbol.key,
            visible: symbol.visible,
            fadeIn: symbol.fadeIn,
            interactive: !usesDefaultText,
            child: textWidget,
          ),
        );
      }
      if (!symbol.visible && !hasPaintItem) _completeCulledFade(symbol);
    }
    _defaultVisuals.removeWhere((key, _) => !liveKeys.contains(key));
    _componentMembership = componentMembership;
    paintItems.sort(_SymbolPaintItem.compare);
    _batchedFades.update(paintItems, widget.fadeDuration);

    return _SymbolBatch(
      paintItems: paintItems,
      positions: _positions,
      fades: _batchedFades,
      screenSize: widget.screenSize,
    );
  }

  bool _componentMembershipChanged() {
    final padding = _validCullingPadding(widget.cullingPadding);
    var count = 0;
    for (final key in _liveKeys) {
      var membership = 0;
      if (widget.iconBuilder != null &&
          _isAnchorInBounds(_positions.anchorFor(key, icon: true), padding)) {
        membership |= 1;
      }
      if (widget.textBuilder != null &&
          _isAnchorInBounds(_positions.anchorFor(key, icon: false), padding)) {
        membership |= 2;
      }
      if (membership == 0) continue;
      count++;
      if (_componentMembership[key] != membership) return true;
    }

    return count != _componentMembership.length;
  }

  /// Returns a finite non-negative padding for culling calculations.
  EdgeInsets _validCullingPadding(EdgeInsets padding) {
    if (!padding.left.isFinite ||
        !padding.top.isFinite ||
        !padding.right.isFinite ||
        !padding.bottom.isFinite ||
        !padding.isNonNegative) {
      return EdgeInsets.zero;
    }

    return padding;
  }

  bool _isAnchorInBounds(Offset? anchor, EdgeInsets padding) {
    if (anchor == null) return false;

    return anchor.dx >= -padding.left &&
        anchor.dx <= widget.screenSize.width + padding.right &&
        anchor.dy >= -padding.top &&
        anchor.dy <= widget.screenSize.height + padding.bottom;
  }

  // Culled symbols have no fade widget to report their completion.
  void _completeCulledFade(MapSymbol symbol) {
    if (symbol.visible) return;
    _pendingCulledFadeKeys.add(symbol.key);
    if (_culledFadeDrainScheduled) return;
    _culledFadeDrainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _culledFadeDrainScheduled = false;
        while (_pendingCulledFadeKeys.isNotEmpty) {
          final key = _pendingCulledFadeKeys.first;
          _pendingCulledFadeKeys.remove(key);
          widget.onFadedOut(key);
        }
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }
}

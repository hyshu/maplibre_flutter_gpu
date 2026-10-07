import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tv_city.dart';

/// Camera and attribution operations available in the TV menu.
enum TvMapAction {
  /// Increases the zoom level by one.
  zoomIn,

  /// Decreases the zoom level by one.
  zoomOut,

  /// Switches between flat and tilted views.
  toggle3d,

  /// Opens the map's source credits.
  attribution,
}

enum _Panel { cities, map, menu }

/// Places remote controls above a map without giving the map keyboard focus.
///
/// Starts in map movement mode. Direction keys select buttons or pan in map
/// mode. Enter, numpad Enter and the remote's select key activate the selection.
/// Only direction keys repeat.
class TvMapControls extends StatefulWidget {
  const TvMapControls({
    super.key,
    required this.child,
    required this.ready,
    required this.is3d,
    required this.onVisit,
    required this.onPan,
    required this.onAction,
    this.message,
  });

  /// The map displayed beneath the controls.
  final Widget child;

  /// Whether the map can accept camera commands.
  final bool ready;

  /// Whether the current camera is tilted.
  final bool is3d;

  /// Requests a flight to a preset city.
  final ValueChanged<TvCity> onVisit;

  /// Requests camera movement toward a screen direction in logical pixels.
  final ValueChanged<Offset> onPan;

  /// Requests an operation from the menu.
  final ValueChanged<TvMapAction> onAction;

  /// An optional camera or loading error displayed above the buttons.
  final String? message;

  @override
  State<TvMapControls> createState() => _TvMapControlsState();
}

class _TvMapControlsState extends State<TvMapControls> {
  static const _panStep = 64.0;
  static const _menuLength = 6;
  final _focusNode = FocusNode(debugLabel: 'TV map remote');
  final _selectedButton = GlobalKey();
  var _panel = _Panel.map;
  var _city = TvCity.newYork;
  var _cityIndex = 0;
  var _menuIndex = 0;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _show(_Panel panel) {
    setState(() => _panel = panel);
    _focusNode.requestFocus();
    _revealSelection();
  }

  void _revealSelection() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = _selectedButton.currentContext;
    if (!mounted || context == null) return;
    Scrollable.ensureVisible(context, alignment: 0.5);
  });

  void _navigate(LogicalKeyboardKey key) {
    if (!widget.ready) return;
    if (_panel == _Panel.map) {
      final offset = switch (key) {
        LogicalKeyboardKey.arrowLeft => const Offset(-_panStep, 0),
        LogicalKeyboardKey.arrowRight => const Offset(_panStep, 0),
        LogicalKeyboardKey.arrowUp => const Offset(0, -_panStep),
        _ => const Offset(0, _panStep),
      };
      widget.onPan(offset);

      return;
    }
    final step = switch (key) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (step == 0) return;
    setState(() {
      if (_panel == _Panel.cities) {
        _cityIndex = (_cityIndex + step).clamp(0, TvCity.values.length - 1);
      } else {
        _menuIndex = (_menuIndex + step).clamp(0, _menuLength - 1);
      }
    });
    _revealSelection();
  }

  void _visit(int index) {
    if (!widget.ready) return;
    _cityIndex = index;
    _city = TvCity.values[index];
    widget.onVisit(_city);
    _show(_Panel.map);
  }

  void _selectMenu(int index) {
    if (!widget.ready) return;
    setState(() => _menuIndex = index);
    switch (index) {
      case 0:
        _show(_Panel.map);
      case 1:
        widget.onAction(.zoomIn);
      case 2:
        widget.onAction(.zoomOut);
      case 3:
        widget.onAction(.toggle3d);
      case 4:
        _show(_Panel.cities);
      case 5:
        widget.onAction(.attribution);
    }
  }

  void _activate() {
    if (!widget.ready) return;
    switch (_panel) {
      case .cities:
        _visit(_cityIndex);
      case .map:
        _menuIndex = 0;
        _show(_Panel.menu);
      case .menu:
        _selectMenu(_menuIndex);
    }
  }

  bool _back() {
    switch (_panel) {
      case .menu:
        _show(_Panel.map);

        return true;
      case .map:
        _show(_Panel.cities);

        return true;
      case .cities:
        return false;
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isArrow =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
    if (isArrow) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) _navigate(key);

      return .handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      if (event is KeyDownEvent) _activate();

      return .handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent && _back()) return .handled;
      if (event is! KeyDownEvent) return .handled;

      return .ignored;
    }

    return .ignored;
  }

  Widget _button(String label, int index, VoidCallback onPressed) {
    final selected =
        index == (_panel == _Panel.cities ? _cityIndex : _menuIndex);
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        focused: selected,
        child: OutlinedButton(
          key: selected ? _selectedButton : null,
          onPressed: widget.ready ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: selected ? colors.onPrimaryContainer : null,
            backgroundColor: selected ? colors.primaryContainer : null,
            side: BorderSide(
              color: selected ? colors.primary : colors.outline,
              width: selected ? 3 : 1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            textStyle: const TextStyle(fontSize: 18),
          ),
          child: Text(label),
        ),
      ),
    );
  }

  @override
  Widget build(context) {
    final labels = [
      'Move map',
      'Zoom in',
      'Zoom out',
      widget.is3d ? '2D view' : '3D view',
      'Cities',
      'Map data',
    ];

    return PopScope(
      canPop: _panel == _Panel.cities,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _onKeyEvent,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeFocus(child: IgnorePointer(child: widget.child)),
            ),
            Align(
              alignment: .bottomCenter,
              child: SafeArea(
                minimum: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          _panel == _Panel.cities
                              ? 'Choose a city'
                              : _city.label,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (widget.message != null || !widget.ready) ...[
                          const SizedBox(height: 8),
                          Text(widget.message ?? 'Loading map…'),
                        ],
                        if (_panel != _Panel.map) ...[
                          const SizedBox(height: 12),
                          ExcludeFocus(
                            child: SingleChildScrollView(
                              scrollDirection: .horizontal,
                              child: Row(
                                children: _panel == _Panel.cities
                                    ? [
                                        for (final (index, city)
                                            in TvCity.values.indexed)
                                          _button(
                                            city.label,
                                            index,
                                            () => _visit(index),
                                          ),
                                      ]
                                    : [
                                        for (final (index, label)
                                            in labels.indexed)
                                          _button(
                                            label,
                                            index,
                                            () => _selectMenu(index),
                                          ),
                                      ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'heatmap_style.dart';

/// Controls commit slider values when the drag ends.
class HeatmapControls extends StatelessWidget {
  const new({
    super.key,
    required this.settings,
    required this.enabled,
    required this.onChanged,
    required this.onCommitted,
  });

  final HeatmapSettings settings;
  final bool enabled;
  final ValueChanged<HeatmapSettings> onChanged;
  final ValueChanged<HeatmapSettings> onCommitted;

  @override
  Widget build(context) => Column(
    crossAxisAlignment: .start,
    children: [
      const Text('Explore earthquake density across the map.'),
      const SizedBox(height: 12),
      SwitchListTile.adaptive(
        contentPadding: .zero,
        title: const Text('Show heatmap'),
        value: settings.visible,
        onChanged: enabled
            ? (value) => onCommitted(settings.copyWith(visible: value))
            : null,
      ),
      _slider(
        'Radius',
        '${settings.radius.round()} px',
        settings.radius,
        4,
        60,
        (value) => settings.copyWith(radius: value),
      ),
      _slider(
        'Intensity',
        settings.intensity.toStringAsFixed(1),
        settings.intensity,
        0,
        3,
        (value) => settings.copyWith(intensity: value),
      ),
      _slider(
        'Opacity',
        '${(settings.opacity * 100).round()}%',
        settings.opacity,
        0,
        1,
        (value) => settings.copyWith(opacity: value),
      ),
      SwitchListTile.adaptive(
        contentPadding: .zero,
        title: const Text('Weight by magnitude'),
        value: settings.weighted,
        onChanged: enabled
            ? (value) => onCommitted(settings.copyWith(weighted: value))
            : null,
      ),
      SwitchListTile.adaptive(
        contentPadding: .zero,
        title: const Text('Show earthquake points'),
        value: settings.pointsVisible,
        onChanged: enabled
            ? (value) => onCommitted(settings.copyWith(pointsVisible: value))
            : null,
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 10,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [for (final color in densityColors) Color(color)],
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      const Row(
        mainAxisAlignment: .spaceBetween,
        children: [Text('Low density'), Text('High density')],
      ),
      const SizedBox(height: 12),
      Text(
        'Relative density changes with zoom, radius and weight.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _slider(
    String name,
    String label,
    double value,
    double min,
    double max,
    HeatmapSettings Function(double) update,
  ) => Column(
    children: [
      Row(
        mainAxisAlignment: .spaceBetween,
        children: [Text(name), Text(label)],
      ),
      Slider(
        key: ValueKey(name),
        value: value,
        min: min,
        max: max,
        label: label,
        semanticFormatterCallback: (_) => '$name $label',
        onChanged: enabled ? (value) => onChanged(update(value)) : null,
        onChangeEnd: enabled ? (value) => onCommitted(update(value)) : null,
      ),
    ],
  );
}

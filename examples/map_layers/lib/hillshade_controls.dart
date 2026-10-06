import 'package:flutter/material.dart';

import 'hillshade_style.dart';

/// Shading controls commit slider values when the drag ends.
class HillshadeControls extends StatelessWidget {
  const new({
    super.key,
    required this.settings,
    required this.enabled,
    required this.onChanged,
    required this.onCommitted,
  });

  final HillshadeSettings settings;
  final bool enabled;
  final ValueChanged<HillshadeSettings> onChanged;
  final ValueChanged<HillshadeSettings> onCommitted;

  @override
  Widget build(context) => Column(
    crossAxisAlignment: .start,
    children: [
      const Text('Explore shaded relief around Innsbruck in the Alps.'),
      const SizedBox(height: 12),
      SwitchListTile.adaptive(
        contentPadding: .zero,
        title: const Text('Show hillshade'),
        value: settings.visible,
        onChanged: enabled
            ? (value) => onCommitted(settings.copyWith(visible: value))
            : null,
      ),
      DropdownButtonFormField<String>(
        key: ValueKey(settings.method),
        initialValue: settings.method,
        decoration: const InputDecoration(labelText: 'Shading method'),
        isExpanded: true,
        items: const [
          DropdownMenuItem(value: 'standard', child: Text('Standard')),
          DropdownMenuItem(value: 'basic', child: Text('Basic')),
          DropdownMenuItem(value: 'combined', child: Text('Combined')),
          DropdownMenuItem(value: 'igor', child: Text('Igor')),
          DropdownMenuItem(
            value: 'multidirectional',
            child: Text('Multidirectional'),
          ),
        ],
        onChanged: enabled
            ? (value) {
                if (value != null) {
                  onCommitted(settings.copyWith(method: value));
                }
              }
            : null,
      ),
      const SizedBox(height: 16),
      _slider(
        'Exaggeration',
        settings.exaggeration.toStringAsFixed(2),
        settings.exaggeration,
        1,
        (value) => settings.copyWith(exaggeration: value),
      ),
      _slider(
        'Light direction',
        '${settings.direction.round()}°',
        settings.direction,
        359,
        (value) => settings.copyWith(direction: value),
      ),
      if (settings.method != 'standard' && settings.method != 'igor')
        _slider(
          'Light altitude',
          '${settings.altitude.round()}°',
          settings.altitude,
          90,
          (value) => settings.copyWith(altitude: value),
        ),
      SwitchListTile.adaptive(
        contentPadding: .zero,
        title: const Text('Anchor light to map'),
        value: settings.anchoredToMap,
        onChanged: enabled
            ? (value) => onCommitted(settings.copyWith(anchoredToMap: value))
            : null,
      ),
      if (settings.method == 'multidirectional')
        Text(
          'Three lights are spaced 120° apart.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );

  Widget _slider(
    String name,
    String label,
    double value,
    double max,
    HillshadeSettings Function(double) update,
  ) => Column(
    children: [
      Row(
        mainAxisAlignment: .spaceBetween,
        children: [Text(name), Text(label)],
      ),
      Slider(
        key: ValueKey(name),
        value: value,
        max: max,
        label: label,
        semanticFormatterCallback: (_) => '$name $label',
        onChanged: enabled ? (value) => onChanged(update(value)) : null,
        onChangeEnd: enabled ? (value) => onCommitted(update(value)) : null,
      ),
    ],
  );
}

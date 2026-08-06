// Gates on which render paths a scene actually exercised.
//
// The image baseline proves visible pixels did not change. It cannot prove a
// path ran at all: a tile clipping mask writes only stencil, a stencil clear
// draws nothing, and a scene whose source silently failed to load simply
// renders fewer commands while still matching a baseline captured from the
// same broken state — or drops out of the baseline comparison entirely.
//
// So the expected set of shaders and stencil modes is recorded alongside the
// image baseline and re-checked on every run. Presence, not exact counts:
// counts move with tile loading, but a path disappearing is always a defect.
//
// Placed labels are tracked the same way and for a sharper reason: this
// backend draws symbols as Flutter widgets, so they emit no draw commands at
// all. Their only machine-checkable signal is the placement export.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('coverage', mandatory: true, help: 'This run\'s report.')
    ..addOption('expected', mandatory: true, help: 'Committed expectations.')
    ..addOption('scene', defaultsTo: 'geometry')
    ..addFlag(
      'update-expected',
      defaultsTo: false,
      negatable: false,
      help:
          'Add paths from this run to the expectation. Existing required '
          'paths are never removed.',
    );

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(parser.usage);
    exitCode = 2;

    return;
  }

  final scene = options.option('scene')!;
  final coverageFile = File(options.option('coverage')!);
  final expectedFile = File(options.option('expected')!);

  if (!await coverageFile.exists()) {
    stderr.writeln('Command coverage report missing: ${coverageFile.path}');
    exitCode = 2;

    return;
  }

  final Map<String, Object?> coverage;
  try {
    coverage =
        jsonDecode(await coverageFile.readAsString()) as Map<String, Object?>;
  } on FormatException catch (error) {
    stderr.writeln(
      'Command coverage report is not valid JSON: ${error.message}',
    );
    exitCode = 2;

    return;
  }

  final shaders = _names(coverage['shaders']);
  final stencilModes = _names(coverage['stencilModes']);
  final placedLabels = switch (coverage['placedLabels']) {
    final num value => value.toInt(),
    _ => 0,
  };
  final labelTexts = _required(coverage['placedLabelTexts']);

  if (options.flag('update-expected')) {
    var requiredShaders = <String>{...shaders};
    var requiredStencilModes = <String>{...stencilModes};
    Map<String, Object?>? existingExpectation;
    if (await expectedFile.exists()) {
      existingExpectation = await _readJsonObject(
        expectedFile,
        description: 'Command coverage expectation',
      );
      if (existingExpectation == null) return;
      requiredShaders = <String>{
        ..._required(existingExpectation['requiredShaders']),
        ...requiredShaders,
      };
      requiredStencilModes = <String>{
        ..._required(existingExpectation['requiredStencilModes']),
        ...requiredStencilModes,
      };
    }
    var minimumPlacedLabels = placedLabels;
    var requiredLabelTexts = <String>{...labelTexts};
    if (existingExpectation != null) {
      minimumPlacedLabels =
          switch (existingExpectation['minimumPlacedLabels']) {
            final num value when value.toInt() > minimumPlacedLabels =>
              value.toInt(),
            _ => minimumPlacedLabels,
          };
      requiredLabelTexts = <String>{
        ..._required(existingExpectation['requiredLabelTexts']),
        ...requiredLabelTexts,
      };
    }
    await expectedFile.parent.create(recursive: true);
    final expectation = <String, Object?>{
      'scene': scene,
      'requiredShaders': requiredShaders.toList()..sort(),
      'requiredStencilModes': requiredStencilModes.toList()..sort(),
      'minimumPlacedLabels': minimumPlacedLabels,
      'requiredLabelTexts': requiredLabelTexts.toList()..sort(),
    };
    await expectedFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(expectation)}\n',
      flush: true,
    );
    stdout.writeln(
      'Command coverage expectation updated: ${expectedFile.path}',
    );
    stdout.writeln(
      '  shaders: ${(requiredShaders.toList()..sort()).join(', ')}',
    );
    stdout.writeln(
      '  stencil modes: '
      '${(requiredStencilModes.toList()..sort()).join(', ')}',
    );

    return;
  }

  if (!await expectedFile.exists()) {
    stderr.writeln('No command coverage expectation for $scene.');
    stderr.writeln('Record one with --update-expected on a known-good commit.');
    exitCode = 2;

    return;
  }

  final expected = await _readJsonObject(
    expectedFile,
    description: 'Command coverage expectation',
  );
  if (expected == null) return;
  final missingShaders = _required(
    expected['requiredShaders'],
  ).difference(shaders).toList()..sort();
  final missingStencilModes = _required(
    expected['requiredStencilModes'],
  ).difference(stencilModes).toList()..sort();
  final missingLabelTexts = _required(
    expected['requiredLabelTexts'],
  ).difference(labelTexts).toList()..sort();
  final minimumPlacedLabels = switch (expected['minimumPlacedLabels']) {
    final num value => value.toInt(),
    _ => 0,
  };
  final labelShortfall = placedLabels < minimumPlacedLabels;

  if (missingShaders.isEmpty &&
      missingStencilModes.isEmpty &&
      missingLabelTexts.isEmpty &&
      !labelShortfall) {
    stdout.writeln(
      '$scene exercised ${shaders.length} shaders and '
      '${stencilModes.length} stencil modes, and placed $placedLabels '
      'labels; all expected paths present.',
    );

    return;
  }

  stderr.writeln('$scene stopped exercising render paths it used to reach:');
  if (labelShortfall) {
    stderr.writeln(
      '  placed labels: $placedLabels (expected at least '
      '$minimumPlacedLabels)',
    );
  }
  if (missingLabelTexts.isNotEmpty) {
    stderr.writeln('  missing label texts: ${missingLabelTexts.join(', ')}');
  }
  if (missingShaders.isNotEmpty) {
    stderr.writeln('  missing shaders: ${missingShaders.join(', ')}');
  }
  if (missingStencilModes.isNotEmpty) {
    stderr.writeln(
      '  missing stencil modes: ${missingStencilModes.join(', ')}',
    );
  }
  stderr.writeln('  report: ${coverageFile.path}');
  exitCode = 1;
}

/// Keys with a non-zero count. A zero would mean the path did not run.
Set<String> _names(Object? value) => switch (value) {
  final Map<String, Object?> map => <String>{
    for (final entry in map.entries)
      if (entry.value is num && (entry.value! as num) > 0) entry.key,
  },
  _ => <String>{},
};

Set<String> _required(Object? value) => switch (value) {
  final List<Object?> list => list.whereType<String>().toSet(),
  _ => <String>{},
};

Future<Map<String, Object?>?> _readJsonObject(
  File file, {
  required String description,
}) async {
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, Object?>) return decoded;
    stderr.writeln('$description is not a JSON object: ${file.path}');
  } on FormatException catch (error) {
    stderr.writeln('$description is not valid JSON: ${error.message}');
  }
  exitCode = 2;

  return null;
}

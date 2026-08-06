// Reports which render paths the captured frame actually exercised.
//
// A visual baseline proves that visible pixels did not change, but several
// paths are invisible by construction: a tile clipping mask writes only to the
// stencil buffer, and a mid-frame stencil clear draws nothing at all. Without
// this report, a refactor could delete those paths entirely and every
// screenshot would still match.
//
// The summary is written next to the screenshot so the runner can gate on it.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';
import 'package:maplibre_flutter_gpu/src/frame/frame_command_summary.dart';

/// Human-readable names so the report does not force the reader to map
/// integers back onto shader kinds by hand.
const _shaderNames = {
  ShaderType.fill: 'fill',
  ShaderType.fillOutline: 'fillOutline',
  ShaderType.line: 'line',
  ShaderType.background: 'background',
  ShaderType.fillExtrusion: 'fillExtrusion',
  ShaderType.lineSDF: 'lineSDF',
  ShaderType.lineGradient: 'lineGradient',
  ShaderType.linePattern: 'linePattern',
  ShaderType.circle: 'circle',
  ShaderType.raster: 'raster',
  ShaderType.fillOutlineTriangulated: 'fillOutlineTriangulated',
  ShaderType.clippingMask: 'clippingMask',
  ShaderType.backgroundPattern: 'backgroundPattern',
  ShaderType.unknown: 'unknown',
};

const _stencilModeNames = {
  StencilModeType.disabled: 'disabled',
  StencilModeType.clippingMask: 'clippingMask',
  StencilModeType.clippingTest: 'clippingTest',
  StencilModeType.fillExtrusion: 'fillExtrusion',
  StencilModeType.clear: 'clear',
};

/// Caps the text list so a label-heavy scene does not bloat the report.
const _maxReportedLabelTexts = 10;

/// Reads the current native frame and writes its command histogram to [path].
Future<void> writeVisualE2eCommandCoverage({
  required gpu.MapLibreMapController controller,
  required String path,
  required String scene,
}) async {
  final metadata = controller.bridge.frameGetMetadata();
  final commands = metadata.commands;
  final summary = commands == nullptr
      ? (
          commandCount: 0,
          countByShader: const <int, int>{},
          countByStencilMode: const <int, int>{},
        )
      : summarizeFrameCommands(
          commands: commands.cast<Uint8>().asTypedList(
            metadata.commandCount * metadata.commandStride,
          ),
          commandCount: metadata.commandCount,
          commandStride: metadata.commandStride,
          shaderTypeOffset: DrawCommandAbi.shaderType,
          stencilModeOffset: DrawCommandAbi.stencilMode,
          expectedStride: DrawCommandAbi.size,
        );

  String name(Map<int, String> names, int key) => names[key] ?? 'unknown($key)';

  // Labels never appear in the command stream: this backend renders text and
  // icons as Flutter widgets from the placement export, so a scene can be
  // fully correct with zero draw commands. Report them separately, or the
  // symbol path has no coverage signal at all.
  final labels = controller.getPlacedLabels();
  final report = {
    'scene': scene,
    'styleLoaded': controller.bridge.isStyleLoaded(),
    'missingNativeFeatures': controller.bridge.missingNativeFeatures.toList(),
    'mapIdle': controller.isMapIdle,
    'commandCount': summary.commandCount,
    'placedLabels': labels.length,
    // Sorted before truncating: the cap must select the same subset on every
    // run, or an expectation recorded from one run would fail the next.
    'placedLabelTexts':
        (labels
                .where((label) => label.text.isNotEmpty)
                .map((label) => label.text)
                .toSet()
                .toList()
              ..sort())
            .take(_maxReportedLabelTexts)
            .toList(),
    'shaders': <String, int>{
      for (final entry in summary.countByShader.entries)
        name(_shaderNames, entry.key): entry.value,
    },
    'stencilModes': <String, int>{
      for (final entry in summary.countByStencilMode.entries)
        name(_stencilModeNames, entry.key): entry.value,
    },
  };

  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    flush: true,
  );
}

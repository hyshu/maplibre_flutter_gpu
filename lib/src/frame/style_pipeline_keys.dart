import 'dart:convert';

import '../native/draw_command.dart';
import 'draw_flags.dart';
import 'pipeline_key.dart';

/// Returns the render pipelines a style can draw with, derived from its layers.
///
/// Data-driven paint is not visible from the layer definitions alone, so each
/// layer type contributes both its constant and its data-driven pipelines.
/// Symbol layers draw as Flutter widgets and contribute nothing. Malformed
/// style JSON yields an empty set.
Set<RenderPipelineKey> pipelineKeysForStyle(String styleJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(styleJson);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map<String, dynamic>) return const {};
  final layers = decoded['layers'];
  if (layers is! List) return const {};

  final keys = <RenderPipelineKey>{};
  var needsClippingMask = false;
  for (final layer in layers) {
    if (layer is! Map<String, dynamic>) continue;
    final paint = layer['paint'];
    final paintKeys = paint is Map<String, dynamic>
        ? paint.keys.toSet()
        : const <String>{};
    switch (layer['type']) {
      case 'background':
        keys.add(
          paintKeys.contains('background-pattern')
              ? RenderPipelineKey.backgroundPattern
              : pipelineKeyFor(shader: ShaderType.background, flags: 0),
        );
      case 'fill':
        needsClippingMask = true;
        for (final flags in [0, DrawCommandFlags.fillColorDataDriven]) {
          keys.add(pipelineKeyFor(shader: ShaderType.fill, flags: flags));
        }
        keys.add(pipelineKeyFor(shader: ShaderType.fillOutline, flags: 0));
        for (final flags in [0, DrawCommandFlags.fillOutlineColorDataDriven]) {
          keys.add(
            pipelineKeyFor(
              shader: ShaderType.fillOutlineTriangulated,
              flags: flags,
            ),
          );
        }
      case 'line':
        needsClippingMask = true;
        final shaders = [
          if (paintKeys.contains('line-pattern'))
            ShaderType.linePattern
          else if (paintKeys.contains('line-gradient'))
            ShaderType.lineGradient
          else if (paintKeys.contains('line-dasharray'))
            ShaderType.lineSDF
          else
            ShaderType.line,
        ];
        for (final shader in shaders) {
          for (final flags in [0, DrawCommandFlags.lineColorDataDriven]) {
            keys.add(pipelineKeyFor(shader: shader, flags: flags));
          }
        }
      case 'fill-extrusion':
        needsClippingMask = true;
        for (final flags in [0, DrawCommandFlags.fillExtrusionDataDriven]) {
          keys
            ..add(
              pipelineKeyFor(shader: ShaderType.fillExtrusion, flags: flags),
            )
            ..add(
              depthPipelineKeyFor(
                shader: ShaderType.fillExtrusion,
                flags: flags,
              )!,
            );
        }
      case 'circle':
        needsClippingMask = true;
        for (final flags in [0, DrawCommandFlags.circleColorDataDriven]) {
          keys.add(pipelineKeyFor(shader: ShaderType.circle, flags: flags));
        }
      case 'heatmap':
        for (final flags in [0, DrawCommandFlags.heatmapWeightDataDriven]) {
          keys.add(pipelineKeyFor(shader: ShaderType.heatmap, flags: flags));
        }
        keys.add(pipelineKeyFor(shader: ShaderType.heatmapTexture, flags: 0));
      case 'hillshade':
        needsClippingMask = true;
        keys
          ..add(pipelineKeyFor(shader: ShaderType.hillshadePrepare, flags: 0))
          ..add(pipelineKeyFor(shader: ShaderType.hillshade, flags: 0));
      case 'raster':
        needsClippingMask = true;
        keys.add(pipelineKeyFor(shader: ShaderType.raster, flags: 0));
    }
  }
  if (needsClippingMask) {
    keys.add(pipelineKeyFor(shader: ShaderType.clippingMask, flags: 0));
  }

  return keys;
}

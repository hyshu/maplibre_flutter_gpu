import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('command export skips unsupported native symbol drawables', () {
    final symbolLayer = File(
      'vendor/maplibre-native/src/mbgl/renderer/layers/render_symbol_layer.cpp',
    ).readAsStringSync();
    final commandDrawable = File(
      'vendor/maplibre-native/src/mbgl/command_export/drawable.cpp',
    ).readAsStringSync();

    expect(
      commandDrawable,
      contains(
        'shaderTypeFromProgramName("SymbolIconShader") == '
        'ShaderType::Unknown',
      ),
    );
    expect(
      commandDrawable,
      contains(
        'shaderTypeFromProgramName("SymbolSDFShader") == '
        'ShaderType::Unknown',
      ),
    );
    expect(
      commandDrawable,
      contains(
        'shaderTypeFromProgramName("SymbolTextAndIconShader") == '
        'ShaderType::Unknown',
      ),
    );

    final commandMarker = symbolLayer.indexOf(
      '// Command Export exposes symbols through placement data',
    );
    expect(commandMarker, greaterThan(0));
    final commandStart = symbolLayer.lastIndexOf(
      '#if MLN_RENDER_BACKEND_COMMAND_EXPORT',
      commandMarker,
    );
    final standardStart = symbolLayer.indexOf('#else', commandMarker);
    final branchEnd = symbolLayer.indexOf('#endif', standardStart);
    final commandBranch = symbolLayer.substring(commandStart, standardStart);
    final standardBranch = symbolLayer.substring(standardStart, branchEnd);

    expect(
      commandBranch,
      contains('collisionTileLayerGroup->removeDrawables(passes, tileID)'),
    );
    expect(commandBranch, contains('addCollisionDrawables(false'));
    expect(commandBranch, contains('addCollisionDrawables(true'));
    expect(commandBranch, isNot(contains('updateTile(')));
    expect(commandBranch, isNot(contains('addRenderables(')));
    expect(standardBranch, contains('updateTile('));
    expect(standardBranch, contains('addRenderables('));
  });

  test('symbol placement and paint evaluation stay backend independent', () {
    final symbolLayer = File(
      'vendor/maplibre-native/src/mbgl/renderer/layers/render_symbol_layer.cpp',
    ).readAsStringSync();

    final prepareStart = symbolLayer.indexOf(
      'void RenderSymbolLayer::prepare(',
    );
    final prepareEnd = symbolLayer.indexOf('\n}\n\nnamespace {', prepareStart);
    final prepareBody = symbolLayer.substring(prepareStart, prepareEnd);
    final evaluateStart = symbolLayer.indexOf(
      'void RenderSymbolLayer::evaluate(',
    );
    final evaluateEnd = symbolLayer.indexOf(
      'bool RenderSymbolLayer::hasTransition()',
      evaluateStart,
    );
    final evaluateBody = symbolLayer.substring(evaluateStart, evaluateEnd);

    expect(prepareBody, contains('placementData.clear()'));
    expect(prepareBody, contains('placementData.push_back('));
    expect(prepareBody, isNot(contains('MLN_RENDER_BACKEND_COMMAND_EXPORT')));
    expect(evaluateBody, contains('unevaluated.evaluate(parameters'));
    expect(evaluateBody, isNot(contains('MLN_RENDER_BACKEND_COMMAND_EXPORT')));
  });
}

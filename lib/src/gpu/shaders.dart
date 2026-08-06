import 'package:flutter_gpu/gpu.dart' as gpu;

gpu.ShaderLibrary? _mapShaderLibrary;

/// Package asset path of the compiled map shader bundle.
const _shaderBundleAsset =
    'packages/maplibre_flutter_gpu/build/shaderbundles/MapShaders.shaderbundle';

/// Loads the map shader library on first access and reuses it thereafter.
///
/// Throws an [Exception] when the shader bundle cannot be loaded.
gpu.ShaderLibrary get mapShaderLibrary {
  _mapShaderLibrary ??= gpu.ShaderLibrary.fromAsset(_shaderBundleAsset);
  if (_mapShaderLibrary == null) {
    throw Exception(
      'Failed to load MapShaders bundle from $_shaderBundleAsset',
    );
  }
  return _mapShaderLibrary!;
}

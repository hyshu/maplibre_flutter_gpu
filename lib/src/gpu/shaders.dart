import 'package:flutter_gpu/gpu.dart' as gpu;

/// Package asset path of the compiled map shader bundle.
const _shaderBundleAsset =
    'packages/maplibre_flutter_gpu/assets/shaderbundles/MapShaders.shaderbundle';

/// Loads the map shader library.
///
/// Throws an [Exception] when the shader bundle cannot be loaded.
Future<gpu.ShaderLibrary> loadMapShaderLibrary() async {
  final library = await gpu.ShaderLibrary.fromAsset(_shaderBundleAsset);
  if (library == null) {
    throw Exception(
      'Failed to load MapShaders bundle from $_shaderBundleAsset',
    );
  }

  return library;
}

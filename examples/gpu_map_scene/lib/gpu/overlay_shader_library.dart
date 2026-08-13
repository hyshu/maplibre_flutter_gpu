import 'package:flutter_gpu/gpu.dart' as gpu;

const _overlayShaderAsset = 'assets/shaderbundles/OverlayShaders.shaderbundle';

Future<gpu.ShaderLibrary> loadOverlayShaderLibrary() async {
  final library = await gpu.ShaderLibrary.fromAsset(_overlayShaderAsset);
  if (library == null) {
    throw StateError('Unable to load $_overlayShaderAsset');
  }

  return library;
}

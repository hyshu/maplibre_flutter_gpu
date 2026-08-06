import 'package:flutter_gpu/gpu.dart' as gpu;

const _overlayShaderAsset = 'assets/shaderbundles/OverlayShaders.shaderbundle';

gpu.ShaderLibrary? _overlayShaderLibrary;

gpu.ShaderLibrary get overlayShaderLibrary {
  final cached = _overlayShaderLibrary;
  if (cached != null) return cached;

  final loaded = gpu.ShaderLibrary.fromAsset(_overlayShaderAsset);
  if (loaded == null) {
    throw StateError('Unable to load $_overlayShaderAsset');
  }
  return _overlayShaderLibrary = loaded;
}

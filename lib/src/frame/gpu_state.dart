// Flutter GPU pipeline state translated from MapLibre's resolved render state.
// Includes stencil configs, the premultiplied blend equation, and texture
// samplers.
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../native/draw_command.dart';

import 'package:vector_math/vector_math.dart' as vector_math;

import '../native/maplibre_ffi.dart' show FrameClearColor;

// Flutter GPU exposes these value carriers as mutable classes, but each
// RenderPass call copies their fields immediately. Keep the shared instances
// private and read-only so hot draws do not allocate equivalent descriptors.
final gpu.StencilConfig _disabledStencilConfig = gpu.StencilConfig(
  compareFunction: gpu.CompareFunction.always,
  stencilFailureOperation: gpu.StencilOperation.keep,
  depthFailureOperation: gpu.StencilOperation.keep,
  depthStencilPassOperation: gpu.StencilOperation.keep,
  readMask: 0xff,
  writeMask: 0x00,
);
final gpu.StencilConfig _clippingMaskStencilConfig = gpu.StencilConfig(
  compareFunction: gpu.CompareFunction.always,
  stencilFailureOperation: gpu.StencilOperation.keep,
  depthFailureOperation: gpu.StencilOperation.keep,
  depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
  readMask: 0xff,
  writeMask: 0xff,
);
final gpu.StencilConfig _clippingTestStencilConfig = gpu.StencilConfig(
  compareFunction: gpu.CompareFunction.equal,
  stencilFailureOperation: gpu.StencilOperation.keep,
  depthFailureOperation: gpu.StencilOperation.keep,
  depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
  readMask: 0xff,
  writeMask: 0x00,
);
final gpu.StencilConfig _fillExtrusionStencilConfig = gpu.StencilConfig(
  compareFunction: gpu.CompareFunction.notEqual,
  stencilFailureOperation: gpu.StencilOperation.keep,
  depthFailureOperation: gpu.StencilOperation.keep,
  depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
  readMask: 0xff,
  writeMask: 0xff,
);

/// Returns the Flutter GPU stencil configuration for [mode].
///
/// Throws a [StateError] when [mode] has no drawable configuration.
gpu.StencilConfig stencilConfigFor(int mode) => switch (mode) {
  StencilModeType.disabled => _disabledStencilConfig,
  StencilModeType.clippingMask => _clippingMaskStencilConfig,
  StencilModeType.clippingTest => _clippingTestStencilConfig,
  StencilModeType.fillExtrusion => _fillExtrusionStencilConfig,
  _ => throw StateError('No draw config for stencil mode $mode'),
};

/// Blend equation used by MapLibre's alpha-blended drawables. MapLibre colors,
/// sampled textures, and shader outputs are premultiplied.
final gpu.ColorBlendEquation _premultipliedAlphaBlendEquation =
    gpu.ColorBlendEquation(
      sourceColorBlendFactor: gpu.BlendFactor.one,
      destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      sourceAlphaBlendFactor: gpu.BlendFactor.one,
      destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
    );

/// Returns the premultiplied-alpha blend equation used by MapLibre drawables.
gpu.ColorBlendEquation premultipliedAlphaBlendEquation() =>
    _premultipliedAlphaBlendEquation;

/// Texture sampling convention for line pipelines. Dash atlases repeat along
/// the line (U) while gradient ramps and sprite atlases clamp at their edges.
final gpu.SamplerOptions _repeatingLinearSampler = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.repeat,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);
final gpu.SamplerOptions _linearSampler = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);
final gpu.SamplerOptions _nearestSampler = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// Returns the sampler used by a line-family shader.
///
/// [ShaderType.lineSDF] repeats its dash atlas along the line. Other line
/// shaders use linear sampling with clamped edges.
gpu.SamplerOptions lineSamplerOptions(int shaderType) =>
    shaderType == ShaderType.lineSDF ? _repeatingLinearSampler : _linearSampler;

/// MapLibre pattern atlases are sampled linearly inside their packed sprite
/// rectangles. Atlas edges clamp rather than repeating neighboring sprites.
gpu.SamplerOptions patternAtlasSamplerOptions() => _linearSampler;

/// The sampler a shader's texture slot is bound with.
///
/// One entry point so the binder does not have to know which convention each
/// texture-backed shader follows. [textureFilter] is only read by raster.
gpu.SamplerOptions samplerOptionsFor(int shader, int textureFilter) =>
    switch (shader) {
      ShaderType.raster => rasterSamplerOptions(textureFilter),
      ShaderType.backgroundPattern => patternAtlasSamplerOptions(),
      _ => lineSamplerOptions(shader),
    };

/// Texture sampling configured by MapLibre's raster-resampling property.
/// Unknown values use the style property's default linear sampling.
gpu.SamplerOptions rasterSamplerOptions(int textureFilter) =>
    textureFilter == TextureFilterType.nearest
    ? _nearestSampler
    : _linearSampler;

/// The render target's clear color, defaulting to fully transparent.
///
/// A style with no background layer reports no clear color. Clearing to opaque
/// black would hide content behind the map.
vector_math.Vector4 frameClearValue(FrameClearColor? color) =>
    vector_math.Vector4(
      color?.red ?? 0.0,
      color?.green ?? 0.0,
      color?.blue ?? 0.0,
      color?.alpha ?? 0.0,
    );

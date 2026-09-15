import 'dart:ui' as dart_ui show Image;

import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vector_math;

import '../../frame/gpu_state.dart';
import '../../native/maplibre_ffi.dart' show FrameClearColor;

/// Owns GPU images and cached values reused between painted frames.
class MapGpuResources {
  /// Most recently completed image available for display.
  dart_ui.Image? lastImage;

  /// Last frame sequence handled by the painter.
  var lastPaintedSeq = -1;

  /// Last native snapshot generation recorded into a texture.
  var lastPaintedGeneration = -1;

  /// Render target textures owned by this resource set.
  final textures = <gpu.Texture>[];

  /// Flutter images backed by [textures].
  final images = <dart_ui.Image>[];

  /// Current physical texture width in pixels.
  var width = 0;

  /// Current physical texture height in pixels.
  var height = 0;

  /// Index of the texture currently displayed by [lastImage].
  var displayIndex = -1;

  /// Whether the previous frame included a custom GPU callback.
  var hadGpuRenderCallback = false;

  /// Paint used to copy [lastImage] onto the Flutter canvas.
  final imagePaint = Paint();
  Rect? _sourceRect;
  var _sourceWidth = 0;
  var _sourceHeight = 0;
  Rect? _destinationRect;
  var _destinationSize = Size.zero;
  FrameClearColor? _clearColor;
  vector_math.Vector4? _frameClearValue;
  var _hasStratumRange = false;
  int? _minimumLayerIndex;
  int? _maximumLayerIndex;
  var _clearToTransparent = false;

  /// Assigns this resource set to one compositing range.
  ///
  /// Range changes invalidate the displayed frame but retain GPU textures.
  void assignStratumRange({
    required int? minimumLayerIndex,
    required int? maximumLayerIndex,
    required bool clearToTransparent,
  }) {
    if (_hasStratumRange &&
        _minimumLayerIndex == minimumLayerIndex &&
        _maximumLayerIndex == maximumLayerIndex &&
        _clearToTransparent == clearToTransparent) {
      return;
    }
    _hasStratumRange = true;
    _minimumLayerIndex = minimumLayerIndex;
    _maximumLayerIndex = maximumLayerIndex;
    _clearToTransparent = clearToTransparent;
    hideLastImage();
    lastPaintedSeq = -1;
    lastPaintedGeneration = -1;
    hadGpuRenderCallback = false;
  }

  /// Returns the cached source rectangle for [image].
  Rect sourceRect(dart_ui.Image image) {
    if (_sourceRect == null ||
        _sourceWidth != image.width ||
        _sourceHeight != image.height) {
      _sourceWidth = image.width;
      _sourceHeight = image.height;
      _sourceRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
    }
    return _sourceRect!;
  }

  /// Returns the cached destination rectangle for [size].
  Rect destinationRect(Size size) {
    if (_destinationRect == null || _destinationSize != size) {
      _destinationSize = size;
      _destinationRect = Rect.fromLTWH(0, 0, size.width, size.height);
    }
    return _destinationRect!;
  }

  /// Returns the cached GPU clear value for [color].
  vector_math.Vector4 cachedFrameClearValue(FrameClearColor? color) {
    if (_frameClearValue == null || _clearColor != color) {
      _clearColor = color;
      _frameClearValue = frameClearValue(color);
    }
    return _frameClearValue!;
  }

  /// Recreates owned resources when the physical size changes.
  void resize(int nextWidth, int nextHeight) {
    if (width == nextWidth && height == nextHeight) return;
    dispose();
    width = nextWidth;
    height = nextHeight;
  }

  /// Hides the previous surface while retaining its textures for reuse.
  void hideLastImage() {
    lastImage = null;
    displayIndex = -1;
  }

  /// Releases owned images and resets all cached frame state.
  void dispose() {
    for (final image in images) {
      image.dispose();
    }
    textures.clear();
    images.clear();
    lastImage = null;
    lastPaintedSeq = -1;
    lastPaintedGeneration = -1;
    displayIndex = -1;
    hadGpuRenderCallback = false;
    _sourceRect = null;
    _sourceWidth = 0;
    _sourceHeight = 0;
    _destinationRect = null;
    _destinationSize = .zero;
    _clearColor = null;
    _frameClearValue = null;
    _hasStratumRange = false;
    _minimumLayerIndex = null;
    _maximumLayerIndex = null;
    _clearToTransparent = false;
    width = 0;
    height = 0;
  }
}

/// Retains render targets by compositing slot while layer ranges change.
class MapGpuResourcePool {
  final _slots = <MapGpuResources>[];

  /// Number of allocated slots retained for reuse.
  @visibleForTesting
  int get length => _slots.length;

  /// Returns the resources assigned to [slot].
  MapGpuResources acquire(
    int slot, {
    required int? minimumLayerIndex,
    required int? maximumLayerIndex,
    required bool clearToTransparent,
  }) {
    assert(slot >= 0);
    while (_slots.length <= slot) {
      _slots.add(.new());
    }
    final resources = _slots[slot];
    resources.assignStratumRange(
      minimumLayerIndex: minimumLayerIndex,
      maximumLayerIndex: maximumLayerIndex,
      clearToTransparent: clearToTransparent,
    );

    return resources;
  }

  /// Releases retained slots at or above [activeSlotCount].
  ///
  /// Active slots form a prefix and keep their identity. Call this after every
  /// active slot has been acquired for the current composition.
  void trimToActiveSlotCount(int activeSlotCount) {
    RangeError.checkValueInInterval(
      activeSlotCount,
      0,
      _slots.length,
      'activeSlotCount',
    );
    while (_slots.length > activeSlotCount) {
      final resources = _slots.removeLast();
      resources.dispose();
    }
  }

  /// Releases every retained render target.
  void dispose() {
    for (final resources in _slots) {
      resources.dispose();
    }
    _slots.clear();
  }
}

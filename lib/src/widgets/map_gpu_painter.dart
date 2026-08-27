import 'dart:ui' as dart_ui show Image;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vector_math;

import '../frame/gpu_state.dart';
import '../gpu/pass_executor.dart';
import '../gpu/render_context.dart';
import '../gpu/renderer.dart';
import '../native/maplibre_ffi.dart';

/// Whether one stratum needs a render target for the current native frame.
@visibleForTesting
bool gpuStratumNeedsSurface({
  required bool clearToTransparent,
  required bool hasNativeCommands,
  required bool hasGpuCallback,
}) => !clearToTransparent || hasNativeCommands || hasGpuCallback;

/// Paints native MapLibre frames and optional GPU callbacks onto a canvas.
class MapGpuPainter({
  /// Native bridge that supplies frame metadata and map transforms.
  required final MaplibreBridge bridge,

  /// Renderer that records MapLibre draw commands.
  required final GpuFrameRenderer gpuRenderer,

  /// Reusable textures, images, and derived frame values.
  required final MapGpuResources resources,

  /// Physical output width in pixels.
  required final int width,

  /// Physical output height in pixels.
  required final int height,

  /// Logical output width in pixels.
  required final int logicalWidth,

  /// Logical output height in pixels.
  required final int logicalHeight,

  /// Ratio between physical and logical pixels.
  required final double devicePixelRatio,

  /// Sequence number used to identify the requested frame.
  required final int frameSeq,

  /// Callback that records custom drawing in map coordinates.
  required final MapLibreGpuRenderCallback? gpuMapRenderCallback,

  /// Callback that records an overlay after the map.
  required final MapLibreGpuRenderCallback? gpuRenderCallback,

  /// Depth and stencil behavior used by [gpuRenderCallback].
  required final MapLibreGpuDepthMode gpuOverlayDepthMode,

  /// Reports whether the current application state permits GPU rendering.
  required final bool Function() gpuRenderingAllowed,

  /// Acquires the native frame snapshot available for painting.
  required final NativeFrameSnapshotLease? Function() frameSnapshotProvider,

  /// Receives a snapshot after its native lease has been released.
  required final ValueChanged<NativeFrameSnapshotLease>?
  onFrameSnapshotReleased,

  /// Position of this painter in [layerRanges].
  required final int stratumIndex,

  /// Ordered layer partitions shared by every painter in the frame.
  required final List<GpuStyleLayerRange> layerRanges,

  /// First native style layer rendered by this painter, inclusive.
  final int? minimumLayerIndex,

  /// First native style layer omitted by this painter, exclusive.
  final int? maximumLayerIndex,

  /// Whether this stratum starts transparent instead of using map clear color.
  final bool clearToTransparent = false,

  /// Whether this painter releases the shared native frame snapshot.
  final bool releaseFrameSnapshot = true,

  /// Whether this stratum advances the renderer's shared resource frame.
  final bool advanceResourceFrame = true,

  /// Whether this stratum runs cache eviction after recording.
  final bool evictResourceCaches = true,
  super.repaint,
}) extends CustomPainter {
  @override
  void paint(canvas, size) {
    // Preserve the pending native frame while GPU rendering is unavailable.
    if (!gpuRenderingAllowed()) {
      if (evictResourceCaches) gpuRenderer.finishFrame();
      _drawLastImage(canvas, size);

      return;
    }
    if (advanceResourceFrame) gpuRenderer.beginFrameReplay();
    final currentFrameSeq = gpuRenderer.frameSeq;
    final submitEachRenderPass =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    NativeFrameSnapshotLease? snapshot;
    try {
      snapshot = frameSnapshotProvider();
      if (currentFrameSeq != resources.lastPaintedSeq ||
          gpuMapRenderCallback != null ||
          gpuRenderCallback != null ||
          resources.hadGpuRenderCallback ||
          (snapshot?.isActive ?? false)) {
        final usesAsyncSnapshots = bridge.supportsAsyncRendering;
        final acquiredGeneration = snapshot?.isActive ?? false
            ? snapshot!.generation
            : 0;
        final hasReadableSnapshot =
            !usesAsyncSnapshots || acquiredGeneration != 0;
        if (hasReadableSnapshot) {
          final frameMetadata = bridge.frameGetMetadata();
          final preparedFrame = gpuRenderer.prepareFrame(
            frameMetadata: frameMetadata,
            physicalWidth: width,
            physicalHeight: height,
            logicalWidth: logicalWidth.toDouble(),
            logicalHeight: logicalHeight.toDouble(),
            devicePixelRatio: devicePixelRatio,
            layerRanges: layerRanges,
            advanceResourceFrame: advanceResourceFrame,
          );
          final hasGpuCallback =
              gpuMapRenderCallback != null || gpuRenderCallback != null;
          final needsSurface = gpuStratumNeedsSurface(
            clearToTransparent: clearToTransparent,
            hasNativeCommands: preparedFrame.hasCommandsInStratum(stratumIndex),
            hasGpuCallback: hasGpuCallback,
          );
          if (!needsSurface) {
            resources.hideLastImage();
            resources.lastPaintedGeneration = acquiredGeneration;
            resources.hadGpuRenderCallback = false;
          } else {
            resources.resize(width, height);
            final snapshotChanged =
                !usesAsyncSnapshots ||
                acquiredGeneration != resources.lastPaintedGeneration;
            final mustRecord =
                snapshotChanged ||
                hasGpuCallback ||
                resources.hadGpuRenderCallback;
            if (mustRecord) {
              var targetTextureIndex = -1;
              for (
                var candidateIndex = 0;
                candidateIndex < resources.textures.length;
                candidateIndex += 1
              ) {
                if (candidateIndex != resources.displayIndex) {
                  targetTextureIndex = candidateIndex;
                  break;
                }
              }
              if (targetTextureIndex < 0) {
                final created = gpu.gpuContext.createTexture(
                  gpu.StorageMode.devicePrivate,
                  width,
                  height,
                  enableRenderTargetUsage: true,
                  enableShaderReadUsage: true,
                );
                resources.textures.add(created);
                resources.images.add(created.asImage());
                targetTextureIndex = resources.textures.length - 1;
              }
              final texture = resources.textures[targetTextureIndex];
              // Resolve the map transform only when a GPU callback can use it.
              final mapTransform = hasGpuCallback
                  ? _toGpuMapTransform(bridge.frameGetMapTransform())
                  : null;
              final clearColor = clearToTransparent
                  ? null
                  : frameMetadata.clearColor;
              var depthStencilTexture = gpuRenderer.prepareDepthStencilTexture(
                texture,
              );
              late gpu.CommandBuffer commandBuffer;
              while (true) {
                commandBuffer = gpu.gpuContext.createCommandBuffer();
                try {
                  gpuRenderer.renderPreparedFrame(
                    preparedFrame: preparedFrame,
                    stratumIndex: stratumIndex,
                    commandBuffer: commandBuffer,
                    texture: texture,
                    frameClearColor: resources.cachedFrameClearValue(
                      clearColor,
                    ),
                    submitEachRenderPass: submitEachRenderPass,
                    initialDepthStencilTexture: depthStencilTexture,
                    gpuMapRenderCallback: gpuMapRenderCallback,
                    mapTransform: mapTransform,
                  );
                  break;
                } on DepthStencilAttachmentError catch (error) {
                  if (depthStencilTexture == null) rethrow;
                  gpuRenderer.disableDepthStencil(error.cause);
                  depthStencilTexture = null;
                }
              }
              try {
                if (submitEachRenderPass && gpuRenderCallback != null) {
                  commandBuffer = gpu.gpuContext.createCommandBuffer();
                }
                _renderGpuOverlay(
                  commandBuffer,
                  texture,
                  depthStencilTexture,
                  mapTransform,
                );
              } catch (e, st) {
                debugPrint('[MapLibreMap] GPU overlay pass error: $e\n$st');
              }
              if (!submitEachRenderPass || gpuRenderCallback != null) {
                commandBuffer.submit();
              }

              resources.lastImage = resources.images[targetTextureIndex];
              resources.displayIndex = targetTextureIndex;
              resources.lastPaintedGeneration = acquiredGeneration;
              resources.hadGpuRenderCallback = hasGpuCallback;
            }
          }
          // Mark the sequence handled without replaying the native frame.
          resources.lastPaintedSeq = currentFrameSeq;
        }
      }
    } catch (e) {
      debugPrint('[MapLibreMap] paint error: $e');
    } finally {
      final activeSnapshot = snapshot;
      if (releaseFrameSnapshot &&
          activeSnapshot != null &&
          activeSnapshot.isActive) {
        try {
          activeSnapshot.release();
        } finally {
          onFrameSnapshotReleased?.call(activeSnapshot);
        }
      }
      if (evictResourceCaches) gpuRenderer.finishFrame();
    }

    _drawLastImage(canvas, size);
  }

  /// Draws the most recently completed frame when one is available.
  void _drawLastImage(Canvas canvas, Size size) {
    final image = resources.lastImage;
    if (image != null) {
      canvas.drawImageRect(
        image,
        resources.sourceRect(image),
        resources.destinationRect(size),
        resources.imagePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MapGpuPainter oldDelegate) =>
      frameSeq != oldDelegate.frameSeq ||
      width != oldDelegate.width ||
      height != oldDelegate.height ||
      logicalWidth != oldDelegate.logicalWidth ||
      logicalHeight != oldDelegate.logicalHeight ||
      devicePixelRatio != oldDelegate.devicePixelRatio ||
      gpuMapRenderCallback != oldDelegate.gpuMapRenderCallback ||
      gpuRenderCallback != oldDelegate.gpuRenderCallback ||
      gpuOverlayDepthMode != oldDelegate.gpuOverlayDepthMode ||
      gpuRenderingAllowed != oldDelegate.gpuRenderingAllowed ||
      frameSnapshotProvider != oldDelegate.frameSnapshotProvider ||
      onFrameSnapshotReleased != oldDelegate.onFrameSnapshotReleased ||
      minimumLayerIndex != oldDelegate.minimumLayerIndex ||
      maximumLayerIndex != oldDelegate.maximumLayerIndex ||
      stratumIndex != oldDelegate.stratumIndex ||
      !listEquals(layerRanges, oldDelegate.layerRanges) ||
      clearToTransparent != oldDelegate.clearToTransparent ||
      releaseFrameSnapshot != oldDelegate.releaseFrameSnapshot ||
      advanceResourceFrame != oldDelegate.advanceResourceFrame ||
      evictResourceCaches != oldDelegate.evictResourceCaches ||
      resources != oldDelegate.resources ||
      gpuRenderer != oldDelegate.gpuRenderer ||
      bridge != oldDelegate.bridge;

  /// Records the configured GPU overlay after the map render pass.
  void _renderGpuOverlay(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture texture,
    gpu.Texture? depthStencilTexture,
    MapLibreGpuMapTransform? mapTransform,
  ) {
    final callback = gpuRenderCallback;
    if (callback == null) return;

    gpu.RenderTarget renderTarget(gpu.Texture? depthStencil) =>
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: texture,
            loadAction: gpu.LoadAction.load,
          ),
          depthStencilAttachment: depthStencil == null
              ? null
              : gpu.DepthStencilAttachment(
                  texture: depthStencil,
                  depthLoadAction:
                      gpuOverlayDepthMode == MapLibreGpuDepthMode.isolated
                      ? gpu.LoadAction.clear
                      : gpu.LoadAction.load,
                  depthStoreAction: gpu.StoreAction.store,
                  depthClearValue: 1.0,
                  stencilLoadAction:
                      gpuOverlayDepthMode == MapLibreGpuDepthMode.isolated
                      ? gpu.LoadAction.clear
                      : gpu.LoadAction.load,
                  stencilStoreAction: gpu.StoreAction.store,
                  stencilClearValue: 0,
                ),
        );

    late gpu.RenderPass renderPass;
    var sharedDepthStencil = depthStencilTexture;
    try {
      renderPass = commandBuffer.createRenderPass(
        renderTarget(sharedDepthStencil),
      );
    } catch (error) {
      if (sharedDepthStencil == null) rethrow;
      debugPrint(
        '[MapLibreMap] GPU overlay depth unavailable. '
        'Using a color-only pass. $error',
      );
      sharedDepthStencil = null;
      renderPass = commandBuffer.createRenderPass(renderTarget(null));
    }

    try {
      callback(
        MapLibreGpuRenderContext(
          gpuContext: gpu.gpuContext,
          renderPass: renderPass,
          logicalSize: Size(logicalWidth.toDouble(), logicalHeight.toDouble()),
          physicalSize: Size(width.toDouble(), height.toDouble()),
          devicePixelRatio: devicePixelRatio,
          frameSequence: frameSeq,
          mapTransform: mapTransform,
          hasDepthStencilAttachment: sharedDepthStencil != null,
          depthMode: gpuOverlayDepthMode,
        ),
      );
    } catch (e, st) {
      debugPrint('[MapLibreMap] gpuRenderCallback error: $e\n$st');
    }
  }

  /// Converts a native frame transform for use by public GPU callbacks.
  static MapLibreGpuMapTransform? _toGpuMapTransform(
    FrameMapTransform? transform,
  ) => transform == null
      ? null
      : MapLibreGpuMapTransform(
          viewProjectionMatrix: transform.viewProjectionMatrix,
          worldSize: transform.worldSize,
          originX: transform.originX,
          originY: transform.originY,
          zoom: transform.zoom,
        );
}

/// Owns GPU images and cached values reused between painted frames.
class MapGpuResources {
  /// Most recently completed image available for display.
  dart_ui.Image? lastImage;

  /// Last frame sequence handled by the painter.
  int lastPaintedSeq = -1;

  /// Last native snapshot generation recorded into a texture.
  int lastPaintedGeneration = -1;

  /// Render target textures owned by this resource set.
  final List<gpu.Texture> textures = [];

  /// Flutter images backed by [textures].
  final List<dart_ui.Image> images = [];

  /// Current physical texture width in pixels.
  var width = 0;

  /// Current physical texture height in pixels.
  var height = 0;

  /// Index of the texture currently displayed by [lastImage].
  var displayIndex = -1;

  /// Whether the previous frame included a custom GPU callback.
  var hadGpuRenderCallback = false;

  /// Paint used to copy [lastImage] onto the Flutter canvas.
  final Paint imagePaint = Paint();
  Rect? _sourceRect;
  var _sourceWidth = 0;
  var _sourceHeight = 0;
  Rect? _destinationRect;
  Size _destinationSize = Size.zero;
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
    _destinationSize = Size.zero;
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
  final List<MapGpuResources> _slots = <MapGpuResources>[];

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
      _slots.add(MapGpuResources());
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

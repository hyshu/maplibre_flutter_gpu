import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame/ubo_abi.dart';
import '../frame/uniform_packer.dart';
import '../native/draw_command.dart';
import 'draw_entry.dart';

/// Values mirrored from MapLibre's `GlobalPaintParamsUBO` for shaders that
/// need viewport-space calculations.
///
/// `units_to_pixels` uses the logical map size. `world_size` uses the physical
/// render target size.
@visibleForTesting
({double unitsX, double unitsY, double worldWidth, double worldHeight})
mapGlobalUniformValues({
  required double logicalWidth,
  required double logicalHeight,
  required int physicalWidth,
  required int physicalHeight,
}) => (
  unitsX: logicalWidth / 2.0,
  unitsY: -logicalHeight / 2.0,
  worldWidth: physicalWidth.toDouble(),
  worldHeight: physicalHeight.toDouble(),
);

/// Packs frame uniforms and retains their bounded GPU upload ring.
final class GpuFrameUniforms {
  gpu.HostBuffer? _uniformHost;
  var _uniformBytes = Uint8List(0);
  var _uniformData = ByteData(0);
  var _uniformUploadData = ByteData(0);
  var _uniformUploadLength = 0;

  /// Starts an upload generation after all strata finish the previous frame.
  void beginFrame() {
    final uniformHost = _uniformHost;
    if (uniformHost == null) {
      _uniformHost = gpu.gpuContext.createHostBuffer();
    } else {
      uniformHost.reset();
    }
  }

  /// Whether draw entries may retain views of an upload of [uniformLength].
  ///
  /// Call after [beginFrame] initializes the upload ring.
  bool canRetainViews(int uniformLength) =>
      uniformLength <= _uniformHost!.blockLengthInBytes;

  /// Releases CPU staging storage and the GPU upload ring.
  void dispose() {
    _uniformHost = null;
    _uniformBytes = Uint8List(0);
    _uniformData = ByteData(0);
    _uniformUploadData = ByteData(0);
    _uniformUploadLength = 0;
  }

  /// Writes every UBO the frame binds into the staging buffer.
  ///
  /// The returned view uses reusable staging storage. Only [layout.totalBytes]
  /// bytes belong to this frame. A later call may overwrite them.
  ByteData pack(
    FrameUniformLayout layout, {
    required List<DrawEntry> entries,
    required Uint8List commandBytes,
    required ByteData commandData,
    required double devicePixelRatio,
    required int physicalWidth,
    required int physicalHeight,
    required double logicalWidth,
    required double logicalHeight,
    required bool hasMapGlobal,
  }) {
    final mapGlobalOffset = layout.mapGlobalOffset;
    final uniformLength = layout.totalBytes;
    final dpr = devicePixelRatio;
    if (_uniformBytes.length < uniformLength) {
      _uniformBytes = Uint8List((uniformLength * 1.5).toInt());
      _uniformData = ByteData.sublistView(_uniformBytes);
      _uniformUploadLength = 0;
    }
    final uniformData = _uniformData;
    if (hasMapGlobal) {
      final global = mapGlobalUniformValues(
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        physicalWidth: physicalWidth,
        physicalHeight: physicalHeight,
      );
      uniformData.setFloat32(
        mapGlobalOffset + RendererUboAbi.mapGlobalUnitsXOffset,
        global.unitsX,
        Endian.little,
      );
      uniformData.setFloat32(
        mapGlobalOffset + RendererUboAbi.mapGlobalUnitsYOffset,
        global.unitsY,
        Endian.little,
      );
      uniformData.setFloat32(
        mapGlobalOffset + RendererUboAbi.mapGlobalWorldWidthOffset,
        global.worldWidth,
        Endian.little,
      );
      uniformData.setFloat32(
        mapGlobalOffset + RendererUboAbi.mapGlobalWorldHeightOffset,
        global.worldHeight,
        Endian.little,
      );
    }
    for (final entry in entries) {
      if (entry.stencilMode == StencilModeType.clear) continue;
      final commandTexture = entry.texture;
      packCommandUniforms(
        source: commandBytes,
        sourceData: commandData,
        commandOffset: entry.commandOffset,
        destination: _uniformBytes,
        destinationData: uniformData,
        shader: entry.shader,
        flags: entry.flags,
        drawableOffset: entry.drawableUniformOffset,
        drawableLength: entry.drawableUniformLength,
        propsOffset: entry.propsUniformOffset,
        propsLength: entry.propsUniformLength,
        tilePropsOffset: entry.tilePropsUniformOffset,
        tilePropsLength: entry.tilePropsUniformLength,
        devicePixelRatio: dpr,
        textureWidth: commandTexture?.width ?? 0,
        textureHeight: commandTexture?.height ?? 0,
      );
    }
    return uniformData;
  }

  /// Uploads the bytes written by [pack] after [beginFrame] starts their frame.
  gpu.DeviceBuffer upload(int uniformLength) {
    if (_uniformUploadLength != uniformLength) {
      _uniformUploadData = ByteData.sublistView(
        _uniformBytes,
        0,
        uniformLength,
      );
      _uniformUploadLength = uniformLength;
    }
    final uniformBytes = _uniformUploadData;
    final uniformHost = _uniformHost!;
    if (uniformLength <= uniformHost.blockLengthInBytes) {
      final uniformView = uniformHost.emplace(uniformBytes);
      assert(uniformView.offsetInBytes == 0);

      return uniformView.buffer;
    }
    // Oversize allocations are not retained by the HostBuffer ring. Use a
    // one-shot buffer instead.
    return gpu.gpuContext.createDeviceBufferWithCopy(uniformBytes);
  }
}

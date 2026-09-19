import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import '../frame/command_layout.dart';
import '../frame/draw_command_admission.dart';
import '../frame/draw_flags.dart';
import '../frame/ubo_abi.dart';
import '../native/abi_generated.dart';
import '../native/draw_command.dart';
import '../native/maplibre_ffi.dart';
import 'command_resources.dart';
import 'draw_entry.dart';
import 'resource_cache.dart';

part 'command/command_view.dart';
part 'command/draw_entry_pool.dart';
part 'command/entry_decoder.dart';

/// Reserves an entry's uniform ranges in the frame's uniform block and returns
/// the cursor past them.
///
/// Every range is aligned for binding, so the cursor advances by more than the
/// UBO sizes alone.
int assignUniformRanges(DrawEntry entry, int cursor, int alignment) {
  final uboLayout = rendererUboLayoutForShader(entry.shader);
  entry.drawableUniformOffset = alignUniformOffset(cursor, alignment);
  entry.propsUniformOffset = alignUniformOffset(
    entry.drawableUniformOffset + uboLayout.drawableBytes,
    alignment,
  );
  entry.drawableUniformLength = uboLayout.drawableBytes;
  entry.propsUniformLength = uboLayout.propsBytes;
  var next = entry.propsUniformOffset + uboLayout.propsBytes;
  if (uboLayout.tilePropsBytes > 0) {
    entry.tilePropsUniformOffset = alignUniformOffset(next, alignment);
    entry.tilePropsUniformLength = uboLayout.tilePropsBytes;
    next = entry.tilePropsUniformOffset + uboLayout.tilePropsBytes;
  }
  return next;
}

/// Frame-wide state produced after every command has been decoded.
typedef GpuFrameDecode = ({
  Uint8List commandBytes,
  ByteData commandData,
  int commandCount,
  int uniformAlignment,
  int uniformCursor,
  bool hasMapGlobalUniform,
  int? lastFillExtrusionLayerIndex,
});

/// Borrowed bytes and typed access to a validated native command block.
typedef GpuCommandView = ({
  Uint8List commandBytes,
  ByteData commandData,
  int commandCount,
  int commandStride,
});

/// Decodes native command blocks into reusable entries.
///
/// Entries and borrowed command views remain valid only while their native
/// frame is alive. Reset entries before decoding a different topology.
final class GpuCommandDecoder {
  /// Resolves geometry through [resourceCache].
  GpuCommandDecoder(GpuResourceCache resourceCache)
    : _resources = GpuCommandResources(resourceCache);

  final GpuCommandResources _resources;
  final _commandViews = _GpuCommandViewCache();
  final _drawEntryPool = _GpuDrawEntryPool();
  late final _entryDecoder = _GpuCommandEntryDecoder(
    _resources,
    _drawEntryPool,
  );

  /// Entries admitted by the current decoded topology.
  final List<DrawEntry> entries = [];

  /// Clears active entries while retaining pool storage for the next topology.
  void resetEntries() {
    entries.clear();
    _drawEntryPool.reset();
  }

  /// Releases retained GPU resources and borrowed native command views.
  void dispose() {
    _commandViews.clear();
    entries.clear();
    _drawEntryPool.dispose();
  }

  /// Acquires the next pooled entry and resets all command-specific state.
  ///
  /// The caller adds the result to [entries] after admission succeeds.
  DrawEntry acquireDrawEntry(
    int commandOffset,
    int shader,
    int drawMode,
    int flags,
    int layer,
    int vertexCount,
    int indexCount,
    GpuBufferEntry? vertexBuffer,
    GpuBufferEntry? indexBuffer,
    gpu.Texture? texture,
    int textureFilter,
    int stencilReference,
    int stencilMode,
    int subLayerIndex,
  ) => _drawEntryPool.acquireDrawEntry(
    commandOffset,
    shader,
    drawMode,
    flags,
    layer,
    vertexCount,
    indexCount,
    vertexBuffer,
    indexBuffer,
    texture,
    textureFilter,
    stencilReference,
    stencilMode,
    subLayerIndex,
  );

  /// Drops resource references held by pool entries outside the active topology.
  void releaseUnusedDrawEntries() => _drawEntryPool.releaseUnused();

  /// Borrows the command block, reusing typed views while its address is stable.
  ///
  /// Returns null and releases old views for an empty or invalid native block.
  GpuCommandView? commandView(
    FrameCommandMetadata metadata, {
    required bool shouldLog,
  }) => _commandViews.view(metadata, shouldLog: shouldLog);

  /// Refreshes resources for entries whose structural topology still matches.
  ///
  /// Returns false when geometry layout or required textures cannot be reused.
  bool refreshEntries(
    List<DrawEntry> entries,
    ByteData commandData, {
    required bool shouldLog,
  }) => _entryDecoder.refresh(entries, commandData, shouldLog: shouldLog);

  /// Reads the native command buffer into pooled [DrawEntry] values.
  ///
  /// Returns null when the native command block is unavailable or invalid.
  ///
  /// Also assigns each entry its uniform ranges, since their offsets run
  /// consecutively in decode order.
  GpuFrameDecode? decodeCommands(
    FrameCommandMetadata frameMetadata, {
    required bool shouldLog,
  }) {
    final view = commandView(frameMetadata, shouldLog: shouldLog);
    if (view == null) {
      releaseUnusedDrawEntries();

      return null;
    }
    final commandBytes = view.commandBytes;
    final commandData = view.commandData;
    final commandCount = view.commandCount;
    final stride = view.commandStride;
    final backendAlignment = gpu.gpuContext.minimumUniformByteAlignment;
    final uniformAlignment =
        backendAlignment < RendererUboAbi.minimumUniformByteAlignment
        ? RendererUboAbi.minimumUniformByteAlignment
        : backendAlignment;

    var uniformCursor = 0;
    var lineCommandCount = 0;
    var hasTriangulatedOutline = false;
    int? lastFillExtrusionLayerIndex;
    for (var index = 0; index < commandCount; index += 1) {
      final commandOffset = index * stride;
      final layerIndex = commandData.getUint32(
        commandOffset + DrawCommandAbi.layerIndex,
        Endian.little,
      );
      if (commandData.getUint32(
            commandOffset + DrawCommandAbi.shaderType,
            Endian.little,
          ) ==
          ShaderType.fillExtrusion) {
        lastFillExtrusionLayerIndex = layerIndex;
      }
      final entry = _entryDecoder.decode(
        commandData,
        commandOffset,
        shouldLog: shouldLog,
      );
      if (entry == null) continue;
      entries.add(entry);
      if (entry.stencilMode == StencilModeType.clear) continue;
      if (isLineShader(entry.shader)) lineCommandCount++;
      if (entry.shader == ShaderType.fillOutlineTriangulated) {
        hasTriangulatedOutline = true;
      }
      uniformCursor = assignUniformRanges(
        entry,
        uniformCursor,
        uniformAlignment,
      );
    }
    releaseUnusedDrawEntries();

    return (
      commandBytes: commandBytes,
      commandData: commandData,
      commandCount: commandCount,
      uniformAlignment: uniformAlignment,
      uniformCursor: uniformCursor,
      hasMapGlobalUniform: frameNeedsMapGlobalUniform(
        lineCommandCount: lineCommandCount,
        hasTriangulatedOutline: hasTriangulatedOutline,
      ),
      lastFillExtrusionLayerIndex: lastFillExtrusionLayerIndex,
    );
  }
}

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

  /// Entries admitted by the current decoded topology.
  final List<DrawEntry> entries = [];
  final List<DrawEntry> _drawEntryPool = [];
  var _drawEntryPoolCursor = 0;
  var _commandViewAddress = 0;
  var _commandViewLength = 0;
  var _commandBytes = Uint8List(0);
  var _commandData = ByteData(0);

  /// Clears active entries while retaining pool storage for the next topology.
  void resetEntries() {
    entries.clear();
    _drawEntryPoolCursor = 0;
  }

  /// Releases retained GPU resources and borrowed native command views.
  void dispose() {
    _clearCommandViews();
    entries.clear();
    for (final entry in _drawEntryPool) {
      entry.releaseResources();
    }
    _drawEntryPool.clear();
    _drawEntryPoolCursor = 0;
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
  ) {
    if (_drawEntryPoolCursor == _drawEntryPool.length) {
      _drawEntryPool.add(
        .new(
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
          subLayerIndex: subLayerIndex,
        ),
      );
    } else {
      _drawEntryPool[_drawEntryPoolCursor].reset(
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
        nextSubLayerIndex: subLayerIndex,
      );
    }
    return _drawEntryPool[_drawEntryPoolCursor++];
  }

  /// Drops resource references held by pool entries outside the active topology.
  void releaseUnusedDrawEntries() {
    for (
      var index = _drawEntryPoolCursor;
      index < _drawEntryPool.length;
      index += 1
    ) {
      _drawEntryPool[index].releaseResources();
    }
  }

  /// Borrows the command block, reusing typed views while its address is stable.
  ///
  /// Returns null and releases old views for an empty or invalid native block.
  GpuCommandView? commandView(
    FrameCommandMetadata metadata, {
    required bool shouldLog,
  }) {
    final commandCount = metadata.commandCount;
    if (commandCount <= 0) {
      _clearCommandViews();

      return null;
    }
    final commandsPointer = metadata.commands;
    if (commandsPointer == nullptr) {
      _clearCommandViews();

      return null;
    }
    final stride = metadata.commandStride;
    if (stride != DrawCommandAbi.size) {
      if (shouldLog) {
        debugPrint(
          '[GpuRenderer] ABI mismatch: stride=$stride expected=${DrawCommandAbi.size}',
        );
      }
      _clearCommandViews();

      return null;
    }
    final commandViewAddress = commandsPointer.address;
    final commandViewLength = commandCount * stride;
    if (_commandViewAddress != commandViewAddress ||
        _commandViewLength != commandViewLength) {
      _commandViewAddress = commandViewAddress;
      _commandViewLength = commandViewLength;
      _commandBytes = commandsPointer.cast<Uint8>().asTypedList(
        commandViewLength,
      );
      _commandData = ByteData.sublistView(_commandBytes);
    }
    return (
      commandBytes: _commandBytes,
      commandData: _commandData,
      commandCount: commandCount,
      commandStride: stride,
    );
  }

  /// Refreshes resources for entries whose structural topology still matches.
  ///
  /// Returns false when geometry layout or required textures cannot be reused.
  bool refreshEntries(
    List<DrawEntry> entries,
    ByteData commandData, {
    required bool shouldLog,
  }) {
    for (final entry in entries) {
      final offset = entry.commandOffset;
      entry.stencilReference = commandData.getUint32(
        offset + DrawCommandAbi.stencilReference,
        Endian.little,
      );
      if (entry.stencilMode == StencilModeType.clear) continue;

      final vertexCount = commandData.getUint32(
        offset + DrawCommandAbi.vertexCount,
        Endian.little,
      );
      final indexCount = commandData.getUint32(
        offset + DrawCommandAbi.indexCount,
        Endian.little,
      );
      final vertexStride = commandData.getUint32(
        offset + DrawCommandAbi.vertexStride,
        Endian.little,
      );
      final isMerged = drawCommandIsCrossTileMerged(entry.flags);
      final expectedStride = nativeVertexStride(
        shader: entry.shader,
        flags: entry.flags,
        merged: isMerged,
      );
      if (vertexStride != expectedStride) {
        if (shouldLog) {
          debugPrint(
            '[GpuRenderer] prepared graph vertex stride mismatch: '
            'shader=${entry.shader} flags=${entry.flags} '
            'exported=$vertexStride expected=$expectedStride',
          );
        }
        return false;
      }
      final vertexDataAddress = commandData.getUint64(
        offset + DrawCommandAbi.vertexData,
        Endian.little,
      );
      final indexDataAddress = commandData.getUint64(
        offset + DrawCommandAbi.indexData,
        Endian.little,
      );
      entry
        ..vertexCount = vertexCount
        ..indexCount = indexCount
        ..vertexBuffer = isMerged
            ? _resources.frameVertexBuffer(
                vertexDataAddress,
                vertexCount,
                vertexStride,
                entry.shader,
                entry.flags,
              )
            : _resources.cachedVertexBuffer(
                commandData.getUint32(
                  offset + DrawCommandAbi.bufferId,
                  Endian.little,
                ),
                commandData.getUint32(
                  offset + DrawCommandAbi.bufferVersion,
                  Endian.little,
                ),
                vertexDataAddress,
                vertexCount,
                vertexStride,
                entry.shader,
                entry.flags,
              )
        ..indexBuffer = isMerged
            ? _resources.frameIndexBuffer(indexDataAddress, indexCount * 2)
            : _resources.cachedIndexBuffer(
                commandData.getUint32(
                  offset + DrawCommandAbi.bufferId,
                  Endian.little,
                ),
                commandData.getUint32(
                  offset + DrawCommandAbi.bufferVersion,
                  Endian.little,
                ),
                indexDataAddress,
                indexCount,
                entry.shader,
              );

      gpu.Texture? commandTexture;
      final textureChannels = commandData.getUint32(
        offset + DrawCommandAbi.texChannels,
        Endian.little,
      );
      if (textureChannels > 0) {
        commandTexture = _resources.textureForCommand(
          commandData.getUint32(offset + DrawCommandAbi.texId, Endian.little),
          commandData.getUint32(
            offset + DrawCommandAbi.texVersion,
            Endian.little,
          ),
          commandData.getUint64(offset + DrawCommandAbi.texData, Endian.little),
          commandData.getUint32(
            offset + DrawCommandAbi.texWidth,
            Endian.little,
          ),
          commandData.getUint32(
            offset + DrawCommandAbi.texHeight,
            Endian.little,
          ),
          textureChannels,
        );
        if (commandTexture == null &&
            shaderRequiresUploadedTexture(entry.shader)) {
          if (shouldLog) {
            debugPrint(
              '[GpuRenderer] prepared graph texture refresh failed: '
              'shader=${entry.shader}',
            );
          }
          return false;
        }
      } else if (shaderRequiresTextureData(entry.shader)) {
        return false;
      }
      entry
        ..texture = commandTexture
        ..textureFilter = commandData.getUint32(
          offset + DrawCommandAbi.texFilter,
          Endian.little,
        );
    }
    return true;
  }

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
      final entry = _decodeCommand(
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

  void _clearCommandViews() {
    if (_commandViewLength == 0) return;
    _commandViewAddress = 0;
    _commandViewLength = 0;
    _commandBytes = Uint8List(0);
    _commandData = ByteData(0);
  }

  /// Decodes one DrawCommand record, resolving its buffers and texture.
  ///
  /// Returns null when the command cannot or need not be rendered.
  ///
  /// The returned entry has no uniform ranges yet. Those are assigned by the
  /// caller, which knows where the frame's uniform cursor stands.
  DrawEntry? _decodeCommand(
    ByteData commandData,
    int offset, {
    required bool shouldLog,
  }) {
    final shader = commandData.getUint32(
      offset + DrawCommandAbi.shaderType,
      Endian.little,
    );
    final stencilMode = commandData.getUint32(
      offset + DrawCommandAbi.stencilMode,
      Endian.little,
    );
    final vertexCount = commandData.getUint32(
      offset + DrawCommandAbi.vertexCount,
      Endian.little,
    );
    final indexCount = commandData.getUint32(
      offset + DrawCommandAbi.indexCount,
      Endian.little,
    );
    final vertexDataAddress = commandData.getUint64(
      offset + DrawCommandAbi.vertexData,
      Endian.little,
    );
    final indexDataAddress = commandData.getUint64(
      offset + DrawCommandAbi.indexData,
      Endian.little,
    );

    final admission = admitDrawCommand(
      shader: shader,
      stencilMode: stencilMode,
      vertexCount: vertexCount,
      indexCount: indexCount,
      vertexDataAddress: vertexDataAddress,
      indexDataAddress: indexDataAddress,
      drawableMatrixM00: commandData.getFloat32(
        offset + DrawCommandAbi.drawableUBO,
        Endian.little,
      ),
      drawableMatrixM11: commandData.getFloat32(
        offset +
            DrawCommandAbi.drawableUBO +
            RendererUboAbi.drawableMatrixM11Offset,
        Endian.little,
      ),
    );
    if (admission == .drop) return null;

    final flags = commandData.getUint32(
      offset + DrawCommandAbi.flags,
      Endian.little,
    );
    final isMerged = drawCommandIsCrossTileMerged(flags);
    final drawMode = commandData.getUint32(
      offset + DrawCommandAbi.drawMode,
      Endian.little,
    );
    final layer = commandData.getUint32(
      offset + DrawCommandAbi.layerIndex,
      Endian.little,
    );
    final stencilReference = commandData.getUint32(
      offset + DrawCommandAbi.stencilReference,
      Endian.little,
    );
    final subLayerIndex = commandData.getInt32(
      offset + DrawCommandAbi.subLayerIndex,
      Endian.little,
    );

    // Control commands bind no geometry but must retain their command order.
    if (admission == .controlCommand) {
      return acquireDrawEntry(
        offset,
        shader,
        drawMode,
        flags,
        layer,
        0,
        0,
        null,
        null,
        null,
        TextureFilterType.linear,
        stencilReference,
        stencilMode,
        subLayerIndex,
      );
    }

    final vertexStride = nativeVertexStride(
      shader: shader,
      flags: flags,
      merged: isMerged,
    );
    final exportedVertexStride = commandData.getUint32(
      offset + DrawCommandAbi.vertexStride,
      Endian.little,
    );
    if (exportedVertexStride != vertexStride) {
      if (shouldLog) {
        debugPrint(
          '[GpuRenderer] vertex stride mismatch: shader=$shader flags=$flags '
          'exported=$exportedVertexStride expected=$vertexStride',
        );
      }
      return null;
    }
    final bufferId = commandData.getUint32(
      offset + DrawCommandAbi.bufferId,
      Endian.little,
    );
    final bufferVersion = commandData.getUint32(
      offset + DrawCommandAbi.bufferVersion,
      Endian.little,
    );
    // Cross-tile merged buffers are frame-owned. Other buffers are cached by
    // the native drawable generation.
    final vertexBuffer = isMerged
        ? _resources.frameVertexBuffer(
            vertexDataAddress,
            vertexCount,
            vertexStride,
            shader,
            flags,
          )
        : _resources.cachedVertexBuffer(
            bufferId,
            bufferVersion,
            vertexDataAddress,
            vertexCount,
            vertexStride,
            shader,
            flags,
          );
    final indexBuffer = isMerged
        ? _resources.frameIndexBuffer(indexDataAddress, indexCount * 2)
        : _resources.cachedIndexBuffer(
            bufferId,
            bufferVersion,
            indexDataAddress,
            indexCount,
            shader,
          );
    gpu.Texture? commandTexture;
    final textureChannels = commandData.getUint32(
      offset + DrawCommandAbi.texChannels,
      Endian.little,
    );
    if (textureChannels > 0) {
      commandTexture = _resources.textureForCommand(
        commandData.getUint32(offset + DrawCommandAbi.texId, Endian.little),
        commandData.getUint32(
          offset + DrawCommandAbi.texVersion,
          Endian.little,
        ),
        commandData.getUint64(offset + DrawCommandAbi.texData, Endian.little),
        commandData.getUint32(offset + DrawCommandAbi.texWidth, Endian.little),
        commandData.getUint32(offset + DrawCommandAbi.texHeight, Endian.little),
        textureChannels,
      );
      // Texture-backed variants cannot render without their image.
      if (commandTexture == null && shaderRequiresUploadedTexture(shader)) {
        return null;
      }
    } else if (shaderRequiresTextureData(shader)) {
      return null;
    }
    return acquireDrawEntry(
      offset,
      shader,
      drawMode,
      flags,
      layer,
      vertexCount,
      indexCount,
      vertexBuffer,
      indexBuffer,
      commandTexture,
      commandData.getUint32(offset + DrawCommandAbi.texFilter, Endian.little),
      stencilReference,
      stencilMode,
      subLayerIndex,
    );
  }
}

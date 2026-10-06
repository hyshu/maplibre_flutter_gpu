part of '../command_decoder.dart';

/// Resolves native command fields into new or retained draw entries.
final class _GpuCommandEntryDecoder {
  _GpuCommandEntryDecoder(this._resources, this._pool);

  final GpuCommandResources _resources;
  final _GpuDrawEntryPool _pool;

  /// Refreshes resources for entries whose structural topology still matches.
  ///
  /// Returns false when geometry layout or required textures cannot be reused.
  bool refresh(
    List<DrawEntry> entries,
    ByteData commandData,
    CommandPayloadReader payload, {
    required bool shouldLog,
  }) {
    for (final entry in entries) {
      final offset = entry.commandOffset;
      if (!payload.read(commandData, offset)) return false;
      entry.stencilReference = payload.stencilReference;
      _readRenderTarget(entry, payload);
      if (entry.stencilMode == StencilModeType.clear ||
          entry.shader == ShaderType.renderTarget) {
        continue;
      }

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
      final textureChannels = payload.textureChannels;
      if (textureChannels > 0) {
        commandTexture = _resources.textureForCommand(
          payload.textureId,
          payload.textureVersion,
          payload.textureAddress,
          payload.textureWidth,
          payload.textureHeight,
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
        ..textureFilter = payload.textureFilter;
    }
    return true;
  }

  /// Decodes one DrawCommand record, resolving its buffers and texture.
  ///
  /// Returns null when the command cannot or need not be rendered.
  ///
  /// The returned entry has no uniform ranges yet. Those are assigned by the
  /// caller, which knows where the frame's uniform cursor stands.
  DrawEntry? decode(
    ByteData commandData,
    int offset,
    CommandPayloadReader payload, {
    required bool shouldLog,
  }) {
    if (!payload.read(commandData, offset)) return null;
    final shader = commandData.getUint32(
      offset + DrawCommandAbi.shaderType,
      Endian.little,
    );
    final stencilMode = payload.stencilMode;
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
      drawableMatrixM00: payload.matrixM00,
      drawableMatrixM11: payload.matrixM11,
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
    final stencilReference = payload.stencilReference;
    final subLayerIndex = commandData.getInt32(
      offset + DrawCommandAbi.subLayerIndex,
      Endian.little,
    );

    // Control commands bind no geometry but must retain their command order.
    if (admission == .controlCommand) {
      final entry = _pool.acquireDrawEntry(
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
      _readRenderTarget(entry, payload);

      return entry;
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
    final textureChannels = payload.textureChannels;
    if (textureChannels > 0) {
      commandTexture = _resources.textureForCommand(
        payload.textureId,
        payload.textureVersion,
        payload.textureAddress,
        payload.textureWidth,
        payload.textureHeight,
        textureChannels,
      );
      // Texture-backed variants cannot render without their image.
      if (commandTexture == null && shaderRequiresUploadedTexture(shader)) {
        return null;
      }
    } else if (shaderRequiresTextureData(shader)) {
      return null;
    }
    final entry = _pool.acquireDrawEntry(
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
      payload.textureFilter,
      stencilReference,
      stencilMode,
      subLayerIndex,
    );
    _readRenderTarget(entry, payload);

    return entry;
  }

  void _readRenderTarget(DrawEntry entry, CommandPayloadReader payload) {
    entry
      ..renderTargetId = payload.renderTargetId
      ..renderTargetWidth = payload.renderTargetWidth
      ..renderTargetHeight = payload.renderTargetHeight
      ..sampledRenderTarget = null;
  }
}

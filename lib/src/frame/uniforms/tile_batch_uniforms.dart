part of '../uniform_packer.dart';

/// Writes every member of a tile-batched command plus its `TileBatchUBO`.
///
/// The exported drawable bytes hold [memberCount] drawables followed by the
/// member table. Each member is patched like a per-tile command, tile
/// properties are copied per member, and the table feeds the batch UBO
/// together with the tile mask size in physical pixels.
void packTileBatchUniforms({
  required CommandPayloadReader payload,
  required Uint8List destination,
  required ByteData destinationData,
  required int shader,
  required int flags,
  required int memberCount,
  required int drawableOffset,
  required int drawableLength,
  required int propsOffset,
  required int propsLength,
  required int tilePropsOffset,
  required int tilePropsLength,
  required int batchOffset,
  required double devicePixelRatio,
  required int textureWidth,
  required int textureHeight,
  required int maskWidth,
  required int maskHeight,
}) {
  final layout = rendererUboLayoutForShader(shader);
  final memberDrawableBytes = layout.drawableBytes;
  final tableBytes = memberCount * RendererUboAbi.tileBatchTableEntryBytes;
  final exportedMemberBytes =
      (payload.drawableSize - tableBytes) ~/ memberCount;
  for (var member = 0; member < memberCount; member++) {
    final sourceOffset = payload.drawableOffset + member * exportedMemberBytes;
    final memberOffset = drawableOffset + member * memberDrawableBytes;
    _copyExportedUbo(
      payload: payload,
      sourceOffset: sourceOffset,
      exportedSize: exportedMemberBytes,
      destination: destination,
      destinationOffset: memberOffset,
      destinationLength: RendererUboAbi.drawableMatrixBytes,
    );
    convertOpenGlToFlutterGpuDepth(
      destinationData,
      offsetInBytes: memberOffset,
    );
    _packDrawableUniforms(
      payload: payload,
      destination: destination,
      destinationData: destinationData,
      shader: shader,
      flags: flags,
      drawableOffset: memberOffset,
      drawableLength: memberDrawableBytes,
      devicePixelRatio: devicePixelRatio,
      textureWidth: textureWidth,
      textureHeight: textureHeight,
      sourceOffset: sourceOffset,
      sourceSize: exportedMemberBytes,
      batched: true,
    );
  }
  if (memberCount * memberDrawableBytes < drawableLength) {
    destination.fillRange(
      drawableOffset + memberCount * memberDrawableBytes,
      drawableOffset + drawableLength,
      0,
    );
  }
  _packEvaluatedUniforms(
    payload: payload,
    destination: destination,
    destinationData: destinationData,
    shader: shader,
    flags: flags,
    propsOffset: propsOffset,
    propsLength: propsLength,
  );
  if (tilePropsLength > 0) {
    final memberTileProps = layout.tilePropsBytes;
    for (var member = 0; member < memberCount; member++) {
      _copyExportedUbo(
        payload: payload,
        sourceOffset: payload.tilePropsOffset + member * memberTileProps,
        exportedSize: payload.tilePropsSize - member * memberTileProps,
        destination: destination,
        destinationOffset: tilePropsOffset + member * memberTileProps,
        destinationLength: memberTileProps,
      );
    }
    if (memberCount * memberTileProps < tilePropsLength) {
      destination.fillRange(
        tilePropsOffset + memberCount * memberTileProps,
        tilePropsOffset + tilePropsLength,
        0,
      );
    }
  }

  destination.fillRange(
    batchOffset,
    batchOffset + RendererUboAbi.tileBatchBytes,
    0,
  );
  destinationData
    ..setFloat32(
      batchOffset + RendererUboAbi.tileBatchMaskWidthOffset,
      maskWidth.toDouble(),
      Endian.little,
    )
    ..setFloat32(
      batchOffset + RendererUboAbi.tileBatchMaskHeightOffset,
      maskHeight.toDouble(),
      Endian.little,
    )
    ..setFloat32(
      batchOffset + RendererUboAbi.tileBatchMemberCountOffset,
      memberCount.toDouble(),
      Endian.little,
    );
  final table = payload.drawableOffset + memberCount * exportedMemberBytes;
  for (var member = 0; member < memberCount; member++) {
    final entry = table + member * RendererUboAbi.tileBatchTableEntryBytes;
    // Starts and references are whole floats for the same reason.
    destinationData
      ..setFloat32(
        batchOffset + RendererUboAbi.tileBatchStartsOffset + member * 4,
        payload.data.getUint32(entry, Endian.little).toDouble(),
        Endian.little,
      )
      ..setFloat32(
        batchOffset + RendererUboAbi.tileBatchIdsOffset + member * 4,
        payload.data.getUint32(entry + 4, Endian.little).toDouble(),
        Endian.little,
      );
  }
}

part of '../uniform_packer.dart';

/// Copies the native drawable tail and initializes omitted shader padding.
void _copyDrawableTail({
  required CommandPayloadReader payload,
  required Uint8List destination,
  required int drawableOffset,
  required int drawableLength,
}) => _copyExportedUbo(
  payload: payload,
  sourceOffset: payload.drawableOffset + RendererUboAbi.drawableMatrixBytes,
  exportedSize: payload.drawableSize > RendererUboAbi.drawableMatrixBytes
      ? payload.drawableSize - RendererUboAbi.drawableMatrixBytes
      : 0,
  destination: destination,
  destinationOffset: drawableOffset + RendererUboAbi.drawableMatrixBytes,
  destinationLength: drawableLength - RendererUboAbi.drawableMatrixBytes,
);

/// Copies only exported bytes and initializes every omitted destination byte.
void _copyExportedUbo({
  required CommandPayloadReader payload,
  required int sourceOffset,
  required int exportedSize,
  required Uint8List destination,
  required int destinationOffset,
  required int destinationLength,
}) {
  if (destinationLength == 0) return;
  final length = exportedSize < destinationLength
      ? exportedSize
      : destinationLength;
  if (length > 0) {
    destination.setRange(
      destinationOffset,
      destinationOffset + length,
      payload.bytes,
      sourceOffset,
    );
  }
  if (length < destinationLength) {
    destination.fillRange(
      destinationOffset + length,
      destinationOffset + destinationLength,
      0,
    );
  }
}

void _copyEvaluatedProps({
  required CommandPayloadReader payload,
  required Uint8List destination,
  required int propsOffset,
  required int propsLength,
}) => _copyExportedUbo(
  payload: payload,
  sourceOffset: payload.propsOffset,
  exportedSize: payload.propsSize,
  destination: destination,
  destinationOffset: propsOffset,
  destinationLength: propsLength,
);

void _copyTileProps({
  required CommandPayloadReader payload,
  required Uint8List destination,
  required int tilePropsOffset,
  required int tilePropsLength,
}) => _copyExportedUbo(
  payload: payload,
  sourceOffset: payload.tilePropsOffset,
  exportedSize: payload.tilePropsSize,
  destination: destination,
  destinationOffset: tilePropsOffset,
  destinationLength: tilePropsLength,
);

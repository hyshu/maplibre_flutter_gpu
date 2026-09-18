part of '../uniform_packer.dart';

/// Returns the evaluated-props byte count reported by the command.
int _exportedPropsSize(ByteData sourceData, int commandOffset) => sourceData
    .getUint32(commandOffset + DrawCommandAbi.propsUBOSize, Endian.little);

/// Copies the drawable UBO past its leading mat4.
///
/// Every shader gets the matrix. Only layouts that add fields after it need
/// this helper. Copying `drawableLength` bytes for a matrix-only layout
/// would pull in unrelated command bytes.
void _copyDrawableTail({
  required Uint8List source,
  required int commandOffset,
  required Uint8List destination,
  required int drawableOffset,
  required int drawableLength,
}) => destination.setRange(
  drawableOffset + RendererUboAbi.drawableMatrixBytes,
  drawableOffset + drawableLength,
  source,
  commandOffset +
      DrawCommandAbi.drawableUBO +
      RendererUboAbi.drawableMatrixBytes,
);

/// Copies one embedded UBO, clamped to what the command actually exported.
///
/// The export can be shorter than the layout when native and Dart disagree on
/// a struct's size. Copying the layout length regardless would read past the
/// embedded buffer into the next field of the command. An exported size of
/// zero means the command carries no such UBO at all.
void _copyExportedUbo({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required int sizeField,
  required int dataField,
  required Uint8List destination,
  required int destinationOffset,
  required int destinationLength,
}) {
  if (destinationLength == 0) return;
  final exported = sourceData.getUint32(
    commandOffset + sizeField,
    Endian.little,
  );
  final length = exported < destinationLength ? exported : destinationLength;
  if (length > 0) {
    destination.setRange(
      destinationOffset,
      destinationOffset + length,
      source,
      commandOffset + dataField,
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

/// Copies the evaluated-props UBO when the shader layout includes one.
void _copyEvaluatedProps({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required Uint8List destination,
  required int propsOffset,
  required int propsLength,
}) => _copyExportedUbo(
  source: source,
  sourceData: sourceData,
  commandOffset: commandOffset,
  sizeField: DrawCommandAbi.propsUBOSize,
  dataField: DrawCommandAbi.propsUBO,
  destination: destination,
  destinationOffset: propsOffset,
  destinationLength: propsLength,
);

/// Copies the tile-props UBO.
///
/// Only the SDF and pattern line variants have one. The others pass a zero
/// length and this is a no-op.
void _copyTileProps({
  required Uint8List source,
  required ByteData sourceData,
  required int commandOffset,
  required Uint8List destination,
  required int tilePropsOffset,
  required int tilePropsLength,
}) => _copyExportedUbo(
  source: source,
  sourceData: sourceData,
  commandOffset: commandOffset,
  sizeField: DrawCommandAbi.tilePropsUBOSize,
  dataField: DrawCommandAbi.tilePropsUBO,
  destination: destination,
  destinationOffset: tilePropsOffset,
  destinationLength: tilePropsLength,
);

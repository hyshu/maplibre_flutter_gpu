part of '../command_decoder.dart';

/// Retains typed views only while the borrowed native command block is stable.
final class _GpuCommandViewCache {
  var _commandViewAddress = 0;
  var _commandViewLength = 0;
  var _commandBytes = Uint8List(0);
  var _commandData = ByteData(0);
  var _payloadAddress = 0;
  var _payload = CommandPayloadReader(Uint8List(0));

  /// Borrows the command block, reusing typed views while its address is stable.
  ///
  /// Returns null and releases old views for an empty or invalid native block.
  GpuCommandView? view(
    FrameCommandMetadata metadata, {
    required bool shouldLog,
  }) {
    final commandCount = metadata.commandCount;
    if (commandCount <= 0) {
      clear();

      return null;
    }
    final commandsPointer = metadata.commands;
    if (commandsPointer == nullptr) {
      clear();

      return null;
    }
    final stride = metadata.commandStride;
    if (stride != DrawCommandAbi.size) {
      if (shouldLog) {
        debugPrint(
          '[GpuRenderer] ABI mismatch: stride=$stride expected=${DrawCommandAbi.size}',
        );
      }
      clear();

      return null;
    }
    final payloadSize = metadata.payloadSize;
    if (payloadSize < 0 || (payloadSize > 0 && metadata.payload == nullptr)) {
      clear();

      return null;
    }
    if (_payloadAddress != metadata.payload.address ||
        _payload.bytes.length != payloadSize) {
      _payloadAddress = metadata.payload.address;
      _payload = CommandPayloadReader(
        payloadSize == 0
            ? Uint8List(0)
            : metadata.payload.cast<Uint8>().asTypedList(payloadSize),
      );
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
      payload: _payload,
      commandCount: commandCount,
      commandStride: stride,
    );
  }

  void clear() {
    if (_commandViewLength == 0 && _payload.bytes.isEmpty) return;
    _commandViewAddress = 0;
    _commandViewLength = 0;
    _commandBytes = Uint8List(0);
    _commandData = ByteData(0);
    _payloadAddress = 0;
    _payload = CommandPayloadReader(Uint8List(0));
  }
}

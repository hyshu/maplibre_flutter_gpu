import 'dart:typed_data';

import 'abi_generated.dart';
import 'draw_command.dart';

/// Optional blocks in the native command payload, in their serialized order.
abstract final class CommandPayloadSections {
  static const texture = 1;
  static const stencil = 2;
  static const renderTarget = 4;
  static const camera = 8;
  static const all = texture | stencil | renderTarget | camera;
}

/// Reuses a checked cursor over one frame's borrowed command payload arena.
///
/// The arena must remain alive while this reader is used. Call [read] for each
/// command and only consume fields when it returns true. No native bytes are
/// retained by prepared graphs or copied into fixed-size command records.
final class CommandPayloadReader {
  CommandPayloadReader(this.bytes) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final ByteData data;
  int drawableOffset = 0;
  int drawableSize = 0;
  int propsOffset = 0;
  int propsSize = 0;
  int tilePropsOffset = 0;
  int tilePropsSize = 0;
  int _textureOffset = -1;
  int _stencilOffset = -1;
  int _renderTargetOffset = -1;
  int _cameraOffset = -1;

  /// Selects a command after validating every block against its payload range.
  ///
  /// Empty payloads are valid. Misaligned, truncated, unknown, or out-of-range
  /// blocks return false without reading beyond the borrowed arena.
  bool read(ByteData commands, int commandOffset) {
    drawableOffset = 0;
    drawableSize = 0;
    propsOffset = 0;
    propsSize = 0;
    tilePropsOffset = 0;
    tilePropsSize = 0;
    _textureOffset = -1;
    _stencilOffset = -1;
    _renderTargetOffset = -1;
    _cameraOffset = -1;
    if (commandOffset < 0 ||
        commandOffset > commands.lengthInBytes - DrawCommandAbi.size) {
      return false;
    }
    final start = commands.getUint32(
      commandOffset + DrawCommandAbi.payloadOffset,
      Endian.little,
    );
    final size = commands.getUint32(
      commandOffset + DrawCommandAbi.payloadSize,
      Endian.little,
    );
    if (size == 0) return start == 0;
    if ((start & 7) != 0 ||
        (size & 7) != 0 ||
        size < CommandPayloadHeaderAbi.size ||
        start > bytes.lengthInBytes ||
        size > bytes.lengthInBytes - start) {
      return false;
    }
    final end = start + size;
    final sections = data.getUint16(
      start + CommandPayloadHeaderAbi.sections,
      Endian.little,
    );
    if ((sections & ~CommandPayloadSections.all) != 0) return false;
    drawableSize = data.getUint16(
      start + CommandPayloadHeaderAbi.drawableUBOSize,
      Endian.little,
    );
    propsSize = data.getUint16(
      start + CommandPayloadHeaderAbi.propsUBOSize,
      Endian.little,
    );
    tilePropsSize = data.getUint16(
      start + CommandPayloadHeaderAbi.tilePropsUBOSize,
      Endian.little,
    );
    drawableOffset = start + CommandPayloadHeaderAbi.size;
    propsOffset = (drawableOffset + drawableSize + 3) & ~3;
    tilePropsOffset = (propsOffset + propsSize + 3) & ~3;
    var cursor = tilePropsOffset + tilePropsSize;
    if ((sections & CommandPayloadSections.texture) != 0) {
      cursor = (cursor + 7) & ~7;
      _textureOffset = cursor;
      cursor += CommandTextureAbi.size;
    }
    if ((sections & CommandPayloadSections.stencil) != 0) {
      cursor = (cursor + 3) & ~3;
      _stencilOffset = cursor;
      cursor += CommandStencilAbi.size;
    }
    if ((sections & CommandPayloadSections.renderTarget) != 0) {
      cursor = (cursor + 3) & ~3;
      _renderTargetOffset = cursor;
      cursor += CommandRenderTargetAbi.size;
    }
    if ((sections & CommandPayloadSections.camera) != 0) {
      cursor = (cursor + 3) & ~3;
      _cameraOffset = cursor;
      cursor += 4;
    }

    return ((cursor + 7) & ~7) == end;
  }

  int _uint32(int block, int offset, [int absent = 0]) =>
      block < 0 ? absent : data.getUint32(block + offset, Endian.little);

  int get textureAddress => _textureOffset < 0
      ? 0
      : data.getUint64(_textureOffset + CommandTextureAbi.data, Endian.little);
  int get textureWidth => _uint32(_textureOffset, CommandTextureAbi.width);
  int get textureHeight => _uint32(_textureOffset, CommandTextureAbi.height);
  int get textureId => _uint32(_textureOffset, CommandTextureAbi.id);
  int get textureVersion => _uint32(_textureOffset, CommandTextureAbi.version);
  int get textureChannels =>
      _uint32(_textureOffset, CommandTextureAbi.channels);
  int get textureFilter => _uint32(
    _textureOffset,
    CommandTextureAbi.filter,
    TextureFilterType.linear,
  );
  int get stencilReference =>
      _uint32(_stencilOffset, CommandStencilAbi.reference);
  int get stencilMode => _uint32(_stencilOffset, CommandStencilAbi.mode);
  int get renderTargetId =>
      _uint32(_renderTargetOffset, CommandRenderTargetAbi.id);
  int get renderTargetWidth =>
      _uint32(_renderTargetOffset, CommandRenderTargetAbi.width);
  int get renderTargetHeight =>
      _uint32(_renderTargetOffset, CommandRenderTargetAbi.height);
  double get cameraDistance =>
      _cameraOffset < 0 ? 0 : data.getFloat32(_cameraOffset, Endian.little);
  double get matrixM00 =>
      drawableSize < 64 ? 0 : data.getFloat32(drawableOffset, Endian.little);
  double get matrixM11 => drawableSize < 64
      ? 0
      : data.getFloat32(drawableOffset + 20, Endian.little);
}

import 'dart:typed_data';

import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';

/// Mutable native command bytes with an independent compact payload arena.
final class TestCommand {
  TestCommand({
    int drawableSize = 128,
    int propsSize = 48,
    int tilePropsSize = 0,
    int sections = CommandPayloadSections.all,
  }) {
    var cursor = (CommandPayloadHeaderAbi.size + drawableSize + 3) & ~3;
    cursor = (cursor + propsSize + 3) & ~3;
    cursor += tilePropsSize;
    if ((sections & CommandPayloadSections.texture) != 0) {
      cursor = (cursor + 7) & ~7;
      textureOffset = cursor;
      cursor += CommandTextureAbi.size;
    }
    if ((sections & CommandPayloadSections.stencil) != 0) {
      cursor = (cursor + 3) & ~3;
      stencilOffset = cursor;
      cursor += CommandStencilAbi.size;
    }
    if ((sections & CommandPayloadSections.renderTarget) != 0) {
      cursor = (cursor + 3) & ~3;
      renderTargetOffset = cursor;
      cursor += CommandRenderTargetAbi.size;
    }
    if ((sections & CommandPayloadSections.camera) != 0) {
      cursor = (cursor + 3) & ~3;
      cameraOffset = cursor;
      cursor += 4;
    }
    payload = Uint8List((cursor + 7) & ~7);
    payloadData = ByteData.sublistView(payload);
    payloadData
      ..setUint16(
        CommandPayloadHeaderAbi.drawableUBOSize,
        drawableSize,
        .little,
      )
      ..setUint16(CommandPayloadHeaderAbi.propsUBOSize, propsSize, .little)
      ..setUint16(
        CommandPayloadHeaderAbi.tilePropsUBOSize,
        tilePropsSize,
        .little,
      )
      ..setUint16(CommandPayloadHeaderAbi.sections, sections, .little);
    data.setUint32(DrawCommandAbi.payloadSize, payload.length, .little);
    reader = CommandPayloadReader(payload);
    if (!reader.read(data, 0)) throw StateError('Invalid test command');
  }

  final bytes = Uint8List(DrawCommandAbi.size);
  late final data = ByteData.sublistView(bytes);
  late final Uint8List payload;
  late final ByteData payloadData;
  late final CommandPayloadReader reader;
  int textureOffset = -1;
  int stencilOffset = -1;
  int renderTargetOffset = -1;
  int cameraOffset = -1;
  int get drawableOffset => reader.drawableOffset;
  int get propsOffset => reader.propsOffset;
  int get tilePropsOffset => reader.tilePropsOffset;
}

/// Relocates payload ranges as native snapshot and command merging do.
({Uint8List commands, Uint8List payload}) combineTestCommands(
  List<TestCommand> commands,
) {
  final headers = Uint8List(commands.length * DrawCommandAbi.size);
  final headerData = ByteData.sublistView(headers);
  final payload = Uint8List(
    commands.fold(0, (sum, c) => sum + c.payload.length),
  );
  var payloadOffset = 0;
  for (var index = 0; index < commands.length; index++) {
    final command = commands[index];
    final offset = index * DrawCommandAbi.size;
    headers.setRange(offset, offset + DrawCommandAbi.size, command.bytes);
    headerData.setUint32(
      offset + DrawCommandAbi.payloadOffset,
      payloadOffset,
      .little,
    );
    payload.setRange(
      payloadOffset,
      payloadOffset + command.payload.length,
      command.payload,
    );
    payloadOffset += command.payload.length;
  }

  return (commands: headers, payload: payload);
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/abi_generated.dart';
import 'package:maplibre_flutter_gpu/src/native/command_payload.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

import 'support/compact_command.dart';

void main() {
  test(
    'all optional section combinations preserve aligned odd UBO lengths',
    () {
      for (
        var sections = 0;
        sections <= CommandPayloadSections.all;
        sections++
      ) {
        final command = TestCommand(
          drawableSize: 5,
          propsSize: 3,
          tilePropsSize: 7,
          sections: sections,
        );
        final reader = command.reader;
        expect(reader.drawableOffset, 8);
        expect(reader.propsOffset, 16);
        expect(reader.tilePropsOffset, 20);
        expect(reader.drawableSize, 5);
        expect(reader.propsSize, 3);
        expect(reader.tilePropsSize, 7);
        if (command.textureOffset >= 0) {
          command.payloadData
            ..setUint64(
              command.textureOffset + CommandTextureAbi.data,
              0x123456789,
              .little,
            )
            ..setUint32(
              command.textureOffset + CommandTextureAbi.width,
              258,
              .little,
            )
            ..setUint32(
              command.textureOffset + CommandTextureAbi.height,
              256,
              .little,
            )
            ..setUint32(
              command.textureOffset + CommandTextureAbi.id,
              31,
              .little,
            )
            ..setUint32(
              command.textureOffset + CommandTextureAbi.version,
              4,
              .little,
            )
            ..setUint32(
              command.textureOffset + CommandTextureAbi.channels,
              4,
              .little,
            )
            ..setUint32(
              command.textureOffset + CommandTextureAbi.filter,
              TextureFilterType.nearest,
              .little,
            );
          expect(command.textureOffset, 32);
          expect(reader.textureAddress, 0x123456789);
          expect(reader.textureWidth, 258);
          expect(reader.textureHeight, 256);
          expect(reader.textureId, 31);
          expect(reader.textureVersion, 4);
          expect(reader.textureChannels, 4);
          expect(reader.textureFilter, TextureFilterType.nearest);
        } else {
          expect(reader.textureAddress, 0);
          expect(reader.textureChannels, 0);
          expect(reader.textureFilter, TextureFilterType.linear);
        }
        if (command.stencilOffset >= 0) {
          command.payloadData
            ..setUint32(
              command.stencilOffset + CommandStencilAbi.reference,
              27,
              .little,
            )
            ..setUint32(
              command.stencilOffset + CommandStencilAbi.mode,
              StencilModeType.clear,
              .little,
            );
          expect(reader.stencilReference, 27);
          expect(reader.stencilMode, StencilModeType.clear);
        } else {
          expect(reader.stencilReference, 0);
          expect(reader.stencilMode, StencilModeType.disabled);
        }
        if (command.renderTargetOffset >= 0) {
          command.payloadData
            ..setUint32(
              command.renderTargetOffset + CommandRenderTargetAbi.id,
              17,
              .little,
            )
            ..setUint32(
              command.renderTargetOffset + CommandRenderTargetAbi.width,
              800,
              .little,
            )
            ..setUint32(
              command.renderTargetOffset + CommandRenderTargetAbi.height,
              600,
              .little,
            );
          expect(reader.renderTargetId, 17);
          expect(reader.renderTargetWidth, 800);
          expect(reader.renderTargetHeight, 600);
        } else {
          expect(reader.renderTargetId, 0);
          expect(reader.renderTargetWidth, 0);
          expect(reader.renderTargetHeight, 0);
        }
        if (command.cameraOffset >= 0) {
          command.payloadData.setFloat32(command.cameraOffset, 12.5, .little);
          expect(reader.cameraDistance, 12.5);
        } else {
          expect(reader.cameraDistance, 0);
        }
        expect(reader.matrixM00, 0);
        expect(reader.matrixM11, 0);
        expect(reader.read(command.data, 0), isTrue);
      }
    },
  );

  test('an empty payload resets every optional field on a reused reader', () {
    final command = TestCommand();
    command.payloadData
      ..setUint32(command.stencilOffset + CommandStencilAbi.mode, 4, .little)
      ..setUint32(command.renderTargetOffset, 5, .little)
      ..setFloat32(command.cameraOffset, 12.5, .little);
    final reader = command.reader;
    expect(reader.stencilMode, 4);
    expect(reader.renderTargetId, 5);
    expect(reader.read(ByteData(DrawCommandAbi.size), 0), isTrue);
    expect(reader.drawableSize, 0);
    expect(reader.propsSize, 0);
    expect(reader.tilePropsSize, 0);
    expect(reader.textureAddress, 0);
    expect(reader.stencilMode, 0);
    expect(reader.renderTargetId, 0);
    expect(reader.cameraDistance, 0);
  });

  test(
    'relocated commands share one arena without reading neighboring blocks',
    () {
      final commands = [
        TestCommand(drawableSize: 64, propsSize: 48, sections: 0),
        TestCommand(
          drawableSize: 0,
          propsSize: 0,
          sections: CommandPayloadSections.renderTarget,
        ),
        TestCommand(
          drawableSize: 128,
          propsSize: 64,
          sections: CommandPayloadSections.camera,
        ),
        TestCommand(
          drawableSize: 64,
          propsSize: 176,
          tilePropsSize: 32,
          sections: CommandPayloadSections.stencil,
        ),
      ];
      for (var index = 0; index < commands.length; index++) {
        final command = commands[index];
        command.payload.fillRange(
          command.propsOffset,
          command.propsOffset + command.reader.propsSize,
          index + 1,
        );
      }
      final frame = combineTestCommands(commands);
      final data = ByteData.sublistView(frame.commands);
      final reader = CommandPayloadReader(frame.payload);
      for (var index = 0; index < commands.length; index++) {
        expect(reader.read(data, index * DrawCommandAbi.size), isTrue);
        expect(reader.propsSize, commands[index].reader.propsSize);
        expect(
          frame.payload.sublist(
            reader.propsOffset,
            reader.propsOffset + reader.propsSize,
          ),
          everyElement(index + 1),
        );
      }
      data.setUint32(DrawCommandAbi.payloadSize, 8, .little);
      expect(reader.read(data, 0), isFalse);
      expect(reader.read(data, DrawCommandAbi.size), isTrue);
    },
  );

  test('malformed header references and payload layouts fail closed', () {
    for (final mutate in <void Function(TestCommand)>[
      (c) => c.data.setUint32(DrawCommandAbi.payloadOffset, 1, .little),
      (c) =>
          c.data.setUint32(DrawCommandAbi.payloadOffset, 0xfffffff8, .little),
      (c) => c.data.setUint32(DrawCommandAbi.payloadSize, 7, .little),
      (c) => c.data.setUint32(DrawCommandAbi.payloadSize, 0xfffffff8, .little),
      (c) => c.data.setUint32(
        DrawCommandAbi.payloadSize,
        c.payload.length - 8,
        .little,
      ),
      (c) => c.payloadData.setUint16(
        CommandPayloadHeaderAbi.sections,
        16,
        .little,
      ),
      (c) => c.payloadData.setUint16(
        CommandPayloadHeaderAbi.drawableUBOSize,
        65535,
        .little,
      ),
      (c) => c.payloadData.setUint16(
        CommandPayloadHeaderAbi.propsUBOSize,
        65535,
        .little,
      ),
      (c) => c.payloadData.setUint16(
        CommandPayloadHeaderAbi.tilePropsUBOSize,
        65535,
        .little,
      ),
    ]) {
      final command = TestCommand();
      mutate(command);
      expect(command.reader.read(command.data, 0), isFalse);
    }
    final command = TestCommand();
    expect(command.reader.read(command.data, -1), isFalse);
    expect(command.reader.read(command.data, 1), isFalse);
    expect(command.reader.read(ByteData(DrawCommandAbi.size - 1), 0), isFalse);
    expect(
      CommandPayloadReader(Uint8List(command.payload.length - 1))
          .read(command.data, 0),
      isFalse,
    );
    final expanded = Uint8List(command.payload.length + 8)
      ..setRange(0, command.payload.length, command.payload);
    command.data.setUint32(
      DrawCommandAbi.payloadSize,
      expanded.length,
      .little,
    );
    expect(CommandPayloadReader(expanded).read(command.data, 0), isFalse);
  });

  test('empty blocks require a zero arena offset', () {
    final reader = CommandPayloadReader(Uint8List(0));
    final headers = ByteData(DrawCommandAbi.size);
    expect(reader.read(headers, 0), isTrue);
    headers.setUint32(DrawCommandAbi.payloadOffset, 8, .little);
    expect(reader.read(headers, 0), isFalse);
  });
}

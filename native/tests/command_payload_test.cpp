#include <mln/command_export/draw_command.hpp>

#include <cassert>
#include <limits>
#include <stdexcept>

using namespace mln::command_export;

static void optionalStorage() {
    FrameData frame;
    DrawCommand command{};
    frame.setPayload(command, {});
    assert(command.payloadSize == 0 && frame.payload.empty());
    assert(CommandPayloadView(frame.payload, command).valid());

    std::array<uint8_t, 80> drawable{};
    std::array<uint8_t, 48> props{};
    drawable[64] = 37;
    props[12] = 91;
    DrawCommandPayload data;
    data.drawableUBO = drawable;
    data.propsUBO = props;
    data.stencil = CommandStencil{3, StencilModeType::ClippingTest};
    frame.setPayload(command, data);
    assert(sizeof(command) + command.payloadSize == 208);
    const CommandPayloadView view(frame.payload, command);
    assert(view.valid());
    assert(view.get().drawableUBO[64] == 37);
    assert(view.get().propsUBO[12] == 91);
    assert(view.get().stencil->reference == 3);
    assert(!view.get().texture && !view.get().renderTarget && !view.get().cameraDistance);

    frame.clear();
    data = {};
    data.renderTarget = CommandRenderTarget{13, 256, 128};
    frame.setPayload(command, data);
    assert(sizeof(command) + command.payloadSize == 88);
    const CommandPayloadView target(frame.payload, command);
    assert(target.get().drawableUBO.empty() && target.get().propsUBO.empty());
    assert(target.get().renderTarget->width == 256);
}

static void aliasingAndPublication() {
    FrameData frame;
    auto& command = frame.addCommand(ShaderType::Circle, DrawModeType::Triangles, nullptr, 4, 0, nullptr, 0);
    const std::array<uint8_t, 5> drawable{1, 2, 3, 4, 5};
    const std::array<uint8_t, 3> props{6, 7, 8};
    const std::array<uint8_t, 7> tile{9, 10, 11, 12, 13, 14, 15};
    const std::array<uint8_t, 4> pixels{0, 1, 2, 3};
    DrawCommandPayload data;
    data.drawableUBO = drawable;
    data.propsUBO = props;
    data.tilePropsUBO = tile;
    data.texture = CommandTexture{pixels.data(), 1, 1, 9, 2, 4, TextureFilterType::Linear};
    data.stencil = CommandStencil{4, StencilModeType::ClippingTest};
    data.renderTarget = CommandRenderTarget{17, 128, 128};
    data.cameraDistance = 1024.5f;
    frame.setPayload(command, data);
    frame.payload.shrink_to_fit();
    const auto original = command;
    const CommandPayloadView view(frame.payload, original);
    assert(view.valid());
    auto copy = view.get();
    copy.stencil->reference = 8;
    frame.setPayload(command, copy);
    const CommandPayloadView cloned(frame.payload, command);
    const CommandPayloadView retained(frame.payload, original);
    assert(command.payloadOffset != original.payloadOffset);
    assert(cloned.valid() && retained.valid());
    assert(cloned.get().drawableUBO[4] == 5 && cloned.get().propsUBO[2] == 8);
    assert(cloned.get().tilePropsUBO[6] == 15);
    assert(cloned.get().texture->data == pixels.data());
    assert(cloned.get().texture->filter == TextureFilterType::Linear);
    assert(cloned.get().stencil->reference == 8 && retained.get().stencil->reference == 4);
    assert(cloned.get().renderTarget->id == 17);
    assert(cloned.get().cameraDistance == 1024.5f);

    FrameData snapshot;
    snapshot.commands.swap(frame.commands);
    snapshot.payload.swap(frame.payload);
    frame.clear();
    DrawCommand next{};
    frame.setPayload(next, data);
    const CommandPayloadView published(snapshot.payload, snapshot.commands.front());
    assert(published.valid() && published.get().stencil->reference == 8);
    snapshot.clear();
    assert(snapshot.commands.empty() && snapshot.payload.empty());
}

static void invalidRecords() {
    FrameData frame;
    DrawCommand command{};
    command.payloadOffset = 8;
    assert(!CommandPayloadView(frame.payload, command).valid());
    DrawCommandPayload data;
    data.renderTarget = CommandRenderTarget{1, 1, 1};
    frame.setPayload(command, data);
    auto invalid = command;
    invalid.payloadOffset = 1;
    assert(!CommandPayloadView(frame.payload, invalid).valid());
    invalid = command;
    invalid.payloadSize = std::numeric_limits<uint32_t>::max();
    assert(!CommandPayloadView(frame.payload, invalid).valid());
    invalid = command;
    invalid.payloadSize -= 8;
    assert(!CommandPayloadView(frame.payload, invalid).valid());
    auto badBytes = frame.payload;
    badBytes[6] |= 0x80;
    assert(!CommandPayloadView(badBytes, command).valid());
    badBytes = frame.payload;
    badBytes[1] = 0xff;
    assert(!CommandPayloadView(badBytes, command).valid());

    std::vector<uint8_t> oversized(65536);
    data.drawableUBO = oversized;
    bool rejected = false;
    try {
        frame.setPayload(command, data);
    } catch (const std::length_error&) {
        rejected = true;
    }
    assert(rejected && CommandPayloadView(frame.payload, command).valid());
}

static void compaction() {
    FrameData frame;
    const std::array<uint8_t, 5> drawable{1, 2, 3, 4, 5};
    const std::array<uint8_t, 3> props{6, 7, 8};
    const std::array<uint8_t, 4> pixels{0, 1, 2, 3};
    DrawCommand unused{};
    DrawCommandPayload data;
    data.drawableUBO = drawable;
    data.propsUBO = props;
    frame.setPayload(unused, data);

    DrawCommand first{};
    data.renderTarget = CommandRenderTarget{17, 128, 64};
    frame.setPayload(first, data);
    frame.setPayload(unused, data);

    DrawCommand second{};
    data = {};
    data.texture = CommandTexture{pixels.data(), 1, 1, 9, 2, 4, TextureFilterType::Linear};
    data.stencil = CommandStencil{4, StencilModeType::ClippingTest};
    data.cameraDistance = 512.25f;
    frame.setPayload(second, data);
    frame.setPayload(unused, data);
    frame.commands = {second, first, first, DrawCommand{}};
    const auto capacity = frame.payload.capacity();
    frame.compactPayload();
    assert(frame.payload.size() == first.payloadSize + second.payloadSize);
    assert(frame.payload.capacity() == capacity);
    assert(frame.commands[0].payloadOffset == first.payloadSize);
    assert(frame.commands[1].payloadOffset == 0);
    assert(frame.commands[2].payloadOffset == 0);
    assert(frame.commands[3].payloadOffset == 0 && frame.commands[3].payloadSize == 0);
    const CommandPayloadView firstView(frame.payload, frame.commands[1]);
    const CommandPayloadView secondView(frame.payload, frame.commands[0]);
    assert(firstView.valid() && secondView.valid());
    assert(firstView.get().drawableUBO[4] == 5 && firstView.get().propsUBO[2] == 8);
    assert(firstView.get().renderTarget->id == 17 && firstView.get().renderTarget->height == 64);
    assert(!firstView.get().texture && !firstView.get().stencil && !firstView.get().cameraDistance);
    assert(secondView.get().texture->data == pixels.data());
    assert(secondView.get().texture->filter == TextureFilterType::Linear);
    assert(secondView.get().stencil->reference == 4 && secondView.get().cameraDistance == 512.25f);

    const auto compacted = frame.payload;
    frame.compactPayload();
    assert(frame.payload == compacted);
    frame.commands[0].payloadOffset = 1;
    bool rejected = false;
    try {
        frame.compactPayload();
    } catch (const std::invalid_argument&) {
        rejected = true;
    }
    assert(rejected && frame.payload == compacted);
    assert(frame.commands[1].payloadOffset == 0 && frame.commands[2].payloadOffset == 0);
    frame.commands.clear();
    frame.compactPayload();
    assert(frame.payload.empty() && frame.payload.capacity() == capacity);
}

int main() {
    optionalStorage();
    aliasingAndPublication();
    invalidRecords();
    compaction();
}

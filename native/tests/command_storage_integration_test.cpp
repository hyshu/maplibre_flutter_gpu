#include <mln/command_export/draw_command.hpp>

#include <cassert>
#include <cmath>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
}

void bridge_mergeCommands(mln::command_export::FrameData&);

using namespace mln::command_export;

static float floatAt(std::span<const uint8_t> bytes, size_t offset) {
    float value;
    std::memcpy(&value, bytes.data() + offset, sizeof(value));
    return value;
}

int main() {
    auto* session = maplibre_session_create();
    assert(session);
    maplibre_session_select(session);
    FrameData frame;
    const std::array<int16_t, 8> vertices{0, 0, 1, 0, 1, 1, 0, 1};
    const std::array<uint16_t, 6> indices{0, 1, 2, 0, 2, 3};
    std::array<float, 20> drawable{};
    drawable[0] = drawable[5] = drawable[10] = drawable[15] = 1;
    drawable[16] = 42;
    std::array<uint8_t, 48> props{};
    props[0] = 7;
    DrawCommandPayload data;
    data.drawableUBO = {reinterpret_cast<const uint8_t*>(drawable.data()), sizeof(drawable)};
    data.propsUBO = props;
    for (uint32_t i = 0; i < 2; ++i) {
        auto& command = frame.addCommand(
            ShaderType::Fill, DrawModeType::Triangles, vertices.data(), 4, 4, indices.data(), 6);
        command.layerIndex = 1;
        command.bufferId = i + 1;
        drawable[12] = static_cast<float>(i);
        frame.setPayload(command, data);
    }
    frame.payload.shrink_to_fit();
    bridge_mergeCommands(frame);
    assert(frame.commands.size() == 1);
    const auto& merged = frame.commands.front();
    assert(merged.vertexCount == 8 && merged.indexCount == 12);
    assert(merged.flags == DrawCommandFlags::CrossTileMerged);
    const CommandPayloadView mergedView(frame.payload, merged);
    assert(mergedView.valid());
    assert(frame.payload.size() == merged.payloadSize);
    assert(mergedView.get().propsUBO[0] == 7);
    assert(floatAt(mergedView.get().drawableUBO, 0) == 1.0f / 8192.0f);
    assert(floatAt(mergedView.get().drawableUBO, 64) == 42);
    const auto* mergedVertices = static_cast<const float*>(merged.vertexData);
    assert(mergedVertices[0] == 0 && mergedVertices[8] == 8192);

    frame.clear();
    for (uint32_t i = 0; i < 2; ++i) {
        auto& command = frame.addCommand(
            ShaderType::Fill, DrawModeType::Triangles, vertices.data(), 4, 4, indices.data(), 6);
        command.layerIndex = 1;
        props[0] = static_cast<uint8_t>(i);
        frame.setPayload(command, data);
    }
    bridge_mergeCommands(frame);
    assert(frame.commands.size() == 2);
    assert(CommandPayloadView(frame.payload, frame.commands[0]).get().propsUBO[0] == 0);
    assert(CommandPayloadView(frame.payload, frame.commands[1]).get().propsUBO[0] == 1);

    data.stencil = CommandStencil{1, StencilModeType::ClippingTest};
    frame.setPayload(frame.commands[0], data);
    frame.setPayload(frame.commands[1], data);
    bridge_mergeCommands(frame);
    assert(frame.commands.size() == 2);
    maplibre_session_release(session);
}

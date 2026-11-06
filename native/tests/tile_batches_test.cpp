// Contract checks for native tile batching over synthetic command frames.
#include "commands/merge_session.hpp"
#include "test_check.hpp"

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <vector>

namespace maplibre_bridge::commands {
// The test owns one session instead of the bridge's per-session registry.
MergeSessionState& mergeSession() {
    static MergeSessionState session;
    return session;
}
} // namespace maplibre_bridge::commands

namespace {
using namespace mln::command_export;
using namespace maplibre_bridge::commands;

struct Tile {
    std::array<uint32_t, 4> vertices;
    std::array<uint16_t, 6> indices{{0, 1, 2, 1, 2, 3}};
};

DrawCommand addFillMatrix(FrameData& frame,
                          const Tile& tile,
                          uint32_t bufferId,
                          uint32_t layer,
                          uint32_t stencilReference,
                          const std::array<uint8_t, 48>& props,
                          const std::array<float, 16>& matrix) {
    auto& command = frame.addCommand(ShaderType::Fill,
                                     DrawModeType::Triangles,
                                     tile.vertices.data(),
                                     sizeof(uint32_t),
                                     tile.vertices.size(),
                                     tile.indices.data(),
                                     tile.indices.size());
    command.bufferId = bufferId;
    command.bufferVersion = 1;
    command.layerIndex = layer;
    command.subLayerIndex = 0;
    std::array<float, 20> drawable{};
    std::copy(matrix.begin(), matrix.end(), drawable.begin());
    DrawCommandPayload payload;
    payload.drawableUBO = {reinterpret_cast<const uint8_t*>(drawable.data()), sizeof(drawable)};
    payload.propsUBO = props;
    payload.stencil = CommandStencil{stencilReference, StencilModeType::ClippingTest};
    frame.setPayload(command, payload);
    return command;
}

// A column-major tile matrix of uniform [scale] translated by ([tx], [ty]).
std::array<float, 16> tileMatrix(float scale, float tx = 0.0f, float ty = 0.0f) {
    std::array<float, 16> matrix{};
    matrix[0] = scale;
    matrix[5] = scale;
    matrix[10] = 1.0f;
    matrix[12] = tx;
    matrix[13] = ty;
    matrix[15] = 1.0f;
    return matrix;
}

DrawCommand addFill(FrameData& frame,
                    const Tile& tile,
                    uint32_t bufferId,
                    uint32_t layer,
                    uint32_t stencilReference,
                    const std::array<uint8_t, 48>& props,
                    float matrixScale) {
    return addFillMatrix(frame, tile, bufferId, layer, stencilReference, props, tileMatrix(matrixScale));
}

void addClear(FrameData& frame) {
    auto& command = frame.addCommand(ShaderType::ClippingMask, DrawModeType::Triangles, nullptr, 0, 0, nullptr, 0);
    DrawCommandPayload payload;
    payload.stencil = CommandStencil{0, StencilModeType::Clear};
    frame.setPayload(command, payload);
}
} // namespace

int main() {
    const Tile first{{{1, 2, 3, 4}}};
    const Tile second{{{5, 6, 7, 8}}};
    const Tile third{{{9, 10, 11, 12}}};
    std::array<uint8_t, 48> props{};
    props[0] = 0xAB;
    std::array<uint8_t, 48> otherProps{};
    otherProps[0] = 0xCD;

    FrameData frame;
    addFill(frame, first, 11, 3, 1, props, 1.0f);
    addFill(frame, second, 12, 3, 2, props, 2.0f);
    addFill(frame, third, 13, 3, 3, otherProps, 3.0f);
    addFill(frame, first, 11, 4, 1, props, 1.0f);
    batchTileCommands(frame);

    MAPLIBRE_TEST_CHECK(frame.commands.size() == 3);
    const auto& batched = frame.commands[0];
    MAPLIBRE_TEST_CHECK((batched.flags & kTileBatchedFlag) != 0);
    MAPLIBRE_TEST_CHECK(batched.vertexCount == 8);
    MAPLIBRE_TEST_CHECK(batched.indexCount == 12);
    MAPLIBRE_TEST_CHECK(batched.bufferId >= 0x80000000u);
    MAPLIBRE_TEST_CHECK(batched.layerIndex == 3);
    // Concatenated vertices keep each member's bytes, and later members'
    // indices are rebased past the earlier vertices.
    const auto* vertices = static_cast<const uint32_t*>(batched.vertexData);
    MAPLIBRE_TEST_CHECK(vertices[0] == 1 && vertices[4] == 5 && vertices[7] == 8);
    MAPLIBRE_TEST_CHECK(batched.indexData[0] == 0 && batched.indexData[6] == 4 && batched.indexData[11] == 7);
    const CommandPayloadView view(frame.payload, batched);
    MAPLIBRE_TEST_CHECK(view.valid());
    const auto& payload = view.get();
    MAPLIBRE_TEST_CHECK(payload.drawableUBO.size() == 2 * (80 + 8));
    MAPLIBRE_TEST_CHECK(!payload.stencil.has_value());
    MAPLIBRE_TEST_CHECK(payload.propsUBO.size() == 48 && payload.propsUBO[0] == 0xAB);
    float scale = 0;
    std::memcpy(&scale, payload.drawableUBO.data() + 80, sizeof(scale));
    MAPLIBRE_TEST_CHECK(scale == 2.0f);
    uint32_t table[4];
    std::memcpy(table, payload.drawableUBO.data() + 160, sizeof(table));
    MAPLIBRE_TEST_CHECK(table[0] == 0 && table[1] == 1 && table[2] == 4 && table[3] == 2);
    // Different paint and a different layer stay per-tile commands.
    MAPLIBRE_TEST_CHECK((frame.commands[1].flags & kTileBatchedFlag) == 0);
    MAPLIBRE_TEST_CHECK(frame.commands[1].bufferId == 13);
    MAPLIBRE_TEST_CHECK(frame.commands[2].layerIndex == 4);

    // The same members reuse the cached geometry identity.
    const uint32_t firstBufferId = batched.bufferId;
    FrameData again;
    addFill(again, first, 11, 3, 1, props, 1.0f);
    addFill(again, second, 12, 3, 2, props, 2.0f);
    batchTileCommands(again);
    MAPLIBRE_TEST_CHECK(again.commands.size() == 1);
    MAPLIBRE_TEST_CHECK(again.commands[0].bufferId == firstBufferId);

    // A mid-frame stencil clear keeps every command per tile.
    FrameData cleared;
    addFill(cleared, first, 11, 3, 1, props, 1.0f);
    addFill(cleared, second, 12, 3, 2, props, 2.0f);
    addClear(cleared);
    batchTileCommands(cleared);
    MAPLIBRE_TEST_CHECK(cleared.commands.size() == 3);
    MAPLIBRE_TEST_CHECK((cleared.commands[0].flags & kTileBatchedFlag) == 0);

    std::puts("Tile batching concatenation, payload table, and reuse passed");
    return 0;
}

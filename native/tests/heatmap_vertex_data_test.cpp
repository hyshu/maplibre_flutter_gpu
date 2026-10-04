#include <mln/command_export/draw_command.hpp>
#include <mln/command_export/heatmap_vertex_data.hpp>

#include <array>
#include <cassert>
#include <cstring>
#include <limits>

using namespace mln::command_export;
using namespace mln::command_export::detail;
using mln::gfx::AttributeDataType;

static float readFloat(const std::vector<uint8_t>& data, size_t offset) {
    float value;
    std::memcpy(&value, data.data() + offset, sizeof(value));
    return value;
}

int main() {
    constexpr std::array<int16_t, 4> positions{12, 13, 28, 29};
    std::array<float, 2> weights{0.25f, 2.0f};
    constexpr std::array<float, 9> radii{99, 99, 99, 99, 10, 20, 99, 30, 40};
    const auto layout = std::span<const uint8_t>(
        reinterpret_cast<const uint8_t*>(positions.data()), sizeof(positions));
    HeatmapVertexAttributes attributes{
        .weight = HeatmapAttributeData{
            .data = reinterpret_cast<const uint8_t*>(weights.data()),
            .size = sizeof(weights),
            .stride = sizeof(float),
            .type = AttributeDataType::Float,
        },
        .radius = HeatmapAttributeData{
            .data = reinterpret_cast<const uint8_t*>(radii.data()),
            .size = sizeof(radii),
            .offset = sizeof(float),
            .vertexOffset = 1,
            .stride = sizeof(float) * 3,
            .type = AttributeDataType::Float2,
        },
    };
    std::vector<uint8_t> output;
    assert(updateHeatmapVertexData(layout, 2, attributes, output) == HeatmapVertexDataUpdate::Changed);
    assert(output.size() == 40);
    assert(std::memcmp(output.data(), positions.data(), 4) == 0);
    assert(std::memcmp(output.data() + 20, positions.data() + 2, 4) == 0);
    assert(readFloat(output, 4) == 0.25f && readFloat(output, 8) == 0.25f);
    assert(readFloat(output, 24) == 2.0f && readFloat(output, 28) == 2.0f);
    assert(readFloat(output, 12) == 10.0f && readFloat(output, 16) == 20.0f);
    assert(readFloat(output, 32) == 30.0f && readFloat(output, 36) == 40.0f);
    assert(updateHeatmapVertexData(layout, 2, attributes, output) == HeatmapVertexDataUpdate::Unchanged);

    weights[1] = 0;
    assert(updateHeatmapVertexData(layout, 2, attributes, output) == HeatmapVertexDataUpdate::Changed);
    assert(readFloat(output, 24) == 0.0f && readFloat(output, 28) == 0.0f);

    attributes.radius.reset();
    assert(updateHeatmapVertexData(layout, 2, attributes, output) == HeatmapVertexDataUpdate::Changed);
    assert(readFloat(output, 12) == 0.0f && readFloat(output, 32) == 0.0f);
    const auto previous = output;

    const auto reject = [&](const HeatmapVertexAttributes& invalid, size_t count = 2) {
        assert(updateHeatmapVertexData(layout, count, invalid, output) == HeatmapVertexDataUpdate::Failed);
        assert(output == previous);
    };
    auto invalid = attributes;
    invalid.weight->size = sizeof(float);
    reject(invalid);
    invalid = attributes;
    invalid.weight->type = AttributeDataType::Short2;
    reject(invalid);
    invalid = attributes;
    invalid.weight->vertexOffset = std::numeric_limits<size_t>::max();
    reject(invalid);
    invalid = attributes;
    invalid.weight->offset = sizeof(float);
    reject(invalid);
    reject(attributes, 0);
    reject(attributes, std::numeric_limits<size_t>::max());
    reject({});

    FrameData frame;
    const auto& command = frame.addCommand(ShaderType::Heatmap, DrawModeType::Triangles, nullptr, 0, 0, nullptr, 0);
    assert(command.renderTargetId == 0 && command.renderTargetWidth == 0 && command.renderTargetHeight == 0);
    static_assert(DrawCommandFlags::HeatmapDataDrivenMask == 0x0C000000u);
}

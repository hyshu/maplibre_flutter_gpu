// Cross-tile merge: batches Fill/Background draw commands that share a
// style layer and evaluated properties into single screen-space draws.
#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "bridge_state.hpp"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <map>
#include <unordered_map>
#include <vector>

static uint64_t fnv(const void* d, size_t n) {
    uint64_t h = 14695981039346656037ULL;
    auto p = static_cast<const uint8_t*>(d);
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 1099511628211ULL; }
    return h;
}

// Storage for merged index/vertex data (lifetime: one frame)
struct MergedVertex {
    float x;
    float y;

    bool operator==(const MergedVertex& other) const {
        return x == other.x && y == other.y;
    }
};
struct MergeSessionState {
    std::vector<std::vector<uint16_t>> indices;
    std::vector<std::vector<MergedVertex>> vertices;
};

static std::map<void*, MergeSessionState> g_mergeSessions;
static MergeSessionState& mergeSession() {
    return g_mergeSessions[bridge_currentSession()];
}

void bridge_releaseMergeSession(void* session) {
    g_mergeSessions.erase(session);
}

#define g_mergedIndices mergeSession().indices
#define g_mergedVertices mergeSession().vertices

void bridge_resetMergeStorage() {
    g_mergedIndices.clear();
    g_mergedVertices.clear();
}

void bridge_mergeCommands(mbgl::command_export::FrameData& fd) {
    using namespace mbgl::command_export;
    constexpr uint32_t depthFlags =
        DrawCommandFlags::DepthTest | DrawCommandFlags::DepthWrite;
    bridge_resetMergeStorage();

    auto& commands = fd.commands;
    if (commands.empty()) return;

    // Step 0: Remove unsupported shader types
    commands.erase(std::remove_if(commands.begin(), commands.end(), [](const DrawCommand& c) {
        return c.shaderType != ShaderType::Fill &&
               c.shaderType != ShaderType::FillOutline &&
               c.shaderType != ShaderType::FillOutlineTriangulated &&
               c.shaderType != ShaderType::Background &&
               c.shaderType != ShaderType::FillExtrusion &&
               c.shaderType != ShaderType::Line &&
               c.shaderType != ShaderType::LineSDF &&
               c.shaderType != ShaderType::LineGradient &&
               c.shaderType != ShaderType::LinePattern &&
               c.shaderType != ShaderType::Circle &&
               c.shaderType != ShaderType::Raster &&
               c.shaderType != ShaderType::ClippingMask &&
               c.shaderType != ShaderType::BackgroundPattern;
    }), commands.end());

    if (commands.empty()) return;

    if (commands.size() <= 1) return;

    // Stencil clear/mask/test/replace operations form one ordered command
    // stream. Sorting individual commands can move a consumer away from the
    // mask setup it depends on (notably across opaque/translucent invocations
    // of the same style layer). Keep MapLibre's native emission order whenever
    // that stream is present. Frames without stencil retain the established
    // layer/sublayer ordering.
    const bool hasOrderedStencil = std::any_of(commands.begin(), commands.end(), [](const DrawCommand& command) {
        return command.stencilMode != StencilModeType::Disabled;
    });
    if (hasOrderedStencil) return;

    std::stable_sort(commands.begin(), commands.end(),
        [](const DrawCommand& a, const DrawCommand& b) {
            if (a.layerIndex != b.layerIndex) return a.layerIndex < b.layerIndex;
            return a.subLayerIndex < b.subLayerIndex;
        });

    // Step 2: Cross-tile merge — group constant Fill/Background by
    // (layerIndex, subLayerIndex, propsUBO).
    // Data-driven fill attributes must remain attached to their original
    // vertices, so those commands bypass this path. Depth-tested commands
    // also bypass it because this screen-space encoding preserves only x/y;
    // MapLibre's projected z/w carries the layer depth offset and varies with
    // position on pitched maps.
    // Pre-transform vertices to NDC, quantize to the signed 8192-step grid,
    // then store that grid coordinate directly as the GPU float2 input.
    // Merged commands (flags=1) are drawn with the FillMerged shader variant
    // because screen-space vertices are not tile-local.
    struct GK {
        uint32_t layer;
        int32_t subLayer;
        ShaderType s;
        uint64_t ph;
        bool operator==(const GK& o) const {
            return layer == o.layer && subLayer == o.subLayer && s == o.s && ph == o.ph;
        }
    };
    struct GKH {
        size_t operator()(const GK& k) const {
            return size_t(k.layer) * 2654435761u ^
                   std::hash<int32_t>()(k.subLayer) * 131u ^
                   size_t(k.s) * 31u ^
                   (std::hash<uint64_t>()(k.ph) * 37u);
        }
    };
    std::vector<DrawCommand> result;
    result.reserve(commands.size());

    // Expand vertices: transform by matrix, quantize NDC, export float2.
    auto expandVertices = [](const DrawCommand& cmd, std::vector<MergedVertex>& verts) {
        const float* mat = reinterpret_cast<const float*>(cmd.drawableUBO);
        const auto* src = static_cast<const uint8_t*>(cmd.vertexData);
        const uint32_t stride = cmd.vertexStride;
        for (uint32_t i = 0; i < cmd.vertexCount; i++) {
            uint32_t packed = *reinterpret_cast<const uint32_t*>(src + i * stride);
            float fx = static_cast<float>(static_cast<int16_t>(packed & 0xFFFF));
            float fy = static_cast<float>(static_cast<int16_t>(packed >> 16));
            float cx = mat[0]*fx + mat[4]*fy + mat[12];
            float cy = mat[1]*fx + mat[5]*fy + mat[13];
            float cw = mat[3]*fx + mat[7]*fy + mat[15];
            if (cw != 0.0f) { cx /= cw; cy /= cw; }
            // Signed symmetric quantization: 8192 steps per NDC unit (2x the
            // precision of the old biased 4096). Store the quantized values
            // as floats so Dart can upload them without per-frame repacking.
            // +0.5/-0.5 rounds instead of truncating.
            int16_t ox = static_cast<int16_t>(std::clamp(cx * 8192.0f + (cx >= 0 ? 0.5f : -0.5f), -32767.0f, 32767.0f));
            int16_t oy = static_cast<int16_t>(std::clamp(cy * 8192.0f + (cy >= 0 ? 0.5f : -0.5f), -32767.0f, 32767.0f));
            verts.push_back({
                static_cast<float>(ox),
                static_cast<float>(oy),
            });
        }
    };

    // Pass 1: Build groups by
    // (layerIndex, subLayerIndex, shaderType, propsUBO hash).
    // Hash/compare the actual propsUBOSize (clamped to the embedded buffer)
    // so commands with different UBO sizes never merge.
    std::unordered_map<GK, std::vector<size_t>, GKH> groups;
    for (size_t ci = 0; ci < commands.size(); ci++) {
        auto& cmd = commands[ci];
        if (cmd.shaderType == ShaderType::Fill) {
            if ((cmd.flags & DrawCommandFlags::FillDataDrivenMask) != 0) continue;
        } else if (cmd.shaderType != ShaderType::Background) {
            continue;
        }
        // A merged draw has only one stencil reference, while tile-clipped
        // commands carry one reference per source tile. Mask, test, 3D write,
        // and clear commands are all ordering barriers and never merge.
        if (cmd.stencilMode != StencilModeType::Disabled) continue;
        if ((cmd.flags & depthFlags) != 0) continue;
        const uint32_t pn = std::min<uint32_t>(cmd.propsUBOSize, sizeof(cmd.propsUBO));
        uint64_t ph = fnv(cmd.propsUBO, pn) ^ (static_cast<uint64_t>(pn) << 56);
        GK key{
            cmd.layerIndex,
            cmd.subLayerIndex,
            cmd.shaderType,
            ph,
        };
        auto it = groups.find(key);
        if (it != groups.end()) {
            const auto& first = commands[it->second[0]];
            if (first.propsUBOSize == cmd.propsUBOSize &&
                std::memcmp(first.propsUBO, cmd.propsUBO, pn) == 0) {
                it->second.push_back(ci);
                continue;
            }
        }
        groups[key] = {ci};
    }

    // Pass 2: For multi-command groups, expand vertices and build merged VB+IB
    std::vector<bool> consumed(commands.size(), false);
    // Map: first cmd index -> list of (vi, ii, vCount) sub-batches
    struct SubBatch { size_t vi, ii; uint32_t vCount; };
    std::unordered_map<size_t, std::vector<SubBatch>> mergedBatches;

    auto setupMergedMatrix = [](DrawCommand& cmd) {
        std::memset(cmd.drawableUBO, 0, 64);
        auto* m = reinterpret_cast<float*>(cmd.drawableUBO);
        m[0] = 1.0f/8192.0f; m[5] = 1.0f/8192.0f; m[10] = 1.0f;
        m[15] = 1.0f;
    };

    for (auto& [key, idxs] : groups) {
        if (idxs.size() <= 1) continue;
        // Mark all but first as consumed
        for (size_t i = 1; i < idxs.size(); i++) consumed[idxs[i]] = true;

        auto& subs = mergedBatches[idxs[0]];
        size_t vi = g_mergedVertices.size();
        size_t ii = g_mergedIndices.size();
        g_mergedVertices.emplace_back();
        g_mergedIndices.emplace_back();
        uint32_t bv = 0;

        for (size_t ci : idxs) {
            auto& cmd = commands[ci];
            if (bv + cmd.vertexCount > 65535) {
                subs.push_back({vi, ii, bv});
                vi = g_mergedVertices.size();
                ii = g_mergedIndices.size();
                g_mergedVertices.emplace_back();
                g_mergedIndices.emplace_back();
                bv = 0;
            }
            expandVertices(cmd, g_mergedVertices[vi]);
            // Append indices, skipping degenerate triangles
            // (where 2+ vertices collapsed to same int16 position)
            auto& vb = g_mergedVertices[vi];
            auto& ib = g_mergedIndices[ii];
            uint32_t base = bv;
            for (uint32_t i = 0; i + 2 < cmd.indexCount; i += 3) {
                uint32_t i0 = cmd.indexData[i] + base;
                uint32_t i1 = cmd.indexData[i+1] + base;
                uint32_t i2 = cmd.indexData[i+2] + base;
                // Skip if any two vertices have same packed position
                if (vb[i0] == vb[i1] || vb[i1] == vb[i2] || vb[i0] == vb[i2])
                    continue;
                ib.push_back(static_cast<uint16_t>(i0));
                ib.push_back(static_cast<uint16_t>(i1));
                ib.push_back(static_cast<uint16_t>(i2));
            }
            bv += cmd.vertexCount;
        }
        if (bv > 0) subs.push_back({vi, ii, bv});
    }

    // Pass 3: Emit commands in order, replacing merged groups
    for (size_t ci = 0; ci < commands.size(); ci++) {
        if (consumed[ci]) continue;
        auto mIt = mergedBatches.find(ci);
        if (mIt != mergedBatches.end()) {
            for (auto& sb : mIt->second) {
                DrawCommand merged = commands[ci];
                merged.vertexData = g_mergedVertices[sb.vi].data();
                merged.vertexCount = sb.vCount;
                merged.vertexStride = sizeof(MergedVertex);
                merged.indexData = g_mergedIndices[sb.ii].data();
                merged.indexCount = static_cast<uint32_t>(g_mergedIndices[sb.ii].size());
                merged.flags = DrawCommandFlags::CrossTileMerged;
                setupMergedMatrix(merged);
                result.push_back(merged);
            }
        } else {
            result.push_back(commands[ci]);
        }
    }

    commands = std::move(result);
}

#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

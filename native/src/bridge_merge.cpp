// Cross-tile merge: batches Fill/Background draw commands that share a
// style layer and evaluated properties into single screen-space draws.
#if MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "bridge_state.hpp"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <functional>
#include <limits>
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

// Data-driven fill-extrusion vertices keep their packed layout prefix and
// float base/height ranges. The bridge packs four color integers into two
// uint32 words so Flutter GPU uploads 36 bytes instead of 44 bytes per vertex.
struct FillExtrusionGpuKey {
    uint32_t bufferId;
    uint32_t bufferVersion;
    const void* vertexData;
    uint32_t vertexCount;

    bool operator<(const FillExtrusionGpuKey& other) const {
        if (bufferId != other.bufferId) return bufferId < other.bufferId;
        if (bufferVersion != other.bufferVersion) return bufferVersion < other.bufferVersion;
        if (vertexData != other.vertexData) {
            return std::less<const void*>{}(vertexData, other.vertexData);
        }
        return vertexCount < other.vertexCount;
    }
};

struct PreparedFillExtrusionVertices {
    std::vector<uint8_t> bytes;
    uint64_t lastUsedFrame = 0;
};

// Data-driven line vertices keep the bridge-expanded 120-byte layout for now.
// Constant line-family vertices remain in Command Export's packed 8-byte
// layout and are decoded directly by the Flutter GPU vertex shaders.
struct LineGpuKey {
    uint32_t bufferId;
    uint32_t bufferVersion;
    const void* vertexData;
    uint32_t vertexCount;
    uint32_t vertexStride;

    bool operator<(const LineGpuKey& other) const {
        if (bufferId != other.bufferId) return bufferId < other.bufferId;
        if (bufferVersion != other.bufferVersion) return bufferVersion < other.bufferVersion;
        if (vertexData != other.vertexData) {
            return std::less<const void*>{}(vertexData, other.vertexData);
        }
        if (vertexCount != other.vertexCount) return vertexCount < other.vertexCount;
        return vertexStride < other.vertexStride;
    }
};

struct PreparedLineVertices {
    std::vector<uint8_t> bytes;
    uint64_t lastUsedFrame = 0;
};

// GPU-ready bridge storage has a different pointer from command_export's
// renderer-owned vertex memory. Give each source drawable segment a stable
// bridge-side bufferId so Dart can key the uploaded GPU buffer independently
// of the prepared std::vector address. The original bufferVersion is preserved,
// so content changes retain the normal superseded-generation semantics.
struct PreparedBufferIds {
    std::vector<uint32_t> segmentIds;
    uint64_t lastUsedFrame = 0;
};

struct MergeSessionState {
    std::vector<std::vector<uint16_t>> indices;
    std::vector<std::vector<MergedVertex>> vertices;
    std::map<FillExtrusionGpuKey, PreparedFillExtrusionVertices> fillExtrusionGpuVertices;
    std::map<LineGpuKey, PreparedLineVertices> lineGpuVertices;
    std::map<uint32_t, PreparedBufferIds> preparedBufferIds;
    uint32_t nextPreparedBufferId = 1;
    uint64_t frame = 0;
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
    auto& session = mergeSession();
    session.indices.clear();
    session.vertices.clear();
    ++session.frame;
}

namespace {
constexpr uint32_t kFillExtrusionSourceStride = 44;
constexpr uint32_t kFillExtrusionPackedColorGpuStride = 36;
constexpr uint32_t kLinePackedStride = 8;
constexpr uint32_t kLineDataDrivenPackedStride = 88;
constexpr uint32_t kLineGpuStride = 24;
constexpr uint32_t kLineDataDrivenGpuStride = 120;
// Bridge-only transport bits. command_export currently owns bits 0..23; Dart
// treats these only as vertex-layout markers and never forwards them to a
// shader-facing data-driven mask.
constexpr uint32_t kLineGpuReadyFlag = 1u << 25;
constexpr uint32_t kFillExtrusionPackedColorGpuReadyFlag = 1u << 26;
constexpr uint64_t kFillExtrusionGpuRetentionFrames = 1800;
constexpr uint64_t kLineGpuRetentionFrames = 60;
constexpr uint64_t kPreparedBufferIdRetentionFrames = 1800;
constexpr size_t kFillExtrusionGpuCacheBudgetBytes = 64 * 1024 * 1024;
constexpr size_t kLineGpuCacheBudgetBytes = 64 * 1024 * 1024;
constexpr uint32_t kPreparedBufferIdNamespace = 0x80000000u;
constexpr uint32_t kPreparedBufferIdValueMask = 0x7fffffffu;
static_assert(sizeof(float) == 4);
static_assert(sizeof(int16_t) == 2);
static_assert(sizeof(uint16_t) == 2);

uint32_t preparedBufferIdFor(MergeSessionState& session,
                             uint32_t sourceBufferId,
                             uint32_t segmentOrdinal) {
    auto& prepared = session.preparedBufferIds[sourceBufferId];
    prepared.lastUsedFrame = session.frame;
    while (prepared.segmentIds.size() <= segmentOrdinal) {
        uint32_t value = session.nextPreparedBufferId++ & kPreparedBufferIdValueMask;
        if (value == 0) {
            value = session.nextPreparedBufferId++ & kPreparedBufferIdValueMask;
        }
        prepared.segmentIds.push_back(kPreparedBufferIdNamespace | value);
    }
    return prepared.segmentIds[segmentOrdinal];
}

void trimPreparedBufferIds(MergeSessionState& session) {
    for (auto it = session.preparedBufferIds.begin(); it != session.preparedBufferIds.end();) {
        const auto age = session.frame - it->second.lastUsedFrame;
        if (it->second.lastUsedFrame != session.frame && age >= kPreparedBufferIdRetentionFrames) {
            it = session.preparedBufferIds.erase(it);
        } else {
            ++it;
        }
    }
}

uint16_t packFillExtrusionColorValue(float value) {
    if (!(value > 0.0f)) return 0;
    if (value >= 65535.0f) return 65535;
    return static_cast<uint16_t>(value);
}

bool packFillExtrusionGpuVertices(const mbgl::command_export::DrawCommand& command,
                                  std::vector<uint8_t>& output) {
    if (!command.vertexData || command.vertexCount == 0 ||
        command.vertexStride != kFillExtrusionSourceStride ||
        command.vertexCount >
            std::numeric_limits<size_t>::max() / kFillExtrusionPackedColorGpuStride) {
        return false;
    }

    const auto* source = static_cast<const uint8_t*>(command.vertexData);
    output.resize(
        static_cast<size_t>(command.vertexCount) * kFillExtrusionPackedColorGpuStride);
    for (uint32_t vertex = 0; vertex < command.vertexCount; ++vertex) {
        const auto* src = source + static_cast<size_t>(vertex) * kFillExtrusionSourceStride;
        auto* dst = output.data() +
                    static_cast<size_t>(vertex) * kFillExtrusionPackedColorGpuStride;

        std::memcpy(dst, src, 28);
        float colorRange[4];
        std::memcpy(colorRange, src + 28, sizeof(colorRange));
        const uint32_t packedColors[2] = {
            static_cast<uint32_t>(packFillExtrusionColorValue(colorRange[0])) |
                (static_cast<uint32_t>(packFillExtrusionColorValue(colorRange[1])) << 16),
            static_cast<uint32_t>(packFillExtrusionColorValue(colorRange[2])) |
                (static_cast<uint32_t>(packFillExtrusionColorValue(colorRange[3])) << 16),
        };
        std::memcpy(dst + 28, packedColors, sizeof(packedColors));
    }
    return true;
}

void trimFillExtrusionGpuCache(MergeSessionState& session) {
    size_t totalBytes = 0;
    for (auto it = session.fillExtrusionGpuVertices.begin(); it != session.fillExtrusionGpuVertices.end();) {
        const auto age = session.frame - it->second.lastUsedFrame;
        if (it->second.lastUsedFrame != session.frame && age >= kFillExtrusionGpuRetentionFrames) {
            it = session.fillExtrusionGpuVertices.erase(it);
        } else {
            totalBytes += it->second.bytes.size();
            ++it;
        }
    }

    while (totalBytes > kFillExtrusionGpuCacheBudgetBytes) {
        auto victim = session.fillExtrusionGpuVertices.end();
        for (auto it = session.fillExtrusionGpuVertices.begin();
             it != session.fillExtrusionGpuVertices.end(); ++it) {
            if (it->second.lastUsedFrame == session.frame) continue;
            if (victim == session.fillExtrusionGpuVertices.end() ||
                it->second.lastUsedFrame < victim->second.lastUsedFrame) {
                victim = it;
            }
        }
        if (victim == session.fillExtrusionGpuVertices.end()) break;
        totalBytes -= victim->second.bytes.size();
        session.fillExtrusionGpuVertices.erase(victim);
    }
}

void prepareFillExtrusionGpuVertices(std::vector<mbgl::command_export::DrawCommand>& commands) {
    using namespace mbgl::command_export;
    auto& session = mergeSession();
    std::unordered_map<uint32_t, uint32_t> segmentOrdinals;
    for (auto& command : commands) {
        if (command.shaderType != ShaderType::FillExtrusion ||
            (command.flags & DrawCommandFlags::FillExtrusionDataDriven) == 0 ||
            command.vertexStride != kFillExtrusionSourceStride || !command.vertexData ||
            command.vertexCount == 0) {
            continue;
        }

        const uint32_t sourceBufferId = command.bufferId;
        const uint32_t segmentOrdinal = segmentOrdinals[sourceBufferId]++;
        const FillExtrusionGpuKey key{
            sourceBufferId,
            command.bufferVersion,
            command.vertexData,
            command.vertexCount,
        };
        auto it = session.fillExtrusionGpuVertices.find(key);
        if (it == session.fillExtrusionGpuVertices.end()) {
            PreparedFillExtrusionVertices prepared;
            if (!packFillExtrusionGpuVertices(command, prepared.bytes)) continue;
            prepared.lastUsedFrame = session.frame;
            it = session.fillExtrusionGpuVertices.emplace(key, std::move(prepared)).first;
        } else {
            it->second.lastUsedFrame = session.frame;
        }

        command.bufferId = preparedBufferIdFor(session, sourceBufferId, segmentOrdinal);
        command.vertexData = it->second.bytes.data();
        command.vertexStride = kFillExtrusionPackedColorGpuStride;
        command.flags |= kFillExtrusionPackedColorGpuReadyFlag;
    }
    trimFillExtrusionGpuCache(session);
}

bool isLineShader(mbgl::command_export::ShaderType shader) {
    using mbgl::command_export::ShaderType;
    return shader == ShaderType::Line || shader == ShaderType::LineSDF ||
           shader == ShaderType::LineGradient || shader == ShaderType::LinePattern;
}

bool expandLineVertices(const mbgl::command_export::DrawCommand& command,
                        std::vector<uint8_t>& output) {
    using namespace mbgl::command_export;
    const bool dataDriven = (command.flags & DrawCommandFlags::LineDataDrivenMask) != 0;
    const uint32_t sourceStride = dataDriven ? kLineDataDrivenPackedStride : kLinePackedStride;
    const uint32_t targetStride = dataDriven ? kLineDataDrivenGpuStride : kLineGpuStride;
    if (!command.vertexData || command.vertexCount == 0 || command.vertexStride != sourceStride ||
        command.vertexCount > std::numeric_limits<size_t>::max() / targetStride) {
        return false;
    }

    const auto* source = static_cast<const uint8_t*>(command.vertexData);
    output.resize(static_cast<size_t>(command.vertexCount) * targetStride);
    for (uint32_t vertex = 0; vertex < command.vertexCount; ++vertex) {
        const auto* src = source + static_cast<size_t>(vertex) * sourceStride;
        auto* dst = output.data() + static_cast<size_t>(vertex) * targetStride;

        int16_t position[2];
        std::memcpy(position, src, sizeof(position));
        const float layout[6] = {
            static_cast<float>(position[0]),
            static_cast<float>(position[1]),
            static_cast<float>(src[4]),
            static_cast<float>(src[5]),
            static_cast<float>(src[6]),
            static_cast<float>(src[7]),
        };
        std::memcpy(dst, layout, sizeof(layout));

        if (!dataDriven) continue;
        std::memcpy(dst + 24, src + 8, 64);

        uint16_t patternFrom[4];
        uint16_t patternTo[4];
        std::memcpy(patternFrom, src + 72, sizeof(patternFrom));
        std::memcpy(patternTo, src + 80, sizeof(patternTo));
        const float pattern[8] = {
            static_cast<float>(patternFrom[0]),
            static_cast<float>(patternFrom[1]),
            static_cast<float>(patternFrom[2]),
            static_cast<float>(patternFrom[3]),
            static_cast<float>(patternTo[0]),
            static_cast<float>(patternTo[1]),
            static_cast<float>(patternTo[2]),
            static_cast<float>(patternTo[3]),
        };
        std::memcpy(dst + 88, pattern, sizeof(pattern));
    }
    return true;
}

void trimLineGpuCache(MergeSessionState& session) {
    size_t totalBytes = 0;
    for (auto it = session.lineGpuVertices.begin(); it != session.lineGpuVertices.end();) {
        const auto age = session.frame - it->second.lastUsedFrame;
        if (it->second.lastUsedFrame != session.frame && age >= kLineGpuRetentionFrames) {
            it = session.lineGpuVertices.erase(it);
        } else {
            totalBytes += it->second.bytes.size();
            ++it;
        }
    }

    while (totalBytes > kLineGpuCacheBudgetBytes) {
        auto victim = session.lineGpuVertices.end();
        for (auto it = session.lineGpuVertices.begin(); it != session.lineGpuVertices.end(); ++it) {
            if (it->second.lastUsedFrame == session.frame) continue;
            if (victim == session.lineGpuVertices.end() ||
                it->second.lastUsedFrame < victim->second.lastUsedFrame) {
                victim = it;
            }
        }
        if (victim == session.lineGpuVertices.end()) break;
        totalBytes -= victim->second.bytes.size();
        session.lineGpuVertices.erase(victim);
    }
}

void prepareLineGpuVertices(std::vector<mbgl::command_export::DrawCommand>& commands) {
    using namespace mbgl::command_export;
    auto& session = mergeSession();
    std::unordered_map<uint32_t, uint32_t> segmentOrdinals;
    for (auto& command : commands) {
        if (!isLineShader(command.shaderType) || !command.vertexData || command.vertexCount == 0) {
            continue;
        }

        const bool dataDriven = (command.flags & DrawCommandFlags::LineDataDrivenMask) != 0;
        if (!dataDriven) continue;
        const uint32_t sourceStride = kLineDataDrivenPackedStride;
        const uint32_t targetStride = kLineDataDrivenGpuStride;
        if (command.vertexStride != sourceStride) continue;

        const uint32_t sourceBufferId = command.bufferId;
        const uint32_t segmentOrdinal = segmentOrdinals[sourceBufferId]++;
        const LineGpuKey key{
            sourceBufferId,
            command.bufferVersion,
            command.vertexData,
            command.vertexCount,
            command.vertexStride,
        };
        auto it = session.lineGpuVertices.find(key);
        if (it == session.lineGpuVertices.end()) {
            PreparedLineVertices prepared;
            if (!expandLineVertices(command, prepared.bytes)) continue;
            prepared.lastUsedFrame = session.frame;
            it = session.lineGpuVertices.emplace(key, std::move(prepared)).first;
        } else {
            it->second.lastUsedFrame = session.frame;
        }

        command.bufferId = preparedBufferIdFor(session, sourceBufferId, segmentOrdinal);
        command.vertexData = it->second.bytes.data();
        command.vertexStride = targetStride;
        command.flags |= kLineGpuReadyFlag;
    }
    trimLineGpuCache(session);
    trimPreparedBufferIds(session);
}
} // namespace

void bridge_mergeCommands(mbgl::command_export::FrameData& fd) {
    using namespace mbgl::command_export;
    constexpr uint32_t depthFlags =
        DrawCommandFlags::DepthTest | DrawCommandFlags::DepthWrite;
    bridge_resetMergeStorage();

    auto& commands = fd.commands;
    if (commands.empty()) return;

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

    prepareFillExtrusionGpuVertices(commands);
    prepareLineGpuVertices(commands);

    if (commands.size() <= 1) return;

    const bool hasOrderedStencil = std::any_of(commands.begin(), commands.end(), [](const DrawCommand& command) {
        return command.stencilMode != StencilModeType::Disabled;
    });
    if (hasOrderedStencil) return;

    std::stable_sort(commands.begin(), commands.end(),
        [](const DrawCommand& a, const DrawCommand& b) {
            if (a.layerIndex != b.layerIndex) return a.layerIndex < b.layerIndex;
            return a.subLayerIndex < b.subLayerIndex;
        });

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
            int16_t ox = static_cast<int16_t>(std::clamp(cx * 8192.0f + (cx >= 0 ? 0.5f : -0.5f), -32767.0f, 32767.0f));
            int16_t oy = static_cast<int16_t>(std::clamp(cy * 8192.0f + (cy >= 0 ? 0.5f : -0.5f), -32767.0f, 32767.0f));
            verts.push_back({
                static_cast<float>(ox),
                static_cast<float>(oy),
            });
        }
    };

    std::unordered_map<GK, std::vector<size_t>, GKH> groups;
    for (size_t ci = 0; ci < commands.size(); ci++) {
        auto& cmd = commands[ci];
        if (cmd.shaderType == ShaderType::Fill) {
            if ((cmd.flags & DrawCommandFlags::FillDataDrivenMask) != 0) continue;
        } else if (cmd.shaderType != ShaderType::Background) {
            continue;
        }
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

    std::vector<bool> consumed(commands.size(), false);
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
            auto& vb = g_mergedVertices[vi];
            auto& ib = g_mergedIndices[ii];
            uint32_t base = bv;
            for (uint32_t i = 0; i + 2 < cmd.indexCount; i += 3) {
                uint32_t i0 = cmd.indexData[i] + base;
                uint32_t i1 = cmd.indexData[i+1] + base;
                uint32_t i2 = cmd.indexData[i+2] + base;
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

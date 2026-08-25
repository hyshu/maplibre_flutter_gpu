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
#include <optional>
#include <unordered_map>
#include <utility>
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

// Content-addressed fill-extrusion identities are cached by the native source
// generation so steady frames never rescan large 44-byte vertex streams. A
// recreated Drawable/bucket gets a different source key and is hashed once;
// identical final bytes reproduce the same exported GPU identity.
struct FillExtrusionContentSourceKey {
    uint32_t bufferId;
    uint32_t bufferVersion;
    const void* vertexData;
    uint32_t vertexCount;
    uint32_t vertexStride;
    const void* indexData;
    uint32_t indexCount;
    uint32_t layerIndex;

    bool operator<(const FillExtrusionContentSourceKey& other) const {
        if (bufferId != other.bufferId) return bufferId < other.bufferId;
        if (bufferVersion != other.bufferVersion) return bufferVersion < other.bufferVersion;
        if (vertexData != other.vertexData) {
            return std::less<const void*>{}(vertexData, other.vertexData);
        }
        if (vertexCount != other.vertexCount) return vertexCount < other.vertexCount;
        if (vertexStride != other.vertexStride) return vertexStride < other.vertexStride;
        if (indexData != other.indexData) {
            return std::less<const void*>{}(indexData, other.indexData);
        }
        if (indexCount != other.indexCount) return indexCount < other.indexCount;
        return layerIndex < other.layerIndex;
    }
};

struct FillExtrusionHashFingerprint {
    uint64_t first = 0;
    uint64_t second = 0;

    bool operator<(const FillExtrusionHashFingerprint& other) const {
        if (first != other.first) return first < other.first;
        return second < other.second;
    }
};

struct FillExtrusionContentIdentity {
    uint32_t bufferId = 0;
    uint32_t bufferVersion = 0;
    uint64_t lastUsedFrame = 0;
    FillExtrusionHashFingerprint structuralFingerprint;
    FillExtrusionHashFingerprint contentFingerprint;
};

struct FillExtrusionContentVersion {
    uint32_t version = 0;
    uint64_t lastUsedFrame = 0;
};

struct FillExtrusionStructuralIdentity {
    uint32_t bufferId = 0;
    uint64_t lastUsedFrame = 0;
    std::map<FillExtrusionHashFingerprint, FillExtrusionContentVersion> contentVersions;
    std::map<uint32_t, FillExtrusionHashFingerprint> versionContents;
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

// GPU-ready bridge line segments use stable IDs so Dart can retain device
// buffers when bridge-expanded native storage moves within the same generation.
struct PreparedBufferIds {
    std::vector<uint32_t> segmentIds;
    uint64_t lastUsedFrame = 0;
};

struct MergeSessionState {
    std::vector<std::vector<uint16_t>> indices;
    std::vector<std::vector<MergedVertex>> vertices;
    std::map<FillExtrusionContentSourceKey, FillExtrusionContentIdentity> fillExtrusionContentIdentities;
    std::map<FillExtrusionHashFingerprint, FillExtrusionStructuralIdentity>
        fillExtrusionStructuralIdentities;
    std::map<uint32_t, FillExtrusionHashFingerprint> fillExtrusionStructuralIds;
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
constexpr uint32_t kFillExtrusionConstantStride = 12;
constexpr uint32_t kFillExtrusionPackedStride = 44;
constexpr uint32_t kLinePackedStride = 8;
constexpr uint32_t kLineDataDrivenPackedStride = 88;
constexpr uint32_t kLineGpuStride = 24;
constexpr uint32_t kLineDataDrivenGpuStride = 120;
// Bridge-only transport bits. command_export currently owns bits 0..23. Dart
// treats these only as vertex-layout markers and never forwards them to a
// shader-facing data-driven mask.
constexpr uint32_t kLineGpuReadyFlag = 1u << 25;
constexpr uint64_t kFillExtrusionContentSourceRetentionFrames = 120;
constexpr uint64_t kFillExtrusionIdentityRetentionFrames = 1800;
constexpr uint64_t kLineGpuRetentionFrames = 60;
constexpr uint64_t kPreparedBufferIdRetentionFrames = 600;
constexpr size_t kLineGpuCacheBudgetBytes = 64 * 1024 * 1024;
constexpr uint32_t kPreparedBufferIdNamespace = 0x80000000u;
constexpr uint32_t kPreparedBufferIdValueMask = 0x7fffffffu;
constexpr uint32_t kContentAddressedFillExtrusionNamespace = 0xC0000000u;
constexpr uint32_t kContentAddressedFillExtrusionValueMask = 0x3fffffffu;
static_assert(sizeof(float) == 4);
static_assert(sizeof(int16_t) == 2);
static_assert(sizeof(uint16_t) == 2);

struct ContentHashState {
    uint64_t first;
    uint64_t second;
};

uint64_t rotateLeft64(uint64_t value, unsigned shift) {
    return (value << shift) | (value >> (64u - shift));
}

uint64_t avalanche64(uint64_t value) {
    value ^= value >> 30;
    value *= 0xbf58476d1ce4e5b9ULL;
    value ^= value >> 27;
    value *= 0x94d049bb133111ebULL;
    value ^= value >> 31;
    return value;
}

void hashBytes(ContentHashState& state, const void* data, size_t size) {
    const auto* bytes = static_cast<const uint8_t*>(data);
    size_t offset = 0;
    while (offset + sizeof(uint64_t) <= size) {
        uint64_t word;
        std::memcpy(&word, bytes + offset, sizeof(word));
        state.first ^= avalanche64(word + 0x517cc1b727220a95ULL);
        state.first = rotateLeft64(state.first, 27) * 0x9e3779b185ebca87ULL;
        state.second ^= avalanche64(word + 0x94d049bb133111ebULL);
        state.second = rotateLeft64(state.second, 31) * 0xc2b2ae3d27d4eb4fULL;
        offset += sizeof(uint64_t);
    }
    if (offset < size) {
        uint64_t tail = 0;
        std::memcpy(&tail, bytes + offset, size - offset);
        state.first ^= avalanche64(tail + 0x27d4eb2f165667c5ULL);
        state.second ^= avalanche64(tail + 0x165667b19e3779f9ULL);
    }
    state.first = avalanche64(state.first ^ static_cast<uint64_t>(size));
    state.second = avalanche64(state.second ^ (static_cast<uint64_t>(size) << 1));
}

FillExtrusionHashFingerprint fingerprintFor(const ContentHashState& state) {
    return {
        avalanche64(state.first ^ rotateLeft64(state.second, 23)),
        avalanche64(state.second ^ rotateLeft64(state.first, 37)),
    };
}

uint32_t fillExtrusionBufferIdFor(
    MergeSessionState& session,
    const FillExtrusionHashFingerprint& fingerprint) {
    const auto found = session.fillExtrusionStructuralIdentities.find(fingerprint);
    if (found != session.fillExtrusionStructuralIdentities.end()) {
        found->second.lastUsedFrame = session.frame;
        return found->second.bufferId;
    }

    uint64_t candidate = avalanche64(fingerprint.first ^ rotateLeft64(fingerprint.second, 17));
    while (true) {
        uint32_t value = static_cast<uint32_t>(candidate) & kContentAddressedFillExtrusionValueMask;
        if (value == 0) value = 1;
        const uint32_t bufferId = kContentAddressedFillExtrusionNamespace | value;
        const auto occupied = session.fillExtrusionStructuralIds.find(bufferId);
        if (occupied == session.fillExtrusionStructuralIds.end()) {
            FillExtrusionStructuralIdentity identity;
            identity.bufferId = bufferId;
            identity.lastUsedFrame = session.frame;
            session.fillExtrusionStructuralIdentities.emplace(fingerprint, std::move(identity));
            session.fillExtrusionStructuralIds.emplace(bufferId, fingerprint);
            return bufferId;
        }
        if (!(fingerprint < occupied->second) && !(occupied->second < fingerprint)) {
            return bufferId;
        }
        candidate = avalanche64(candidate + 0x9e3779b97f4a7c15ULL);
    }
}

uint32_t fillExtrusionBufferVersionFor(
    MergeSessionState& session,
    const FillExtrusionHashFingerprint& structuralFingerprint,
    const FillExtrusionHashFingerprint& contentFingerprint) {
    auto& structural = session.fillExtrusionStructuralIdentities.at(structuralFingerprint);
    structural.lastUsedFrame = session.frame;
    const auto found = structural.contentVersions.find(contentFingerprint);
    if (found != structural.contentVersions.end()) {
        found->second.lastUsedFrame = session.frame;
        return found->second.version;
    }

    uint64_t candidate = avalanche64(contentFingerprint.first ^ rotateLeft64(contentFingerprint.second, 29));
    while (true) {
        uint32_t version = static_cast<uint32_t>(candidate ^ (candidate >> 32));
        if (version == 0) version = 1;
        const auto occupied = structural.versionContents.find(version);
        if (occupied == structural.versionContents.end()) {
            structural.contentVersions.emplace(
                contentFingerprint,
                FillExtrusionContentVersion{version, session.frame});
            structural.versionContents.emplace(version, contentFingerprint);
            return version;
        }
        if (!(contentFingerprint < occupied->second) && !(occupied->second < contentFingerprint)) {
            return version;
        }
        candidate = avalanche64(candidate + 0xc2b2ae3d27d4eb4fULL);
    }
}

std::optional<FillExtrusionContentIdentity> fillExtrusionContentIdentityFor(
    MergeSessionState& session,
    const mbgl::command_export::DrawCommand& command) {
    if (!command.vertexData || !command.indexData || command.vertexCount == 0 || command.indexCount == 0 ||
        command.vertexStride == 0 ||
        command.vertexCount > std::numeric_limits<size_t>::max() / command.vertexStride ||
        command.indexCount > std::numeric_limits<size_t>::max() / sizeof(uint16_t)) {
        return std::nullopt;
    }

    const FillExtrusionContentSourceKey sourceKey{
        command.bufferId,
        command.bufferVersion,
        command.vertexData,
        command.vertexCount,
        command.vertexStride,
        command.indexData,
        command.indexCount,
        command.layerIndex,
    };
    const auto found = session.fillExtrusionContentIdentities.find(sourceKey);
    if (found != session.fillExtrusionContentIdentities.end()) {
        found->second.lastUsedFrame = session.frame;
        const auto structural =
            session.fillExtrusionStructuralIdentities.find(found->second.structuralFingerprint);
        if (structural != session.fillExtrusionStructuralIdentities.end()) {
            structural->second.lastUsedFrame = session.frame;
            const auto content =
                structural->second.contentVersions.find(found->second.contentFingerprint);
            if (content != structural->second.contentVersions.end()) {
                content->second.lastUsedFrame = session.frame;
            }
        }
        return found->second;
    }

    const size_t vertexBytes = static_cast<size_t>(command.vertexCount) * command.vertexStride;
    const size_t indexBytes = static_cast<size_t>(command.indexCount) * sizeof(uint16_t);

    // bufferId is structural: it intentionally excludes FE paint ranges so a
    // feature-state/paint update remains the same resource ID with a new
    // generation. Index topology plus counts/layer are stable across recreated
    // buckets for the same geometry.
    ContentHashState structural{
        0x243f6a8885a308d3ULL ^ static_cast<uint64_t>(command.vertexCount),
        0x13198a2e03707344ULL ^ static_cast<uint64_t>(command.indexCount),
    };
    hashBytes(structural, command.indexData, indexBytes);
    structural.first ^= static_cast<uint64_t>(command.vertexStride) << 32;
    structural.second ^= static_cast<uint64_t>(command.layerIndex) << 24;
    const auto structuralFingerprint = fingerprintFor(structural);

    // bufferVersion is content-addressed from the exact GPU vertex/index bytes.
    // Recreated native allocations therefore reproduce the same generation,
    // while any geometry or data-driven paint mutation changes it.
    ContentHashState content{
        0xa4093822299f31d0ULL ^ static_cast<uint64_t>(vertexBytes),
        0x082efa98ec4e6c89ULL ^ static_cast<uint64_t>(indexBytes),
    };
    hashBytes(content, command.vertexData, vertexBytes);
    hashBytes(content, command.indexData, indexBytes);
    content.first ^= static_cast<uint64_t>(command.vertexStride) << 40;
    content.second ^= static_cast<uint64_t>(command.vertexCount) << 16;
    const auto contentFingerprint = fingerprintFor(content);
    const uint32_t bufferId = fillExtrusionBufferIdFor(session, structuralFingerprint);
    const uint32_t version =
        fillExtrusionBufferVersionFor(session, structuralFingerprint, contentFingerprint);

    FillExtrusionContentIdentity identity{
        bufferId,
        version,
        session.frame,
        structuralFingerprint,
        contentFingerprint,
    };
    session.fillExtrusionContentIdentities.emplace(sourceKey, identity);
    return identity;
}

void trimFillExtrusionContentIdentities(MergeSessionState& session) {
    for (auto it = session.fillExtrusionContentIdentities.begin();
         it != session.fillExtrusionContentIdentities.end();) {
        const auto age = session.frame - it->second.lastUsedFrame;
        if (it->second.lastUsedFrame != session.frame && age >= kFillExtrusionContentSourceRetentionFrames) {
            it = session.fillExtrusionContentIdentities.erase(it);
        } else {
            ++it;
        }
    }
    for (auto it = session.fillExtrusionStructuralIdentities.begin();
         it != session.fillExtrusionStructuralIdentities.end();) {
        const auto age = session.frame - it->second.lastUsedFrame;
        if (it->second.lastUsedFrame != session.frame &&
            age >= kFillExtrusionIdentityRetentionFrames) {
            session.fillExtrusionStructuralIds.erase(it->second.bufferId);
            it = session.fillExtrusionStructuralIdentities.erase(it);
        } else {
            auto& structural = it->second;
            for (auto content = structural.contentVersions.begin();
                 content != structural.contentVersions.end();) {
                const auto contentAge = session.frame - content->second.lastUsedFrame;
                if (content->second.lastUsedFrame != session.frame &&
                    contentAge >= kFillExtrusionIdentityRetentionFrames) {
                    structural.versionContents.erase(content->second.version);
                    content = structural.contentVersions.erase(content);
                } else {
                    ++content;
                }
            }
            ++it;
        }
    }
}

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

// Fill-extrusion bytes already match Flutter GPU's 12-byte constant or 44-byte
// data-driven layout. Give them a content-addressed identity instead of a
// Drawable/allocation identity, without changing the DrawCommand ABI.
void assignPackedFillExtrusionBufferIds(
    std::vector<mbgl::command_export::DrawCommand>& commands) {
    using namespace mbgl::command_export;
    auto& session = mergeSession();
    for (auto& command : commands) {
        if (command.shaderType != ShaderType::FillExtrusion ||
            (command.vertexStride != kFillExtrusionConstantStride &&
             command.vertexStride != kFillExtrusionPackedStride)) {
            continue;
        }
        const auto identity = fillExtrusionContentIdentityFor(session, command);
        if (!identity) continue;
        command.bufferId = identity->bufferId;
        command.bufferVersion = identity->bufferVersion;
    }
    trimFillExtrusionContentIdentities(session);
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

    // Fill-extrusion keeps its native packed bytes but receives a deterministic
    // content identity. Only DD line vertices still use bridge-side expansion.
    assignPackedFillExtrusionBufferIds(commands);
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

// Storage shared by command preparation and cross-tile batching.
#pragma once

#include "../bridge_state.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
#include <cstdint>
#include <functional>
#include <map>
#include <vector>

namespace maplibre_bridge::commands {
// Screen-space vertices stay alive until the next command frame begins.
struct MergedVertex {
    float x;
    float y;

    bool operator==(const MergedVertex& other) const {
        return x == other.x && y == other.y;
    }
};

// Native source generations avoid rescanning unchanged vertex streams.
// Recreated buckets are hashed once and identical bytes reuse the GPU identity.
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

// Data-driven line vertices keep the bridge-expanded 120-byte layout.
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

// Returns storage for the selected session. Call only on the owner thread.
MergeSessionState& mergeSession();

// Reuses packed extrusion bytes and gives equal content stable GPU identities.
void assignPackedFillExtrusionBufferIds(
    std::vector<mln::command_export::DrawCommand>& commands);

// Expands data-driven lines into session-owned buffers valid for this frame.
void prepareLineGpuVertices(std::vector<mln::command_export::DrawCommand>& commands);
} // namespace maplibre_bridge::commands
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

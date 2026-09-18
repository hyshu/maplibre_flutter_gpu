#include "merge_session.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
#include <cstring>
#include <limits>
#include <optional>
#include <utility>

namespace maplibre_bridge::commands {
namespace {
constexpr uint32_t kFillExtrusionConstantStride = 12;
constexpr uint32_t kFillExtrusionPackedStride = 44;
constexpr uint64_t kFillExtrusionContentSourceRetentionFrames = 120;
constexpr uint64_t kFillExtrusionIdentityRetentionFrames = 1800;
constexpr uint32_t kContentAddressedFillExtrusionNamespace = 0xC0000000u;
constexpr uint32_t kContentAddressedFillExtrusionValueMask = 0x3fffffffu;

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
    const mln::command_export::DrawCommand& command) {
    if (!command.vertexData || !command.indexData || command.vertexCount == 0 || command.indexCount == 0 ||
        command.vertexStride == 0 ||
        command.vertexCount > std::numeric_limits<size_t>::max() / command.vertexStride ||
        static_cast<size_t>(command.indexCount) >
            std::numeric_limits<size_t>::max() / sizeof(uint16_t)) {
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

    // Paint changes retain the resource ID and receive a new generation.
    // Index topology, counts, and layer identify recreated geometry buckets.
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

} // namespace

// Fill-extrusion bytes already match Flutter GPU's 12-byte constant or 44-byte
// data-driven layout. Give them a content-addressed identity instead of a
// Drawable/allocation identity, without changing the DrawCommand ABI.
void assignPackedFillExtrusionBufferIds(
    std::vector<mln::command_export::DrawCommand>& commands) {
    using namespace mln::command_export;
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

} // namespace maplibre_bridge::commands
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

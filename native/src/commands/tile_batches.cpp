// Concatenates the tiles of one layer into a single draw per pipeline run.
#include "merge_session.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
#include <algorithm>
#include <cstring>
#include <limits>
#include <unordered_map>
#include <vector>

namespace maplibre_bridge::commands {
namespace {
using mln::command_export::CommandPayloadView;
using mln::command_export::DrawCommand;
using mln::command_export::DrawCommandPayload;
using mln::command_export::FrameData;
using mln::command_export::ShaderType;
using mln::command_export::StencilModeType;
namespace DrawCommandFlags = mln::command_export::DrawCommandFlags;

constexpr uint64_t kTileBatchRetentionFrames = 120;
constexpr size_t kTileBatchCacheBudgetBytes = 96 * 1024 * 1024;
constexpr uint32_t kPreparedBufferIdNamespace = 0x80000000u;
constexpr uint32_t kPreparedBufferIdValueMask = 0x7fffffffu;

uint64_t fnv64(uint64_t hash, const void* bytes, size_t length) {
    const auto* data = static_cast<const uint8_t*>(bytes);
    for (size_t index = 0; index < length; ++index) {
        hash ^= data[index];
        hash *= 1099511628211ULL;
    }
    return hash;
}

uint64_t mixPointer(uint64_t hash, const void* pointer) {
    const auto value = reinterpret_cast<uintptr_t>(pointer);
    return fnv64(hash, &value, sizeof(value));
}

bool batchableShader(ShaderType shader) {
    switch (shader) {
        case ShaderType::Fill:
        case ShaderType::FillOutline:
        case ShaderType::FillOutlineTriangulated:
        case ShaderType::Line:
        case ShaderType::LineSDF:
        case ShaderType::LineGradient:
        case ShaderType::Circle:
            return true;
        default:
            return false;
    }
}

bool sameBytes(std::span<const uint8_t> left, std::span<const uint8_t> right) {
    return left.size() == right.size() &&
           (left.empty() || std::memcmp(left.data(), right.data(), left.size()) == 0);
}

// Members of one batch share everything except geometry and per-tile UBOs.
bool batchCompatible(const DrawCommand& first,
                     const DrawCommandPayload& firstPayload,
                     const DrawCommand& next,
                     const DrawCommandPayload& nextPayload) {
    if (next.shaderType != first.shaderType || next.drawMode != first.drawMode ||
        next.flags != first.flags || next.layerIndex != first.layerIndex ||
        next.subLayerIndex != first.subLayerIndex || next.vertexStride != first.vertexStride) {
        return false;
    }
    if (nextPayload.drawableUBO.size() != firstPayload.drawableUBO.size() ||
        nextPayload.tilePropsUBO.size() != firstPayload.tilePropsUBO.size() ||
        !sameBytes(nextPayload.propsUBO, firstPayload.propsUBO)) {
        return false;
    }
    if (firstPayload.texture.has_value() != nextPayload.texture.has_value()) return false;
    if (firstPayload.texture) {
        const auto& a = *firstPayload.texture;
        const auto& b = *nextPayload.texture;
        if (a.id != b.id || a.version != b.version || a.width != b.width || a.height != b.height ||
            a.channels != b.channels || a.filter != b.filter) {
            return false;
        }
    }
    return true;
}

// A command joins a batch only while its tile mask is the sole clipping it needs.
bool batchableCommand(const DrawCommand& command, const DrawCommandPayload& payload) {
    if (!batchableShader(command.shaderType)) return false;
    if ((command.flags & (DrawCommandFlags::CrossTileMerged | kTileBatchedFlag)) != 0) return false;
    if (!command.vertexData || !command.indexData || command.vertexCount == 0 || command.indexCount == 0) {
        return false;
    }
    if (command.vertexCount > kTileBatchMaxVertices) return false;
    if (!payload.stencil || payload.stencil->mode != StencilModeType::ClippingTest) return false;
    if (payload.stencil->reference > 255) return false;
    if (payload.renderTarget || payload.fillExtrusionFeatures) return false;
    if (payload.drawableUBO.empty() || payload.drawableUBO.size() > kTileBatchMaxDrawableBytes) return false;
    return true;
}

uint32_t allocateBatchBufferId(MergeSessionState& session) {
    uint32_t value = session.nextPreparedBufferId++ & kPreparedBufferIdValueMask;
    if (value == 0) value = session.nextPreparedBufferId++ & kPreparedBufferIdValueMask;
    return kPreparedBufferIdNamespace | value;
}

void trimTileBatchCache(MergeSessionState& session) {
    size_t totalBytes = 0;
    for (auto it = session.tileBatches.begin(); it != session.tileBatches.end();) {
        const auto age = session.frame - it->second.lastUsedFrame;
        if (it->second.lastUsedFrame != session.frame && age >= kTileBatchRetentionFrames) {
            it = session.tileBatches.erase(it);
        } else {
            totalBytes += it->second.vertices.size() + it->second.indices.size() * sizeof(uint16_t);
            ++it;
        }
    }
    while (totalBytes > kTileBatchCacheBudgetBytes) {
        auto victim = session.tileBatches.end();
        for (auto it = session.tileBatches.begin(); it != session.tileBatches.end(); ++it) {
            if (it->second.lastUsedFrame == session.frame) continue;
            if (victim == session.tileBatches.end() ||
                it->second.lastUsedFrame < victim->second.lastUsedFrame) {
                victim = it;
            }
        }
        if (victim == session.tileBatches.end()) break;
        totalBytes -= victim->second.vertices.size() + victim->second.indices.size() * sizeof(uint16_t);
        session.tileBatches.erase(victim);
    }
}

// Identity of the concatenated bytes. Addresses participate because native
// geometry can be replaced at the same identity within one generation.
uint64_t batchGeometryHash(const std::vector<const DrawCommand*>& members) {
    uint64_t hash = 14695981039346656037ULL;
    for (const auto* member : members) {
        hash = fnv64(hash, &member->bufferId, sizeof(member->bufferId));
        hash = fnv64(hash, &member->bufferVersion, sizeof(member->bufferVersion));
        hash = mixPointer(hash, member->vertexData);
        hash = fnv64(hash, &member->vertexCount, sizeof(member->vertexCount));
        hash = fnv64(hash, &member->vertexStride, sizeof(member->vertexStride));
        hash = mixPointer(hash, member->indexData);
        hash = fnv64(hash, &member->indexCount, sizeof(member->indexCount));
    }
    return hash;
}

TileBatchGeometry& batchGeometryFor(MergeSessionState& session,
                                    const std::vector<const DrawCommand*>& members) {
    const auto hash = batchGeometryHash(members);
    auto it = session.tileBatches.find(hash);
    if (it != session.tileBatches.end()) {
        it->second.lastUsedFrame = session.frame;
        return it->second;
    }
    TileBatchGeometry geometry;
    geometry.bufferId = allocateBatchBufferId(session);
    geometry.lastUsedFrame = session.frame;
    const uint32_t stride = members.front()->vertexStride;
    size_t vertexBytes = 0;
    size_t indexCount = 0;
    for (const auto* member : members) {
        vertexBytes += static_cast<size_t>(member->vertexCount) * stride;
        indexCount += member->indexCount;
    }
    geometry.vertices.resize(vertexBytes);
    geometry.indices.reserve(indexCount);
    geometry.vertexStarts.reserve(members.size());
    size_t vertexCursor = 0;
    uint32_t vertexBase = 0;
    for (const auto* member : members) {
        const size_t bytes = static_cast<size_t>(member->vertexCount) * stride;
        std::memcpy(geometry.vertices.data() + vertexCursor, member->vertexData, bytes);
        vertexCursor += bytes;
        geometry.vertexStarts.push_back(vertexBase);
        for (uint32_t index = 0; index < member->indexCount; ++index) {
            geometry.indices.push_back(static_cast<uint16_t>(member->indexData[index] + vertexBase));
        }
        vertexBase += member->vertexCount;
    }
    return session.tileBatches.emplace(hash, std::move(geometry)).first->second;
}

// Emits one command for [members], whose payload carries every member's
// drawable UBO followed by a table of vertex starts and clip references.
DrawCommand emitBatch(FrameData& fd,
                      MergeSessionState& session,
                      const std::vector<const DrawCommand*>& members) {
    std::vector<uint8_t> drawables;
    std::vector<uint8_t> tileProps;
    std::vector<uint8_t> table;
    std::vector<uint8_t> props;
    std::optional<mln::command_export::CommandTexture> texture;
    uint32_t vertexBase = 0;
    for (const auto* member : members) {
        const CommandPayloadView view(fd.payload, *member);
        const auto& payload = view.get();
        drawables.insert(drawables.end(), payload.drawableUBO.begin(), payload.drawableUBO.end());
        tileProps.insert(tileProps.end(), payload.tilePropsUBO.begin(), payload.tilePropsUBO.end());
        const uint32_t reference = payload.stencil ? payload.stencil->reference : 0;
        const uint8_t* startBytes = reinterpret_cast<const uint8_t*>(&vertexBase);
        const uint8_t* referenceBytes = reinterpret_cast<const uint8_t*>(&reference);
        table.insert(table.end(), startBytes, startBytes + sizeof(vertexBase));
        table.insert(table.end(), referenceBytes, referenceBytes + sizeof(reference));
        if (member == members.front()) {
            props.assign(payload.propsUBO.begin(), payload.propsUBO.end());
            texture = payload.texture;
        }
        vertexBase += member->vertexCount;
    }
    drawables.insert(drawables.end(), table.begin(), table.end());

    auto& geometry = batchGeometryFor(session, members);
    DrawCommand batched = *members.front();
    batched.vertexData = geometry.vertices.data();
    batched.vertexCount = vertexBase;
    batched.indexData = geometry.indices.data();
    batched.indexCount = static_cast<uint32_t>(geometry.indices.size());
    batched.bufferId = geometry.bufferId;
    batched.bufferVersion = 1;
    batched.flags |= kTileBatchedFlag;

    DrawCommandPayload payload;
    payload.drawableUBO = drawables;
    payload.propsUBO = props;
    payload.tilePropsUBO = tileProps;
    payload.texture = texture;
    fd.setPayload(batched, payload);
    return batched;
}
} // namespace

void batchTileCommands(FrameData& fd) {
    auto& commands = fd.commands;
    if (commands.size() < 2) return;
    // A mid-frame stencil clear renumbers the tile masks, so every clip
    // reference would need its own epoch. Keep per-tile draws in that case.
    for (const auto& command : commands) {
        const CommandPayloadView view(fd.payload, command);
        const auto& payload = view.get();
        if (payload.stencil && payload.stencil->mode == StencilModeType::Clear) return;
    }

    auto& session = mergeSession();
    std::vector<DrawCommand> result;
    result.reserve(commands.size());
    std::vector<const DrawCommand*> members;
    bool batched = false;
    size_t index = 0;
    while (index < commands.size()) {
        const DrawCommand& first = commands[index];
        const CommandPayloadView firstView(fd.payload, first);
        if (!firstView.valid() || !batchableCommand(first, firstView.get())) {
            result.push_back(first);
            index += 1;
            continue;
        }
        members.clear();
        members.push_back(&first);
        uint32_t vertexCount = first.vertexCount;
        size_t next = index + 1;
        while (next < commands.size() && members.size() < kTileBatchMaxMembers) {
            const DrawCommand& candidate = commands[next];
            const CommandPayloadView candidateView(fd.payload, candidate);
            if (!candidateView.valid() || !batchableCommand(candidate, candidateView.get()) ||
                !batchCompatible(first, firstView.get(), candidate, candidateView.get()) ||
                vertexCount + candidate.vertexCount > kTileBatchMaxVertices) {
                break;
            }
            members.push_back(&candidate);
            vertexCount += candidate.vertexCount;
            next += 1;
        }
        if (members.size() < 2) {
            result.push_back(first);
            index += 1;
            continue;
        }
        result.push_back(emitBatch(fd, session, members));
        batched = true;
        index = next;
    }
    if (!batched) return;
    commands = std::move(result);
    trimTileBatchCache(session);
    fd.compactPayload();
}
} // namespace maplibre_bridge::commands
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

#include "merge_session.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
#include <cstring>
#include <limits>
#include <unordered_map>
#include <utility>

namespace maplibre_bridge::commands {
namespace {
constexpr uint32_t kLineDataDrivenPackedStride = 88;
constexpr uint32_t kLineDataDrivenGpuStride = 120;
// Bridge-only layout marker. Dart removes it from shader-facing paint masks.
constexpr uint32_t kLineGpuReadyFlag = 1u << 25;
constexpr uint64_t kLineGpuRetentionFrames = 60;
constexpr uint64_t kPreparedBufferIdRetentionFrames = 600;
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

bool isLineShader(mln::command_export::ShaderType shader) {
    using mln::command_export::ShaderType;
    return shader == ShaderType::Line || shader == ShaderType::LineSDF ||
           shader == ShaderType::LineGradient || shader == ShaderType::LinePattern;
}

bool expandLineVertices(const mln::command_export::DrawCommand& command,
                        std::vector<uint8_t>& output) {
    const uint32_t sourceStride = kLineDataDrivenPackedStride;
    const uint32_t targetStride = kLineDataDrivenGpuStride;
    if (!command.vertexData || command.vertexCount == 0 || command.vertexStride != sourceStride ||
        static_cast<size_t>(command.vertexCount) >
            std::numeric_limits<size_t>::max() / targetStride) {
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

} // namespace

void prepareLineGpuVertices(std::vector<mln::command_export::DrawCommand>& commands) {
    using namespace mln::command_export;
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
} // namespace maplibre_bridge::commands
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

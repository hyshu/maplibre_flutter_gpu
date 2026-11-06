#pragma once

#include <bit>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>

namespace maplibre_bridge::vertices {

// These identifiers describe packed little-endian input and float32 output.
enum class RepackLayout : std::uint32_t {
    FillExtrusion12To24 = 1,
    FillExtrusion44To56 = 2,
    Line8To24 = 3,
    // Three exact numeric floats carry byte groups [0,3), [3,6), and [6,8).
    Line8To12 = 4,
};

enum class RepackResult : std::int32_t {
    InvalidInput = -1,
    UnsupportedLayout = 0,
    Success = 1,
};

namespace detail {

static_assert(std::endian::native == std::endian::little);
static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559);

template <typename Integer>
inline Integer loadInteger(const std::uint8_t* source) noexcept {
    Integer value;
    std::memcpy(&value, source, sizeof(value));
    return value;
}

template <std::size_t SourceStride, std::size_t TargetStride, bool Extrusion>
inline void convertVertices(const std::uint8_t* source,
                            std::uint8_t* destination,
                            std::uint32_t count) noexcept {
    for (std::uint32_t vertex = 0; vertex < count; ++vertex) {
        const auto* input = source + static_cast<std::size_t>(vertex) * SourceStride;
        auto* output = destination + static_cast<std::size_t>(vertex) * TargetStride;
        float values[6];
        values[0] = static_cast<float>(loadInteger<std::int16_t>(input));
        values[1] = static_cast<float>(loadInteger<std::int16_t>(input + 2));
        if constexpr (Extrusion) {
            values[2] = static_cast<float>(loadInteger<std::uint16_t>(input + 4));
            values[3] = static_cast<float>(loadInteger<std::uint16_t>(input + 6));
            values[4] = static_cast<float>(loadInteger<std::int16_t>(input + 8));
            values[5] = static_cast<float>(loadInteger<std::int16_t>(input + 10));
        } else {
            values[2] = static_cast<float>(input[4]);
            values[3] = static_cast<float>(input[5]);
            values[4] = static_cast<float>(input[6]);
            values[5] = static_cast<float>(input[7]);
        }
        std::memcpy(output, values, sizeof(values));
        if constexpr (SourceStride == 44) {
            // Paint attributes retain every bit, including NaN payloads.
            std::memcpy(output + 24, input + 12, 32);
        }
    }
}

inline void packLineVertices(const std::uint8_t* source,
                             std::uint8_t* destination,
                             std::uint32_t count) noexcept {
    for (std::uint32_t vertex = 0; vertex < count; ++vertex) {
        const auto* input = source + static_cast<std::size_t>(vertex) * 8;
        auto* output = destination + static_cast<std::size_t>(vertex) * 12;
        const std::uint32_t first = std::uint32_t{input[0]} |
                                    (std::uint32_t{input[1]} << 8) |
                                    (std::uint32_t{input[2]} << 16);
        const std::uint32_t second = std::uint32_t{input[3]} |
                                     (std::uint32_t{input[4]} << 8) |
                                     (std::uint32_t{input[5]} << 16);
        const std::uint32_t third = std::uint32_t{input[6]} |
                                    (std::uint32_t{input[7]} << 8);
        // Every integer fits in float32's exact 24-bit significand.
        const float values[3] = {
            static_cast<float>(first), static_cast<float>(second), static_cast<float>(third),
        };
        std::memcpy(output, values, sizeof(values));
    }
}

} // namespace detail

// Borrows caller-owned spans for one synchronous conversion without allocating.
// The accessed input and output ranges must be accessible and must not overlap.
// Unaligned ranges are supported. Invalid input leaves the destination unchanged.
// Supported empty inputs succeed without accessing either pointer.
inline RepackResult repackVertices(std::uint32_t layout,
                                  const void* source,
                                  std::size_t sourceBytes,
                                  std::uint32_t vertexCount,
                                  void* destination,
                                  std::size_t destinationCapacity) noexcept {
    std::size_t sourceStride;
    std::size_t targetStride;
    switch (static_cast<RepackLayout>(layout)) {
        case RepackLayout::FillExtrusion12To24:
            sourceStride = 12;
            targetStride = 24;
            break;
        case RepackLayout::FillExtrusion44To56:
            sourceStride = 44;
            targetStride = 56;
            break;
        case RepackLayout::Line8To24:
            sourceStride = 8;
            targetStride = 24;
            break;
        case RepackLayout::Line8To12:
            sourceStride = 8;
            targetStride = 12;
            break;
        default:
            return RepackResult::UnsupportedLayout;
    }
    if (vertexCount == 0) return RepackResult::Success;
    if (!source || !destination ||
        vertexCount > std::numeric_limits<std::size_t>::max() / sourceStride ||
        vertexCount > std::numeric_limits<std::size_t>::max() / targetStride) {
        return RepackResult::InvalidInput;
    }
    const auto inputBytes = static_cast<std::size_t>(vertexCount) * sourceStride;
    const auto outputBytes = static_cast<std::size_t>(vertexCount) * targetStride;
    if (sourceBytes < inputBytes || destinationCapacity < outputBytes) {
        return RepackResult::InvalidInput;
    }
    const auto inputAddress = reinterpret_cast<std::uintptr_t>(source);
    const auto outputAddress = reinterpret_cast<std::uintptr_t>(destination);
    constexpr auto maximumAddress = std::numeric_limits<std::uintptr_t>::max();
    if (inputBytes > maximumAddress - inputAddress ||
        outputBytes > maximumAddress - outputAddress) {
        return RepackResult::InvalidInput;
    }
    if (inputAddress < outputAddress + outputBytes &&
        outputAddress < inputAddress + inputBytes) {
        return RepackResult::InvalidInput;
    }

    const auto* input = static_cast<const std::uint8_t*>(source);
    auto* output = static_cast<std::uint8_t*>(destination);
    switch (static_cast<RepackLayout>(layout)) {
        case RepackLayout::FillExtrusion12To24:
            detail::convertVertices<12, 24, true>(input, output, vertexCount);
            break;
        case RepackLayout::FillExtrusion44To56:
            detail::convertVertices<44, 56, true>(input, output, vertexCount);
            break;
        case RepackLayout::Line8To24:
            detail::convertVertices<8, 24, false>(input, output, vertexCount);
            break;
        case RepackLayout::Line8To12:
            detail::packLineVertices(input, output, vertexCount);
            break;
    }
    return RepackResult::Success;
}

} // namespace maplibre_bridge::vertices

// The optional C ABI uses RepackLayout and RepackResult numeric values.
// The function retains neither pointer and does not require a map session.
extern "C" std::int32_t maplibre_repack_vertices_v1(std::uint32_t layout,
                                                   const void* source,
                                                   std::size_t sourceBytes,
                                                   std::uint32_t vertexCount,
                                                   void* destination,
                                                   std::size_t destinationCapacity) noexcept;

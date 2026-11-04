#include "frame/vertex_repack.hpp"
#include "test_check.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

using maplibre_bridge::vertices::RepackLayout;

static void putHalf(std::uint8_t* output, std::uint16_t value) {
    output[0] = static_cast<std::uint8_t>(value);
    output[1] = static_cast<std::uint8_t>(value >> 8);
}

static std::uint32_t readWord(const std::uint8_t* input) {
    return std::uint32_t{input[0]} | (std::uint32_t{input[1]} << 8) |
           (std::uint32_t{input[2]} << 16) | (std::uint32_t{input[3]} << 24);
}

static float signedHalf(std::uint16_t value) {
    return static_cast<float>(value < 0x8000 ? static_cast<int>(value) : static_cast<int>(value) - 65536);
}

static void checkConversion(RepackLayout layout,
                            std::uint32_t count,
                            std::size_t inputOffset,
                            std::size_t outputOffset) {
    const bool extrusion = layout != RepackLayout::Line8To24;
    const std::size_t inputStride = layout == RepackLayout::FillExtrusion44To56 ? 44 : extrusion ? 12 : 8;
    const std::size_t outputStride = inputStride == 44 ? 56 : 24;
    const auto inputLength = count * inputStride;
    const auto outputLength = count * outputStride;
    std::vector<std::uint8_t> source(inputOffset + inputLength + 16, 0x93);
    std::vector<std::uint8_t> destination(outputOffset + outputLength + 16, 0xa5);
    std::vector<std::array<float, 6>> expected(count);
    const std::array<std::uint32_t, 8> paintBits = {
        0x7fc01234, 0x7f801234, 0xffc05678, 0x80000000,
        0x00000000, 0x7f800000, 0xff800000, 0x00000001,
    };
    for (std::uint32_t vertex = 0; vertex < count; ++vertex) {
        auto* input = source.data() + inputOffset + vertex * inputStride;
        const auto value = static_cast<std::uint16_t>(vertex);
        const std::array<std::uint16_t, 6> halves = {
            value, static_cast<std::uint16_t>(65535 - value),
            static_cast<std::uint16_t>(value ^ 0x8000), value,
            static_cast<std::uint16_t>(value ^ 0x55aa),
            static_cast<std::uint16_t>(value ^ 0xaa55),
        };
        putHalf(input, halves[0]);
        putHalf(input + 2, halves[1]);
        expected[vertex][0] = signedHalf(halves[0]);
        expected[vertex][1] = signedHalf(halves[1]);
        if (extrusion) {
            for (std::size_t word = 2; word < halves.size(); ++word) putHalf(input + word * 2, halves[word]);
            expected[vertex][2] = static_cast<float>(halves[2]);
            expected[vertex][3] = static_cast<float>(halves[3]);
            expected[vertex][4] = signedHalf(halves[4]);
            expected[vertex][5] = signedHalf(halves[5]);
        } else {
            for (std::size_t byte = 0; byte < 4; ++byte) {
                const auto encoded = static_cast<std::uint8_t>(vertex + byte * 67);
                input[4 + byte] = encoded;
                expected[vertex][2 + byte] = static_cast<float>(encoded);
            }
        }
        if (inputStride == 44) {
            for (std::size_t word = 0; word < paintBits.size(); ++word) {
                const auto bits = paintBits[(word + vertex) % paintBits.size()];
                for (std::size_t byte = 0; byte < 4; ++byte) {
                    input[12 + word * 4 + byte] = static_cast<std::uint8_t>(bits >> (byte * 8));
                }
            }
        }
    }
    const auto original = source;
    MAPLIBRE_TEST_CHECK(maplibre_repack_vertices_v1(
        static_cast<std::uint32_t>(layout), source.data() + inputOffset, inputLength, count,
        destination.data() + outputOffset, outputLength) == 1);
    MAPLIBRE_TEST_CHECK(source == original);
    MAPLIBRE_TEST_CHECK(std::all_of(destination.begin(), destination.begin() + outputOffset,
                                   [](auto value) { return value == 0xa5; }));
    MAPLIBRE_TEST_CHECK(std::all_of(destination.begin() + outputOffset + outputLength, destination.end(),
                                   [](auto value) { return value == 0xa5; }));
    for (std::uint32_t vertex = 0; vertex < count; ++vertex) {
        const auto* output = destination.data() + outputOffset + vertex * outputStride;
        for (std::size_t component = 0; component < 6; ++component) {
            MAPLIBRE_TEST_CHECK(readWord(output + component * 4) ==
                                std::bit_cast<std::uint32_t>(expected[vertex][component]));
        }
        if (inputStride == 44) {
            MAPLIBRE_TEST_CHECK(std::memcmp(output + 24, source.data() + inputOffset + vertex * 44 + 12, 32) == 0);
        }
    }
}

static void checkInvalidInput() {
    std::array<std::uint8_t, 128> source;
    std::array<std::uint8_t, 128> destination;
    source.fill(0x93);
    destination.fill(0xa5);
    const auto originalSource = source;
    const auto originalDestination = destination;
    const auto reject = [&](std::uint32_t layout, const void* input, std::size_t inputSize,
                            std::uint32_t count, void* output, std::size_t capacity, std::int32_t result = -1) {
        MAPLIBRE_TEST_CHECK(maplibre_repack_vertices_v1(layout, input, inputSize, count, output, capacity) == result);
        MAPLIBRE_TEST_CHECK(source == originalSource);
        MAPLIBRE_TEST_CHECK(destination == originalDestination);
    };
    for (const std::uint32_t layout : {1u, 2u, 3u}) {
        const std::size_t inputStride = layout == 1 ? 12 : layout == 2 ? 44 : 8;
        const std::size_t outputStride = layout == 2 ? 56 : 24;
        MAPLIBRE_TEST_CHECK(maplibre_repack_vertices_v1(layout, nullptr, 0, 0, nullptr, 0) == 1);
        reject(layout, nullptr, inputStride, 1, destination.data(), outputStride);
        reject(layout, source.data(), inputStride, 1, nullptr, outputStride);
        reject(layout, source.data(), inputStride - 1, 1, destination.data(), outputStride);
        reject(layout, source.data(), inputStride, 1, destination.data(), outputStride - 1);
        reject(layout, source.data(), inputStride, 2, destination.data(), outputStride * 2);
        reject(layout, source.data(), inputStride * 2, 2, destination.data(), outputStride);
        reject(layout, source.data(), 0, std::numeric_limits<std::uint32_t>::max(), destination.data(), 0);
        reject(layout, source.data(), inputStride, 1, source.data(), outputStride);
        reject(layout, source.data(), inputStride, 1, source.data() + inputStride - 1, outputStride);
        reject(layout, destination.data() + outputStride - 1, inputStride, 1, destination.data(), outputStride);
        const auto wrapped = std::numeric_limits<std::uintptr_t>::max() - 3;
        reject(layout, reinterpret_cast<const void*>(wrapped), inputStride, 1, destination.data(), outputStride);
        reject(layout, source.data(), inputStride, 1, reinterpret_cast<void*>(wrapped), outputStride);
    }
    for (const std::uint32_t layout : {0u, 4u, std::numeric_limits<std::uint32_t>::max()}) {
        reject(layout, source.data(), source.size(), 1, destination.data(), destination.size(), 0);
        reject(layout, nullptr, 0, 0, nullptr, 0, 0);
    }
    std::array<std::uint8_t, 64> adjacent{};
    putHalf(adjacent.data(), 123);
    MAPLIBRE_TEST_CHECK(maplibre_repack_vertices_v1(1, adjacent.data(), 12, 1, adjacent.data() + 12, 24) == 1);
    MAPLIBRE_TEST_CHECK(readWord(adjacent.data() + 12) == std::bit_cast<std::uint32_t>(123.0f));
    adjacent.fill(0);
    putHalf(adjacent.data() + 24, 456);
    MAPLIBRE_TEST_CHECK(maplibre_repack_vertices_v1(1, adjacent.data() + 24, 12, 1, adjacent.data(), 24) == 1);
    MAPLIBRE_TEST_CHECK(readWord(adjacent.data()) == std::bit_cast<std::uint32_t>(456.0f));

    MAPLIBRE_TEST_CHECK(maplibre_repack_vertices_v1(
        1, source.data(), source.size(), 1, destination.data(), destination.size()) == 1);
    MAPLIBRE_TEST_CHECK(source == originalSource);
    MAPLIBRE_TEST_CHECK(std::all_of(destination.begin() + 24, destination.end(),
                                   [](auto value) { return value == 0xa5; }));
}

int main() {
    for (const auto layout : {RepackLayout::FillExtrusion12To24, RepackLayout::FillExtrusion44To56,
                              RepackLayout::Line8To24}) {
        for (const std::size_t inputOffset : {0u, 1u, 2u, 3u}) {
            for (const std::size_t outputOffset : {0u, 1u, 2u, 3u}) {
                checkConversion(layout, 17, inputOffset, outputOffset);
            }
        }
        checkConversion(layout, 0, 1, 3);
        checkConversion(layout, 65536, 1, 3);
    }
    checkConversion(RepackLayout::FillExtrusion44To56, 74900, 0, 0);
    checkInvalidInput();
    std::puts("Vertex repack conversion, bit preservation and invalid-input checks passed");
}

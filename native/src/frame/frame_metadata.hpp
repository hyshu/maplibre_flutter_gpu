#pragma once

#include <cstddef>
#include <cstdint>

// Commands and payload are borrowed together until their frame is released.
// payloadSize counts used arena bytes and excludes spare capacity.
struct FrameMetadata {
    const void* commands;
    int32_t commandCount;
    int32_t commandStride;
    float clearColor[4];
    uint32_t hasClearColor;
    const void* payload;
    uint32_t payloadSize;
};

static_assert(sizeof(FrameMetadata) == 56);
static_assert(offsetof(FrameMetadata, commands) == 0);
static_assert(offsetof(FrameMetadata, commandCount) == 8);
static_assert(offsetof(FrameMetadata, commandStride) == 12);
static_assert(offsetof(FrameMetadata, clearColor) == 16);
static_assert(offsetof(FrameMetadata, hasClearColor) == 32);
static_assert(offsetof(FrameMetadata, payload) == 40);
static_assert(offsetof(FrameMetadata, payloadSize) == 48);

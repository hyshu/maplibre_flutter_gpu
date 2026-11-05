#pragma once

#include "../src/frame/frame_metadata.hpp"
#include "test_check.hpp"

#include <mln/command_export/draw_command.hpp>

extern "C" const FrameMetadata* maplibre_frame_get_metadata();

inline mln::command_export::DrawCommandPayload payloadFor(
    const mln::command_export::DrawCommand& command) {
    const auto* frame = maplibre_frame_get_metadata();
    MAPLIBRE_TEST_CHECK(frame && frame->commandStride == sizeof(mln::command_export::DrawCommand));
    const mln::command_export::CommandPayloadView view(
        {static_cast<const uint8_t*>(frame->payload), frame->payloadSize}, command);
    MAPLIBRE_TEST_CHECK(view.valid());
    return view.get();
}

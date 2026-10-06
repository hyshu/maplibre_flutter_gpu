#pragma once

#include "../src/frame/frame_metadata.hpp"

#include <mln/command_export/draw_command.hpp>

#include <cassert>

extern "C" const FrameMetadata* maplibre_frame_get_metadata();

inline mln::command_export::DrawCommandPayload payloadFor(
    const mln::command_export::DrawCommand& command) {
    const auto* frame = maplibre_frame_get_metadata();
    assert(frame && frame->commandStride == sizeof(mln::command_export::DrawCommand));
    const mln::command_export::CommandPayloadView view(
        {static_cast<const uint8_t*>(frame->payload), frame->payloadSize}, command);
    assert(view.valid());
    return view.get();
}

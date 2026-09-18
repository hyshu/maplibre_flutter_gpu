// Owner-thread frame publication shared by synchronous and queued renders.
#pragma once

#include "../bridge_session.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
// Starts a frame only when no acquired snapshot can reference its buffers.
bool beginCommandFrameOnOwner(bool asynchronous = false);

// Publishes command storage and captures the transform used by this render.
// Returns false and clears the snapshot if the map or frontend is unavailable.
bool endCommandFrameOnOwner(const mln::TransformState* renderedState = nullptr);

#ifdef __ANDROID__
// Makes the snapshot available to Dart and returns its nonzero lease generation.
uint64_t publishFrameLease(uint64_t cameraRevision);
#endif
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

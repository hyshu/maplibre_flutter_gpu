#include "merge_session.hpp"

#if MLN_RENDER_BACKEND_COMMAND_EXPORT
namespace maplibre_bridge::commands {
namespace {
std::map<void*, MergeSessionState> sessions;
}

MergeSessionState& mergeSession() {
    return sessions[bridge_currentSession()];
}
} // namespace maplibre_bridge::commands

void bridge_releaseMergeSession(void* session) {
    maplibre_bridge::commands::sessions.erase(session);
}

void bridge_resetMergeStorage() {
    auto& session = maplibre_bridge::commands::mergeSession();
    session.indices.clear();
    session.vertices.clear();
    ++session.frame;
}
#endif // MLN_RENDER_BACKEND_COMMAND_EXPORT

#include <cassert>
#include <cstdio>
#include <cstring>
extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
int maplibre_style_set(const char*);
const char* maplibre_style_last_error();
void maplibre_destroy();
void maplibre_shutdown_all();
}
int main() {
    auto* session = maplibre_session_create();
    assert(session);
    maplibre_session_select(session);
    assert(maplibre_init(256, 256, 1, R"({"version":8,"sources":{},"layers":[]})") == 0);
    assert(maplibre_style_set(nullptr) == 0);
    const char* error = maplibre_style_last_error();
    std::printf("Native owner error: %s\n", error);
    assert(std::strstr(error, "style is null"));
    maplibre_destroy();
    maplibre_session_release(session);
    maplibre_shutdown_all();
}

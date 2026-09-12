#include <cassert>
#include <cstring>
#include <thread>

#define MAPLIBRE_API
static char g_styleError[1024] = "set filter: invalid expression";

template <typename Operation>
void bridge_runOnOwnerSync(Operation operation) {
    std::thread owner(operation);
    owner.join();
}

#include "style_last_error.inc"

int main() {
    const char* first = maplibre_style_last_error();
    assert(std::strcmp(first, g_styleError) == 0);
    std::strcpy(g_styleError, "set layer properties: missing layer");
    assert(std::strcmp(maplibre_style_last_error(), g_styleError) == 0);
    g_styleError[0] = '\0';
    assert(maplibre_style_last_error()[0] == '\0');
}

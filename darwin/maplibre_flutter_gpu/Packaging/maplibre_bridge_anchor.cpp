#include "../Headers/MapLibreBridge.h"

// Every FFI entry point must appear here. The retained table makes each symbol
// reachable when the bridge and MapLibre dependencies are distributed as one
// static archive.
#define MAPLIBRE_FFI_SYMBOLS(X) \
    X(maplibre_session_create) \
    X(maplibre_session_select) \
    X(maplibre_session_release) \
    X(maplibre_init) \
    X(maplibre_is_idle) \
    X(maplibre_is_style_loaded) \
    X(maplibre_set_render_request_callback) \
    X(maplibre_process_events) \
    X(maplibre_frame_needs_repaint) \
    X(maplibre_render_frame) \
    X(maplibre_async_render_supported) \
    X(maplibre_render_frame_async) \
    X(maplibre_frame_acquire) \
    X(maplibre_frame_release) \
    X(maplibre_set_camera) \
    X(maplibre_set_camera_full) \
    X(maplibre_set_max_pitch) \
    X(maplibre_set_min_pitch) \
    X(maplibre_camera_ease_to) \
    X(maplibre_camera_fly_to) \
    X(maplibre_camera_move_by_animated) \
    X(maplibre_camera_scale_by_animated) \
    X(maplibre_camera_fit_bounds) \
    X(maplibre_is_camera_moving) \
    X(maplibre_cancel_camera_transitions) \
    X(maplibre_set_content_insets) \
    X(maplibre_set_content_insets_with_duration) \
    X(maplibre_set_bounds) \
    X(maplibre_get_camera) \
    X(maplibre_get_camera_lat) \
    X(maplibre_get_camera_lon) \
    X(maplibre_get_camera_zoom) \
    X(maplibre_get_camera_bearing) \
    X(maplibre_get_camera_pitch) \
    X(maplibre_get_visible_region) \
    X(maplibre_get_meters_per_pixel_at_latitude) \
    X(maplibre_move_by) \
    X(maplibre_scale_by) \
    X(maplibre_rotate_by) \
    X(maplibre_pitch_by) \
    X(maplibre_lat_lon_to_screen) \
    X(maplibre_project_coordinates) \
    X(maplibre_screen_to_lat_lon) \
    X(maplibre_set_size) \
    X(maplibre_get_drawable_count) \
    X(maplibre_get_drawable_name) \
    X(maplibre_get_drawable_summary) \
    X(maplibre_destroy) \
    X(maplibre_shutdown_all) \
    X(maplibre_frame_begin) \
    X(maplibre_frame_end) \
    X(maplibre_request_label_extraction) \
    X(maplibre_frame_get_command_count) \
    X(maplibre_frame_get_commands) \
    X(maplibre_frame_get_command_stride) \
    X(maplibre_frame_get_clear_color) \
    X(maplibre_frame_get_metadata) \
    X(maplibre_frame_get_map_transform) \
    X(maplibre_get_label_count) \
    X(maplibre_get_labels) \
    X(maplibre_get_label_stride) \
    X(maplibre_get_label_blob) \
    X(maplibre_get_label_blob_size) \
    X(maplibre_reproject_labels) \
    X(maplibre_get_labels_version) \
    X(maplibre_style_last_error) \
    X(maplibre_style_set) \
    X(maplibre_style_get_json) \
    X(maplibre_style_get_layer_ids) \
    X(maplibre_style_get_source_ids) \
    X(maplibre_style_get_source_attributions) \
    X(maplibre_style_set_layer_visibility) \
    X(maplibre_style_get_layer_visibility) \
    X(maplibre_style_set_filter) \
    X(maplibre_style_get_filter) \
    X(maplibre_style_add_layer) \
    X(maplibre_style_set_layer_properties) \
    X(maplibre_style_remove_layer)

extern "C" {

#define DECLARE_FFI_SYMBOL(name) void name(void);
MAPLIBRE_FFI_SYMBOLS(DECLARE_FFI_SYMBOL)
#undef DECLARE_FFI_SYMBOL

}

namespace {

using FfiSymbol = void (*)(void);

__attribute__((used)) const FfiSymbol kRetainedFfiSymbols[] = {
#define RETAIN_FFI_SYMBOL(name) &name,
    MAPLIBRE_FFI_SYMBOLS(RETAIN_FFI_SYMBOL)
#undef RETAIN_FFI_SYMBOL
};

}  // namespace

extern "C" __attribute__((used, visibility("default")))
const void* maplibre_flutter_gpu_force_link(void) {
    return kRetainedFfiSymbols;
}

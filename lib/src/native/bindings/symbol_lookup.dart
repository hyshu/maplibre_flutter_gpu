part of '../maplibre_ffi.dart';

extension _MaplibreBridgeSymbolLookup on MaplibreBridge {
  /// Resolves every native entry point.
  ///
  /// Missing required symbols fail immediately. Feature-group availability is
  /// reported only when every lookup succeeds.
  void _lookUpSymbols() {
    _createNativeSession = _lib.lookupFunction<SessionCreateN, SessionCreateD>(
      'maplibre_session_create',
    );
    _selectNativeSession = _lib.lookupFunction<SessionHandleN, SessionHandleD>(
      'maplibre_session_select',
    );
    _releaseNativeSession = _lib.lookupFunction<SessionHandleN, SessionHandleD>(
      'maplibre_session_release',
    );
    _init = _lib.lookupFunction<InitN, InitD>('maplibre_init');
    _renderFrame = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
      'maplibre_render_frame',
    );
    _isIdle = _lib.lookupFunction<Int32VoidN, Int32VoidD>('maplibre_is_idle');
    _setCamera = _lib.lookupFunction<SetCameraN, SetCameraD>(
      'maplibre_set_camera',
    );
    // Calls using this optional group provide fallbacks when possible.
    _symbols.lookUpGroup('camera transform and style state', () {
      _setCameraFull = _lib.lookupFunction<SetCameraFullN, SetCameraFullD>(
        'maplibre_set_camera_full',
      );
      _setBounds = _lib.lookupFunction<SetBoundsN, SetBoundsD>(
        'maplibre_set_bounds',
      );
      _getCameraBearing = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
        'maplibre_get_camera_bearing',
      );
      _getCameraPitch = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
        'maplibre_get_camera_pitch',
      );
      _rotateBy = _lib.lookupFunction<AdjustByN, AdjustByD>(
        'maplibre_rotate_by',
      );
      _pitchBy = _lib.lookupFunction<AdjustByN, AdjustByD>('maplibre_pitch_by');
      _screenToLatLon = _lib.lookupFunction<LatLonToScreenN, LatLonToScreenD>(
        'maplibre_screen_to_lat_lon',
      );
      _isStyleLoaded = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_is_style_loaded',
      );
    });
    // Calls using this group either provide a fallback or report that the
    // native feature is unavailable.
    _symbols.lookUpGroup('animated camera transitions', () {
      _cameraEase = _lib.lookupFunction<CameraEaseN, CameraEaseD>(
        'maplibre_camera_ease_to',
      );
      _cameraFly = _lib.lookupFunction<CameraFlyN, CameraFlyD>(
        'maplibre_camera_fly_to',
      );
      _cameraMoveAnimated = _lib
          .lookupFunction<CameraMoveAnimatedN, CameraMoveAnimatedD>(
            'maplibre_camera_move_by_animated',
          );
      _cameraScaleAnimated = _lib
          .lookupFunction<CameraScaleAnimatedN, CameraScaleAnimatedD>(
            'maplibre_camera_scale_by_animated',
          );
      _cameraFitBounds = _lib
          .lookupFunction<CameraFitBoundsN, CameraFitBoundsD>(
            'maplibre_camera_fit_bounds',
          );
      _isCameraMoving = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_is_camera_moving',
      );
      _cancelCameraTransitions = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_cancel_camera_transitions',
      );
      _setContentInsets = _lib
          .lookupFunction<SetContentInsetsN, SetContentInsetsD>(
            'maplibre_set_content_insets',
          );
      _getVisibleRegion = _lib
          .lookupFunction<GetVisibleRegionN, GetVisibleRegionD>(
            'maplibre_get_visible_region',
          );
      _getMetersPerPixelAtLatitude = _lib
          .lookupFunction<DoubleArgN, DoubleArgD>(
            'maplibre_get_meters_per_pixel_at_latitude',
          );
    });
    _symbols.lookUpGroup('content inset duration', () {
      _setContentInsetsWithDuration = _lib
          .lookupFunction<
            SetContentInsetsWithDurationN,
            SetContentInsetsWithDurationD
          >('maplibre_set_content_insets_with_duration');
    });
    _symbols.lookUpGroup('extended camera pitch', () {
      _setMinPitch = _lib.lookupFunction<VoidDoubleN, VoidDoubleD>(
        'maplibre_set_min_pitch',
      );
      _setMaxPitch = _lib.lookupFunction<VoidDoubleN, VoidDoubleD>(
        'maplibre_set_max_pitch',
      );
    });
    _symbols.lookUpGroup('runtime style mutation', () {
      _styleLastError = _lib.lookupFunction<StyleStringVoidN, StyleStringVoidD>(
        'maplibre_style_last_error',
      );
      _styleSet = _lib.lookupFunction<StyleSetN, StyleSetD>(
        'maplibre_style_set',
      );
      _styleGetJson = _lib.lookupFunction<StyleStringVoidN, StyleStringVoidD>(
        'maplibre_style_get_json',
      );
      _styleGetLayerIds = _lib
          .lookupFunction<StyleStringVoidN, StyleStringVoidD>(
            'maplibre_style_get_layer_ids',
          );
      _styleGetSourceIds = _lib
          .lookupFunction<StyleStringVoidN, StyleStringVoidD>(
            'maplibre_style_get_source_ids',
          );
      _styleSetLayerVisibility = _lib
          .lookupFunction<StyleSetVisibilityN, StyleSetVisibilityD>(
            'maplibre_style_set_layer_visibility',
          );
      _styleGetLayerVisibility = _lib
          .lookupFunction<StyleGetVisibilityN, StyleGetVisibilityD>(
            'maplibre_style_get_layer_visibility',
          );
      _styleSetFilter = _lib.lookupFunction<StyleSetFilterN, StyleSetFilterD>(
        'maplibre_style_set_filter',
      );
      _styleGetFilter = _lib.lookupFunction<StyleGetFilterN, StyleGetFilterD>(
        'maplibre_style_get_filter',
      );
    });
    _symbols.lookUpGroup('runtime layer creation', () {
      _styleAddLayer = _lib.lookupFunction<StyleAddLayerN, StyleAddLayerD>(
        'maplibre_style_add_layer',
      );
      _styleSetLayerProperties = _lib
          .lookupFunction<StyleLayerJsonN, StyleLayerJsonD>(
            'maplibre_style_set_layer_properties',
          );
      _styleRemoveLayer = _lib.lookupFunction<StyleLayerIdN, StyleLayerIdD>(
        'maplibre_style_remove_layer',
      );
    });
    _symbols.lookUpGroup('resolved style attributions', () {
      _styleGetSourceAttributions = _lib
          .lookupFunction<StyleStringVoidN, StyleStringVoidD>(
            'maplibre_style_get_source_attributions',
          );
    });
    _getCameraLat = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
      'maplibre_get_camera_lat',
    );
    _getCameraLon = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
      'maplibre_get_camera_lon',
    );
    _getCameraZoom = _lib.lookupFunction<DoubleVoidN, DoubleVoidD>(
      'maplibre_get_camera_zoom',
    );
    _symbols.lookUpGroup('camera snapshot', () {
      _getCamera = _lib.lookupFunction<GetCameraN, GetCameraD>(
        'maplibre_get_camera',
      );
    });
    _moveBy = _lib.lookupFunction<MoveByN, MoveByD>('maplibre_move_by');
    _scaleBy = _lib.lookupFunction<ScaleByN, ScaleByD>('maplibre_scale_by');
    _latLonToScreen = _lib.lookupFunction<LatLonToScreenN, LatLonToScreenD>(
      'maplibre_lat_lon_to_screen',
    );
    _symbols.lookUpGroup('batch coordinate projection', () {
      _projectCoordinates = _lib
          .lookupFunction<ProjectCoordinatesN, ProjectCoordinatesD>(
            'maplibre_project_coordinates',
          );
    });
    _symbols.lookUpGroup('wrapped batch coordinate projection', () {
      _projectWrappedCoordinates = _lib
          .lookupFunction<
            ProjectWrappedCoordinatesN,
            ProjectWrappedCoordinatesD
          >('maplibre_project_wrapped_coordinates');
    });
    _setSize = _lib.lookupFunction<SetSizeN, SetSizeD>('maplibre_set_size');
    _destroy = _lib.lookupFunction<VoidVoidN, VoidVoidD>('maplibre_destroy');
    // Missing event callbacks use the polling scheduler.
    _symbols.lookUpGroup('event-driven rendering', () {
      _setRenderRequestCallback = _lib
          .lookupFunction<SetRenderRequestCallbackN, SetRenderRequestCallbackD>(
            'maplibre_set_render_request_callback',
          );
      _processEvents = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_process_events',
      );
      _frameNeedsRepaint = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_frame_needs_repaint',
      );
    });
    _symbols.lookUpGroup('asynchronous frame snapshots', () {
      _asyncRenderSupported = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_async_render_supported',
      );
      _renderFrameAsync = _lib.lookupFunction<Int32VoidN, Int32VoidD>(
        'maplibre_render_frame_async',
      );
      _frameAcquire = _lib.lookupFunction<Uint64VoidN, Uint64VoidD>(
        'maplibre_frame_acquire',
      );
      _frameRelease = _lib.lookupFunction<VoidUint64N, VoidUint64D>(
        'maplibre_frame_release',
      );
    });
    _lookUpLabelSymbols(_lib);
    _lookUpFrameSymbols(_lib);
  }
}

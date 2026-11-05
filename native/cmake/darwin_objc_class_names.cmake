# MapLibre Native defines these Objective-C classes in Darwin sources that the
# bridge compiles into its own static archive. The Objective-C runtime registers
# a class process wide from __objc_classlist, so hidden visibility does not stop
# a collision when the host application also links the MapLibre GL SDK. Whichever
# copy the runtime keeps then serves both, and the SDK's network configuration
# can land on the bridge's manager or the reverse.
#
# Renaming the bridge's copies keeps the two registrations apart, the way the
# dev.maplibre.fluttergpu JNI request class does on Android. The rename applies
# to mbgl-core only, so the vendored MapLibre SDK targets keep their own names.
#
# native/scripts/packaging/darwin_common.sh parses the pairs below and fails the
# packaged archive when an original name survives or a renamed one is missing.
# Keep every pair on its own line in Old=New form.
set(MAPLIBRE_DARWIN_OBJC_CLASS_RENAMES
    MLNNativeNetworkManager=MFGBridgeNativeNetworkManager
    MLNInternalNetworkResponse=MFGBridgeInternalNetworkResponse
    MBGLBundleCanary=MFGBridgeBundleCanary
)

# Applies the renames to a target that already exists. Call it through
# cmake_language(DEFER CALL ...) from a project include, because mbgl-core is
# created after the include runs.
function(maplibre_apply_darwin_objc_class_renames target)
    if(NOT TARGET ${target})
        message(FATAL_ERROR
            "${target} does not exist, so the Darwin class renames would be dropped")
    endif()
    target_compile_definitions(${target} PRIVATE ${MAPLIBRE_DARWIN_OBJC_CLASS_RENAMES})
endfunction()

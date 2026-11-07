#!/usr/bin/env bash

# Shared build helpers for the vendored Darwin XCFramework.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "error: darwin_common.sh must be sourced" >&2
    exit 64
fi

PACKAGING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${PACKAGING_DIR}/.." && pwd)"
NATIVE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${NATIVE_ROOT}/.." && pwd)"
MAPLIBRE_SRC="${PROJECT_ROOT}/vendor/maplibre-native"
DARWIN_PACKAGE_ROOT="${PROJECT_ROOT}/darwin/maplibre_flutter_gpu"
ANCHOR_SOURCE="${DARWIN_PACKAGE_ROOT}/Packaging/maplibre_bridge_anchor.cpp"
BRIDGE_HEADER="${DARWIN_PACKAGE_ROOT}/Headers/MapLibreBridge.h"
FRAMEWORK_MODULE_MAP="${DARWIN_PACKAGE_ROOT}/Packaging/module.modulemap"
PRIVACY_MANIFEST="${DARWIN_PACKAGE_ROOT}/Packaging/PrivacyInfo.xcprivacy"
OBJC_CLASS_RENAMES_SOURCE="${NATIVE_ROOT}/cmake/darwin_objc_class_names.cmake"
BRIDGE_FRAMEWORK_NAME=MapLibreBridge
BRIDGE_FRAMEWORK_IDENTIFIER=dev.maplibre.fluttergpu.MapLibreBridge
IOS_DEPLOYMENT_TARGET="${MAPLIBRE_IOS_DEPLOYMENT_TARGET:-${MAPLIBRE_DARWIN_DEPLOYMENT_TARGET:-15.5}}"
MACOS_DEPLOYMENT_TARGET="${MAPLIBRE_MACOS_DEPLOYMENT_TARGET:-${MAPLIBRE_DARWIN_DEPLOYMENT_TARGET:-14.3}}"

BRIDGE_SOURCE_PATHS=(
    "${NATIVE_ROOT}/src/maplibre_bridge.cpp"
    "${NATIVE_ROOT}/src/bridge_camera.cpp"
    "${NATIVE_ROOT}/src/camera/camera_gestures.cpp"
    "${NATIVE_ROOT}/src/camera/camera_query.cpp"
    "${NATIVE_ROOT}/src/bridge_debug.cpp"
    "${NATIVE_ROOT}/src/bridge_memory.cpp"
    "${NATIVE_ROOT}/src/memory/system_memory.cpp"
    "${NATIVE_ROOT}/src/bridge_frame.cpp"
    "${NATIVE_ROOT}/src/bridge_projection.cpp"
    "${NATIVE_ROOT}/src/bridge_owner_thread.cpp"
    "${NATIVE_ROOT}/src/bridge_merge.cpp"
    "${NATIVE_ROOT}/src/commands/merge_session.cpp"
    "${NATIVE_ROOT}/src/commands/fill_extrusion.cpp"
    "${NATIVE_ROOT}/src/commands/line_vertices.cpp"
    "${NATIVE_ROOT}/src/commands/tile_batches.cpp"
    "${NATIVE_ROOT}/src/frame/command_snapshot.cpp"
    "${NATIVE_ROOT}/src/frame/async_renderer.cpp"
    "${NATIVE_ROOT}/src/frame/vertex_repack.cpp"
    "${NATIVE_ROOT}/src/bridge_labels.cpp"
    "${NATIVE_ROOT}/src/labels/label_encoding.cpp"
    "${NATIVE_ROOT}/src/labels/label_session.cpp"
    "${NATIVE_ROOT}/src/bridge_style.cpp"
    "${ANCHOR_SOURCE}"
)

BRIDGE_INCLUDE_ARGS=(
    -I"${MAPLIBRE_SRC}/src"
    -I"${MAPLIBRE_SRC}/include"
    -I"${MAPLIBRE_SRC}/platform/default/include"
    -I"${MAPLIBRE_SRC}/platform/darwin/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/variant/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/geometry.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/geojson.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/jni.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/shelf-pack-cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/geojson-vt-cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/cheap-ruler-cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-native-base/deps/pixelmatch-cpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/expected-lite/include"
    -isystem "${MAPLIBRE_SRC}/vendor/rapidjson/include"
    -isystem "${MAPLIBRE_SRC}/vendor/boost/include"
    -isystem "${MAPLIBRE_SRC}/vendor/unordered_dense/include"
    -isystem "${MAPLIBRE_SRC}/vendor/eternal/include"
    -isystem "${MAPLIBRE_SRC}/vendor/nunicode/include"
    -isystem "${MAPLIBRE_SRC}/vendor/sqlite/include"
    -isystem "${MAPLIBRE_SRC}/vendor/protozero/include"
    -isystem "${MAPLIBRE_SRC}/vendor/vector-tile/include"
    -isystem "${MAPLIBRE_SRC}/vendor/wagyu/include"
    -isystem "${MAPLIBRE_SRC}/vendor/earcut.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/kdbush.hpp/include"
    -isystem "${MAPLIBRE_SRC}/vendor/polylabel/include"
    -isystem "${MAPLIBRE_SRC}/vendor/supercluster/include"
    -isystem "${MAPLIBRE_SRC}/vendor/unique_resource"
    -isystem "${MAPLIBRE_SRC}/vendor/freetype/include"
    -isystem "${MAPLIBRE_SRC}/vendor/harfbuzz/src"
    -isystem "${MAPLIBRE_SRC}/vendor/csscolorparser"
    -isystem "${MAPLIBRE_SRC}/vendor/parsedate"
    -isystem "${MAPLIBRE_SRC}/vendor/PMTiles/cpp"
    -isystem "${MAPLIBRE_SRC}/vendor/maplibre-tile-spec/cpp/include"
)

require_tools() {
    local tool
    for tool in "$@"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            echo "error: ${tool} is required" >&2
            exit 1
        fi
    done
}

require_darwin_sources() {
    if [[ ! -f "${MAPLIBRE_SRC}/CMakeLists.txt" ]]; then
        echo "error: MapLibre Native submodule is missing" >&2
        echo "Run git submodule update --init --recursive." >&2
        exit 1
    fi
    if [[ ! -f "${ANCHOR_SOURCE}" ]]; then
        echo "error: force-link anchor is missing at ${ANCHOR_SOURCE}" >&2
        exit 1
    fi
    if [[ ! -f "${OBJC_CLASS_RENAMES_SOURCE}" ]]; then
        echo "error: Darwin class rename list is missing at ${OBJC_CLASS_RENAMES_SOURCE}" >&2
        exit 1
    fi
    local packaging_input
    for packaging_input in "${BRIDGE_HEADER}" "${FRAMEWORK_MODULE_MAP}" "${PRIVACY_MANIFEST}"; do
        if [[ ! -f "${packaging_input}" ]]; then
            echo "error: Darwin framework input is missing at ${packaging_input}" >&2
            exit 1
        fi
    done
}

compile_bridge_objects() {
    local sdk="$1"
    local target="$2"
    local build_dir="$3"
    local object_dir="${build_dir}/bridge-objects"

    rm -rf "${object_dir}"
    mkdir -p "${object_dir}"
    BRIDGE_OBJECTS=()

    local source
    for source in "${BRIDGE_SOURCE_PATHS[@]}"; do
        local object="${object_dir}/$(basename "${source%.*}").o"
        BRIDGE_OBJECTS+=("${object}")
        "${CLANG}" \
            -c \
            -std=c++20 \
            -O2 \
            -DNDEBUG \
            -target "${target}" \
            -isysroot "${SYSROOT}" \
            -fPIC \
            -fno-rtti \
            -fvisibility=hidden \
            -fvisibility-inlines-hidden \
            -DMLN_RENDER_BACKEND_COMMAND_EXPORT=1 \
            -DMLN_TEXT_SHAPING_HARFBUZZ=1 \
            -DMLN_USE_UNORDERED_DENSE=1 \
            -DRAPIDJSON_HAS_STDSTRING=1 \
            "${BRIDGE_INCLUDE_ARGS[@]}" \
            -o "${object}" \
            "${source}"
    done
}

create_monolithic_archive() {
    local output="$1"
    shift

    local archive
    for archive in "$@"; do
        if [[ ! -f "${archive}" ]]; then
            echo "error: expected native archive was not built: ${archive}" >&2
            exit 1
        fi
    done

    mkdir -p "$(dirname "${output}")"
    rm -f "${output}"
    "${LIBTOOL}" -static -o "${output}" "${BRIDGE_OBJECTS[@]}" "$@" >&2
    verify_bridge_archive "${output}"
}

# Prints the C symbols the bridge must export, one per line and without the
# Mach-O underscore. The force-link anchor is the single source of this list.
bridge_expected_symbols() {
    {
        sed -En 's/^[[:space:]]*X\(([a-zA-Z0-9_]+)\).*/\1/p' "${ANCHOR_SOURCE}"
        echo maplibre_flutter_gpu_force_link
    } | sort -u
}

verify_bridge_archive() {
    local archive="$1"
    local exported_symbols
    exported_symbols="$(nm -gU "${archive}" | awk '{print $NF}')"

    local expected_symbols
    expected_symbols="$(bridge_expected_symbols)"

    local symbol
    while IFS= read -r symbol; do
        [[ -z "${symbol}" ]] && continue
        if ! grep -Fqx "_${symbol}" <<<"${exported_symbols}"; then
            echo "error: Darwin bridge does not export ${symbol}" >&2
            exit 1
        fi
    done <<<"${expected_symbols}"

    while IFS= read -r symbol; do
        [[ -z "${symbol}" ]] && continue
        if ! grep -Fqx "${symbol}" <<<"${expected_symbols}"; then
            echo "error: ${symbol} is exported but missing from the force-link anchor" >&2
            exit 1
        fi
    done < <(
        sed -En 's/^_((maplibre_)[a-zA-Z0-9_]+)$/\1/p' <<<"${exported_symbols}" | sort -u
    )

    verify_bridge_objc_class_names "${archive}" "$(
        sed -En 's/^_OBJC_(METACLASS_)?CLASS_\$_([A-Za-z0-9_]+)$/\2/p' <<<"${exported_symbols}" |
            sort -u
    )"
}

# The Objective-C runtime registers a class process wide, so a class the
# vendored MapLibre SDK also defines collides when a host application links both.
# cmake/darwin_objc_class_names.cmake renames the bridge's copies at compile
# time. This check fails the artifact when a rename did not reach the build.
#
# The second argument lists the Objective-C class names the artifact defines,
# one per line.
verify_bridge_objc_class_names() {
    local artifact="$1"
    local class_names="$2"

    local renames
    renames="$(
        sed -En 's/^[[:space:]]*((MLN|MBGL)[A-Za-z0-9_]+=[A-Za-z0-9_]+)[[:space:]]*$/\1/p' \
            "${OBJC_CLASS_RENAMES_SOURCE}"
    )"
    if [[ -z "${renames}" ]]; then
        echo "error: no Darwin class renames found in ${OBJC_CLASS_RENAMES_SOURCE}" >&2
        exit 1
    fi

    local rename original renamed
    while IFS= read -r rename; do
        [[ -z "${rename}" ]] && continue
        original="${rename%%=*}"
        renamed="${rename##*=}"
        if ! grep -Fqx "${renamed}" <<<"${class_names}"; then
            echo "error: ${artifact} does not define ${renamed}" >&2
            echo "The compile time rename of ${original} did not reach mbgl-core." >&2
            exit 1
        fi
        if grep -Fqx "${original}" <<<"${class_names}"; then
            echo "error: ${artifact} still defines ${original}" >&2
            echo "That class collides with the MapLibre GL SDK in a cohosted app." >&2
            exit 1
        fi
    done <<<"${renames}"

    local leftover
    leftover="$(grep -E '^(MLN|MBGL)' <<<"${class_names}" || true)"
    if [[ -n "${leftover}" ]]; then
        echo "error: ${artifact} defines SDK Objective-C classes:" >&2
        echo "${leftover}" >&2
        echo "Add each one to ${OBJC_CLASS_RENAMES_SOURCE}." >&2
        exit 1
    fi
}

# Prints the package version in the numeric form CFBundleShortVersionString
# accepts. Prerelease and build suffixes are dropped.
bridge_bundle_version() {
    local version
    version="$(
        sed -En 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p' \
            "${PROJECT_ROOT}/pubspec.yaml"
    )"
    if [[ -z "${version}" ]]; then
        echo "error: pubspec.yaml does not declare a numeric package version" >&2
        exit 1
    fi
    echo "${version}"
}

# Prints the path of the bridge binary inside a framework. macOS frameworks use
# the versioned bundle layout and iOS frameworks are flat.
bridge_framework_binary() {
    local platform="$1"
    local framework="$2"
    case "${platform}" in
        macosx)
            echo "${framework}/Versions/A/${BRIDGE_FRAMEWORK_NAME}"
            ;;
        *)
            echo "${framework}/${BRIDGE_FRAMEWORK_NAME}"
            ;;
    esac
}

# Prints the directory that holds the framework's Info.plist and privacy manifest.
bridge_framework_resources() {
    local platform="$1"
    local framework="$2"
    case "${platform}" in
        macosx)
            echo "${framework}/Versions/A/Resources"
            ;;
        *)
            echo "${framework}"
            ;;
    esac
}

write_bridge_framework_info_plist() {
    local platform="$1"
    local output="$2"
    local version="$3"
    local supported_platform minimum_version_key minimum_version

    case "${platform}" in
        iphoneos)
            supported_platform=iPhoneOS
            minimum_version_key=MinimumOSVersion
            minimum_version="${IOS_DEPLOYMENT_TARGET}"
            ;;
        iphonesimulator)
            supported_platform=iPhoneSimulator
            minimum_version_key=MinimumOSVersion
            minimum_version="${IOS_DEPLOYMENT_TARGET}"
            ;;
        macosx)
            supported_platform=MacOSX
            minimum_version_key=LSMinimumSystemVersion
            minimum_version="${MACOS_DEPLOYMENT_TARGET}"
            ;;
        *)
            echo "error: unsupported Darwin platform: ${platform}" >&2
            exit 64
            ;;
    esac

    cat >"${output}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${BRIDGE_FRAMEWORK_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BRIDGE_FRAMEWORK_IDENTIFIER}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${BRIDGE_FRAMEWORK_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>${version}</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>${supported_platform}</string>
	</array>
	<key>CFBundleVersion</key>
	<string>${version}</string>
	<key>${minimum_version_key}</key>
	<string>${minimum_version}</string>
</dict>
</plist>
PLIST
    plutil -lint "${output}" >/dev/null
}

# Links a monolithic bridge archive into MapLibreBridge.framework.
#
# Dart resolves the bridge by name with dlsym. A host app's archive build strips
# every global symbol from its own executable, so the bridge ships as a dynamic
# framework whose exported symbols survive that strip. The framework exports
# only the anchor's C symbols, and dead stripping drops code those symbols do
# not reach.
link_bridge_framework() {
    local platform="$1"
    local archive="$2"
    local framework="$3"

    local version_flag install_name
    local frameworks=(CFNetwork CoreGraphics CoreLocation CoreText Foundation ImageIO Security SystemConfiguration)
    case "${platform}" in
        iphoneos)
            version_flag="-miphoneos-version-min=${IOS_DEPLOYMENT_TARGET}"
            install_name="@rpath/${BRIDGE_FRAMEWORK_NAME}.framework/${BRIDGE_FRAMEWORK_NAME}"
            frameworks+=(Metal MetalKit UIKit)
            ;;
        iphonesimulator)
            version_flag="-mios-simulator-version-min=${IOS_DEPLOYMENT_TARGET}"
            install_name="@rpath/${BRIDGE_FRAMEWORK_NAME}.framework/${BRIDGE_FRAMEWORK_NAME}"
            frameworks+=(Metal MetalKit UIKit)
            ;;
        macosx)
            version_flag="-mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}"
            install_name="@rpath/${BRIDGE_FRAMEWORK_NAME}.framework/Versions/A/${BRIDGE_FRAMEWORK_NAME}"
            frameworks+=(AppKit CoreImage)
            ;;
        *)
            echo "error: unsupported Darwin platform: ${platform}" >&2
            exit 64
            ;;
    esac

    if [[ ! -f "${archive}" ]]; then
        echo "error: expected bridge archive is missing: ${archive}" >&2
        exit 1
    fi

    local architectures
    read -r -a architectures <<<"$(xcrun lipo -archs "${archive}")"
    local arch_flags=() architecture
    for architecture in "${architectures[@]}"; do
        arch_flags+=(-arch "${architecture}")
    done
    local framework_flags=() name
    for name in "${frameworks[@]}"; do
        framework_flags+=(-framework "${name}")
    done

    rm -rf "${framework}"
    mkdir -p "${framework}"
    local binary resources content_root
    binary="$(bridge_framework_binary "${platform}" "${framework}")"
    resources="$(bridge_framework_resources "${platform}" "${framework}")"
    content_root="$(dirname "${binary}")"
    mkdir -p "${content_root}/Headers" "${content_root}/Modules" "${resources}"

    local exports_file="${framework}.exports"
    bridge_expected_symbols | sed 's/^/_/' >"${exports_file}"

    echo "Linking ${BRIDGE_FRAMEWORK_NAME}.framework for ${platform} (${architectures[*]})..." >&2
    xcrun --sdk "${platform}" clang++ \
        -dynamiclib \
        "${arch_flags[@]}" \
        -isysroot "$(xcrun --sdk "${platform}" --show-sdk-path)" \
        "${version_flag}" \
        -install_name "${install_name}" \
        -Wl,-force_load,"${archive}" \
        -Wl,-exported_symbols_list,"${exports_file}" \
        -Wl,-dead_strip \
        -Wl,-dead_strip_dylibs \
        -Wl,-x \
        "${framework_flags[@]}" \
        -lsqlite3 \
        -lz \
        -o "${binary}" >&2
    rm -f "${exports_file}"

    cp "${BRIDGE_HEADER}" "${content_root}/Headers/"
    cp "${FRAMEWORK_MODULE_MAP}" "${content_root}/Modules/module.modulemap"
    cp "${PRIVACY_MANIFEST}" "${resources}/PrivacyInfo.xcprivacy"
    write_bridge_framework_info_plist \
        "${platform}" "${resources}/Info.plist" "$(bridge_bundle_version)"

    if [[ "${platform}" == macosx ]]; then
        ln -s A "${framework}/Versions/Current"
        local entry
        for entry in "${BRIDGE_FRAMEWORK_NAME}" Headers Modules Resources; do
            ln -s "Versions/Current/${entry}" "${framework}/${entry}"
        done
    fi

    verify_bridge_framework "${platform}" "${framework}" "${architectures[@]}"
}

# Prints the Mach-O platform number and the minimum OS version a slice targets.
bridge_framework_target() {
    case "$1" in
        iphoneos)
            echo "2 ${IOS_DEPLOYMENT_TARGET} MinimumOSVersion"
            ;;
        iphonesimulator)
            echo "7 ${IOS_DEPLOYMENT_TARGET} MinimumOSVersion"
            ;;
        macosx)
            echo "1 ${MACOS_DEPLOYMENT_TARGET} LSMinimumSystemVersion"
            ;;
        *)
            echo "error: unsupported Darwin platform: $1" >&2
            exit 64
            ;;
    esac
}

# Checks that a MapLibreBridge.framework slice is a well-formed dynamic
# framework with the given architectures. The check does not depend on the
# current source tree, so slices from an earlier build pass it unchanged.
verify_bridge_framework_layout() {
    local platform="$1"
    local framework="$2"
    shift 2
    bridge_framework_target "${platform}" >/dev/null

    local binary resources content_root
    binary="$(bridge_framework_binary "${platform}" "${framework}")"
    resources="$(bridge_framework_resources "${platform}" "${framework}")"
    content_root="$(dirname "${binary}")"

    local required
    for required in \
        "${binary}" \
        "${content_root}/Headers/MapLibreBridge.h" \
        "${content_root}/Modules/module.modulemap" \
        "${resources}/Info.plist" \
        "${resources}/PrivacyInfo.xcprivacy"; do
        if [[ ! -f "${required}" ]]; then
            echo "error: ${framework} is missing ${required#"${framework}/"}" >&2
            exit 1
        fi
    done
    if [[ "${platform}" == macosx ]]; then
        local entry
        for entry in "${BRIDGE_FRAMEWORK_NAME}" Headers Modules Resources Versions/Current; do
            if [[ ! -L "${framework}/${entry}" ]]; then
                echo "error: ${framework}/${entry} is not a symbolic link" >&2
                exit 1
            fi
        done
    fi
    plutil -lint "${resources}/Info.plist" >/dev/null
    plutil -lint "${resources}/PrivacyInfo.xcprivacy" >/dev/null
    local executable
    executable="$(plutil -extract CFBundleExecutable raw -o - "${resources}/Info.plist")"
    if [[ "${executable}" != "${BRIDGE_FRAMEWORK_NAME}" ]]; then
        echo "error: ${framework} names ${executable} as its executable" >&2
        exit 1
    fi

    if ! xcrun otool -hv "${binary}" | grep -q DYLIB; then
        echo "error: ${binary} is not a dynamic library" >&2
        exit 1
    fi

    local architectures
    architectures="$(xcrun lipo -archs "${binary}")"
    if [[ "$(wc -w <<<"${architectures}" | tr -d ' ')" -ne "$#" ]]; then
        echo "error: unexpected architectures in ${binary}: ${architectures}" >&2
        exit 1
    fi

    local architecture install_name
    for architecture in "$@"; do
        if ! grep -qw "${architecture}" <<<"${architectures}"; then
            echo "error: ${binary} is missing ${architecture}" >&2
            exit 1
        fi
        install_name="$(xcrun otool -arch "${architecture}" -D "${binary}" | tail -n 1)"
        if [[ "${install_name}" != "@rpath/${BRIDGE_FRAMEWORK_NAME}.framework/"*"${BRIDGE_FRAMEWORK_NAME}" ]]; then
            echo "error: ${binary} ${architecture} has install name ${install_name}" >&2
            exit 1
        fi
    done
}

# Checks a MapLibreBridge.framework slice against the current source tree. The
# remaining arguments are the architectures the slice must contain.
verify_bridge_framework() {
    local platform="$1"
    local framework="$2"
    shift 2
    verify_bridge_framework_layout "${platform}" "${framework}" "$@"

    local expected_platform expected_minos minimum_version_key
    read -r expected_platform expected_minos minimum_version_key \
        <<<"$(bridge_framework_target "${platform}")"

    local binary resources
    binary="$(bridge_framework_binary "${platform}" "${framework}")"
    resources="$(bridge_framework_resources "${platform}" "${framework}")"

    local declared_minimum
    declared_minimum="$(plutil -extract "${minimum_version_key}" raw -o - "${resources}/Info.plist")"
    if [[ "${declared_minimum}" != "${expected_minos}" ]]; then
        echo "error: ${framework} declares ${minimum_version_key} ${declared_minimum} instead of ${expected_minos}" >&2
        exit 1
    fi

    local expected_symbols
    expected_symbols="$(bridge_expected_symbols | sed 's/^/_/')"
    local architecture
    for architecture in "$@"; do
        xcrun otool -arch "${architecture}" -l "${binary}" | ruby -e '
          expected_platform = ARGV.fetch(0)
          expected_minos = ARGV.fetch(1)
          label = ARGV.fetch(2)
          builds = []
          current = nil
          STDIN.each_line do |line|
            if line.match?(/^Load command /)
              current = nil
            elsif line.match?(/^\s*cmd LC_BUILD_VERSION\s*$/)
              current = {}
              builds << current
            elsif current && (match = line.match(/^\s*platform\s+(\d+)\s*$/))
              current[:platform] = match[1]
            elsif current && (match = line.match(/^\s*minos\s+(\S+)\s*$/))
              current[:minos] = match[1]
            end
          end
          abort "#{label} has #{builds.length} build targets instead of 1" unless builds.length == 1
          build = builds.first
          abort "#{label} targets the wrong Apple platform" unless build[:platform] == expected_platform
          valid_minos = [expected_minos, "#{expected_minos}.0"]
          abort "#{label} does not target #{expected_minos}" unless valid_minos.include?(build[:minos])
        ' "${expected_platform}" "${expected_minos}" "${binary} ${architecture}"

        # Dart looks these up by name, so the export list must match exactly.
        local exported_symbols
        exported_symbols="$(nm -arch "${architecture}" -gU "${binary}" | awk '{print $NF}' | sort -u)"
        if [[ "${exported_symbols}" != "${expected_symbols}" ]]; then
            echo "error: ${binary} ${architecture} exports differ from the force-link anchor:" >&2
            diff <(echo "${expected_symbols}") <(echo "${exported_symbols}") >&2 || true
            exit 1
        fi

        verify_bridge_objc_class_names "${binary} ${architecture}" "$(
            xcrun dyld_info -arch "${architecture}" -objc "${binary}" |
                sed -En 's/^[[:space:]]*@interface[[:space:]]+([A-Za-z0-9_]+).*$/\1/p' |
                sort -u
        )"
    done
}

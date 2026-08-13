#!/usr/bin/env bash

set -euo pipefail

EXPECTED_REVISION='4cf24164269a5ebf0c16a028a00727d0e77bbb05'
EXPECTED_ORIGINAL_SHA256='ca2a09633a4c7c0af25ddbabcf148f4c6096e813e29cda3cd306f9c7f484b2e2'
EXPECTED_PATCHED_SHA256='994025cbd727da655f3a99de3416ecabc0cbc6ac8022abc1295beb3fd1f0cc36'
SDK_RELATIVE_PATH='packages/flutter/lib/src/widgets/_window_macos.dart'

if [[ -n "${FLUTTER_ROOT:-}" ]]; then
    FLUTTER_SDK_ROOT="${FLUTTER_ROOT}"
else
    flutter_binary="$(command -v flutter)"
    FLUTTER_SDK_ROOT="$(cd "$(dirname "${flutter_binary}")/.." && pwd -P)"
fi

TEMP_DIRECTORY="${RUNNER_TEMP:?RUNNER_TEMP is required}"
SDK_FILE="${FLUTTER_SDK_ROOT}/${SDK_RELATIVE_PATH}"
BACKUP_FILE="${TEMP_DIRECTORY}/flutter-3.47.0-window-macos.original"
PATCHED_FILE="${TEMP_DIRECTORY}/flutter-3.47.0-window-macos.patched"

checksum() {
    shasum -a 256 "$1" | awk '{ print $1 }'
}

verify_revision() {
    local revision
    revision="$(git -C "${FLUTTER_SDK_ROOT}" rev-parse HEAD)"
    if [[ "${revision}" != "${EXPECTED_REVISION}" ]]; then
        echo "error: workaround only supports Flutter revision ${EXPECTED_REVISION}" >&2
        exit 1
    fi
}

restore_sdk() {
    if [[ -f "${BACKUP_FILE}" ]]; then
        cp -p "${BACKUP_FILE}" "${SDK_FILE}"
    fi
    if [[ "$(checksum "${SDK_FILE}")" != "${EXPECTED_ORIGINAL_SHA256}" ]]; then
        echo 'error: failed to restore Flutter SDK source' >&2
        return 1
    fi
    git -C "${FLUTTER_SDK_ROOT}" diff --quiet -- "${SDK_RELATIVE_PATH}"
}

restore_on_exit() {
    local status=$?
    local restore_status
    trap - EXIT HUP INT TERM
    set +e
    restore_sdk
    restore_status=$?
    if [[ "${restore_status}" -ne 0 ]]; then
        exit "${restore_status}"
    fi
    exit "${status}"
}

case "${1:-}" in
    run)
        shift
        if [[ "$#" -eq 0 ]]; then
            echo "Usage: $0 run <command> [argument ...]" >&2
            exit 64
        fi
        verify_revision
        if [[ "$(checksum "${SDK_FILE}")" != "${EXPECTED_ORIGINAL_SHA256}" ]]; then
            echo 'error: unexpected Flutter 3.47.0 windowing source' >&2
            exit 1
        fi
        if [[ -e "${BACKUP_FILE}" || -e "${PATCHED_FILE}" ]]; then
            echo 'error: workaround temporary files already exist' >&2
            exit 1
        fi
        cp -p "${SDK_FILE}" "${BACKUP_FILE}"
        trap restore_on_exit EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        awk '
            BEGIN {
                split("_WindowCreationRequest _Size _Offset _Rect _Constraints", names)
                for (i in names) targets[names[i]] = 1
            }
            $1 == "final" && $2 == "class" && ($3 in targets) && $4 == "extends" && $5 == "Struct" && $6 == "{" {
                print "@pragma(\047vm:entry-point\047)"
                seen[$3] += 1
            }
            { print }
            END {
                for (name in targets) if (seen[name] != 1) exit 65
            }
        ' "${SDK_FILE}" >"${PATCHED_FILE}"
        if [[ "$(checksum "${PATCHED_FILE}")" != "${EXPECTED_PATCHED_SHA256}" ]]; then
            echo 'error: generated Flutter SDK workaround differs from expectation' >&2
            exit 1
        fi
        cp "${PATCHED_FILE}" "${SDK_FILE}"
        test "$(checksum "${SDK_FILE}")" = "${EXPECTED_PATCHED_SHA256}"
        "$@"
        ;;
    restore)
        verify_revision
        restore_sdk
        ;;
    *)
        echo "Usage: $0 {run <command> [argument ...]|restore}" >&2
        exit 64
        ;;
esac

#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
    echo "Usage: $0 <artifact-source-commit> <release-commit> [repository]" >&2
    exit 64
fi

ARTIFACT_SOURCE_COMMIT="$1"
RELEASE_COMMIT="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY="${3:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

exec python3 "${SCRIPT_DIR}/verify_release_artifact_source.py" \
    "${ARTIFACT_SOURCE_COMMIT}" "${RELEASE_COMMIT}" "${REPOSITORY}"

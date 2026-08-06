#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

for zoom in 13 14 2; do
  "$repository_root/e2e/visual/run_android.sh" \
    --scene flutter-markers \
    --zoom "$zoom" \
    --minimum-similarity 0 \
    --minimum-content-ratio 0.1 \
    --output "e2e/visual/report-flutter-markers/android/z$zoom" \
    "$@"
done

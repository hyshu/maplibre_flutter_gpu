#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "$script_dir/../.." && pwd -P)"
runner_root="$repository_root/e2e/visual/runner"

(
  cd "$runner_root"
  dart pub get
  dart run bin/run_android.dart "$@"
)

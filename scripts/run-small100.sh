#!/usr/bin/env bash
set -euo pipefail

bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

export ORT_DYLIB_PATH="$bundle_dir/lib/libonnxruntime.so.1.22.0"
export LD_LIBRARY_PATH="$bundle_dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export REPO_PINS_MODEL_CACHE="$bundle_dir/model-cache"

exec "$bundle_dir/gh-profile-repo-pins" "$@"

#!/usr/bin/env bash
set -euo pipefail

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)
    platform="linux-x64"
    ;;
  Linux/aarch64)
    platform="linux-arm64"
    ;;
  *)
    printf '%s\n' \
      'Install ONNX Runtime and set ORT_DYLIB_PATH on this platform; see README.' >&2
    exit 1
    ;;
esac

runtime_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/repo-pins-onnx"
runtime_dir="$runtime_parent/onnxruntime-$platform-1.22.0"
runtime_lib="$runtime_dir/lib/libonnxruntime.so.1.22.0"

mkdir -p "$runtime_parent"

if [[ ! -f "$runtime_lib" ]]; then
  archive="$(mktemp "$runtime_parent/runtime.XXXXXX.nupkg")"
  trap 'rm -f -- "$archive"' EXIT

  curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.22.0/microsoft.ml.onnxruntime.1.22.0.nupkg" \
    --output "$archive"
  mkdir -p "$runtime_dir/lib"
  unzip -jo "$archive" \
    "runtimes/$platform/native/*.so*" \
    -d "$runtime_dir/lib"

  if [[ ! -f "$runtime_lib" ]]; then
    mv "$runtime_dir/lib/libonnxruntime.so" "$runtime_lib"
  fi
fi

if [[ ! -f "$runtime_lib" ]]; then
  printf 'ONNX Runtime library not found: %s\n' "$runtime_lib" >&2
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'ORT_DYLIB_PATH=%s\n' "$runtime_lib" >> "$GITHUB_ENV"
fi

printf 'export ORT_DYLIB_PATH="%s"\n' "$runtime_lib"

#!/usr/bin/env bash
set -euo pipefail

platform="${1:?Usage: scripts/package-small100.sh linux-x64|linux-arm64 [binary]}"
binary="${2:-target/release/gh-profile-repo-pins}"

case "$platform" in
  linux-x64|linux-arm64)
    ;;
  *)
    printf 'Unsupported platform: %s\n' "$platform" >&2
    exit 1
    ;;
esac

: "${ORT_DYLIB_PATH:?Run scripts/setup-onnx.sh first and set ORT_DYLIB_PATH}"
: "${GITHUB_SHA:?Expected GitHub Actions commit SHA}"

if [[ ! "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  printf '%s\n' 'GITHUB_SHA must be a full Git commit SHA' >&2
  exit 1
fi

if [[ ! -f "$binary" || ! -f "$ORT_DYLIB_PATH" ]]; then
  printf '%s\n' 'Binary or ONNX Runtime library is missing' >&2
  exit 1
fi

revision="a0d8498"
model_url="https://huggingface.co/casawolice/small100-onnx/resolve/$revision"

package_dir="$(mktemp -d)"
trap 'rm -rf -- "$package_dir"' EXIT

model_dir="$package_dir/model-cache/small100/$revision"
mkdir -p "$model_dir" "$package_dir/lib" dist

install -m 755 "$binary" "$package_dir/gh-profile-repo-pins"
install -m 755 scripts/run-small100.sh "$package_dir/run-repo-pins"
cp -a -- "$(dirname -- "$ORT_DYLIB_PATH")/." "$package_dir/lib/"
install -m 644 LICENSE "$package_dir/LICENSE-APPLICATION"
printf '%s\n' "$GITHUB_SHA" > "$package_dir/SOURCE_COMMIT"

fetch_model_file() {
  local remote="$1"
  local dest="$model_dir/$2"

  printf 'Fetching SMALL100 %s (%s)\n' "$remote" "$revision"

  curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --output "$dest.part" "$model_url/$remote"

  if [[ ! -s "$dest.part" ]]; then
    printf 'Empty download: %s\n' "$remote" >&2
    exit 1
  fi

  mv -- "$dest.part" "$dest"
}

fetch_model_file tokenizer.json tokenizer.json
fetch_model_file lang_tokens.json lang_tokens.json
fetch_model_file onnx/encoder_model.onnx encoder_model.onnx
fetch_model_file onnx/decoder_model_merged.onnx decoder_model_merged.onnx

for file in encoder_model.onnx decoder_model_merged.onnx; do
  if [[ "$(stat --format=%s "$model_dir/$file")" -le 100000000 ]]; then
    printf 'Suspiciously small model file: %s\n' "$file" >&2
    exit 1
  fi
done

cat > "$package_dir/THIRD_PARTY_NOTICES.txt" <<'NOTICES'
SMaLL-100 ONNX model (MIT license)
Source: https://huggingface.co/casawolice/small100-onnx
Model: SMaLL-100 (Mohammadshahi et al., 2022)
Pinned Hugging Face revision: a0d8498

ONNX Runtime 1.22.0 (MIT license)
Source: https://github.com/microsoft/onnxruntime/tree/v1.22.0
License: https://github.com/microsoft/onnxruntime/blob/v1.22.0/LICENSE

MIT license text for the third-party components:

Copyright (c) Microsoft Corporation and ONNX Runtime contributors.
Copyright (c) SMaLL-100 model authors and contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
NOTICES

cat > "$package_dir/README-SMALL100.txt" <<'README'
GitHub Profile Repo Pins - SMALL100 Bundle
==========================================

Extract this archive and run:

    GH_API_TOKEN=<token> TRANSLATION_LOCALES=sv,de,it ./run-repo-pins --username <github-user>

The launcher automatically points the program to the bundled ONNX Runtime and
SMALL100 model cache. No model download is needed to run translations.
The GitHub API and any linked repositories still require network access.

The model comes from casawolice/small100-onnx at revision a0d8498.
The included runtime is ONNX Runtime 1.22.0 for the target Linux architecture.
See THIRD_PARTY_NOTICES.txt for attribution.
README

asset="gh-profile-repo-pins-small100-$platform.tar.gz"

tar --create --gzip --file "dist/$asset" --directory "$package_dir" \
  gh-profile-repo-pins run-repo-pins SOURCE_COMMIT LICENSE-APPLICATION \
  THIRD_PARTY_NOTICES.txt README-SMALL100.txt lib model-cache

(
  cd dist
  sha256sum "$asset" > "$asset.sha256"
)

printf 'Packaged %s\n' "dist/$asset"

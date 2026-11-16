#!/usr/bin/env bash
set -euo pipefail

src_dir="$(cd -- "${1:?Source checkout directory is required}" && pwd)"

for file in files/themes.json scripts/commit.sh; do
  if [[ ! -f "$src_dir/$file" ]]; then
    printf '::error::Missing %s in source checkout %s.\n' "$file" "$src_dir" >&2
    exit 1
  fi
done

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64)
    platform="linux-x64"
    ;;
  Linux/aarch64)
    platform="linux-arm64"
    ;;
  *)
    printf '%s\n' '::error::Prebuilt actions support Linux x64 and ARM64 only.' >&2
    exit 1
    ;;
esac

src_sha="$(git -C "$src_dir" rev-parse HEAD)"
origin="$(git -C "$src_dir" remote get-url origin)"
repo="${origin#https://github.com/}"
repo="${repo%.git}"

if [[ ! "$src_sha" =~ ^[0-9a-f]{40}$ || ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  printf '%s\n' '::error::Expected a GitHub HTTPS source checkout and a full commit SHA.' >&2
  exit 1
fi

mode="standard"
locales="${TRANSLATION_LOCALES:-}"

if [[ -n "${locales//[[:space:]]/}" ]]; then
  mode="small100"
fi

asset="gh-profile-repo-pins-$platform.tar.gz"
if [[ "$mode" == "small100" ]]; then
  asset="gh-profile-repo-pins-small100-$platform.tar.gz"
fi

tag="binary-$src_sha"
url="https://github.com/$repo/releases/download/$tag"
bin_dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/repo-pins-bin/$src_sha/$platform/$mode"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/extract"

if ! curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' --tlsv1.2 \
  "$url/$asset.sha256" --output "$tmp_dir/$asset.sha256"; then
  printf '::error::Missing %s for source %s in %s. Publish the binary-%s release before using this Action.\n' \
    "$asset" "$src_sha" "$repo" "$src_sha" >&2
  exit 1
fi

curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' --tlsv1.2 \
  "$url/$asset" --output "$tmp_dir/$asset"

(
  cd "$tmp_dir"
  sha256sum --check --strict "$asset.sha256"
)

if [[ "$mode" == "small100" ]]; then
  tar --extract --gzip --no-same-owner --no-same-permissions \
    --file "$tmp_dir/$asset" --directory "$tmp_dir/extract" \
    gh-profile-repo-pins run-repo-pins SOURCE_COMMIT lib model-cache
else
  tar --extract --gzip --no-same-owner --no-same-permissions \
    --file "$tmp_dir/$asset" --directory "$tmp_dir/extract" \
    gh-profile-repo-pins SOURCE_COMMIT
fi

extracted="$tmp_dir/extract"

if [[ -L "$extracted/gh-profile-repo-pins" || -L "$extracted/SOURCE_COMMIT" \
  || ! -f "$extracted/gh-profile-repo-pins" || ! -f "$extracted/SOURCE_COMMIT" \
  || "$(cat "$extracted/SOURCE_COMMIT")" != "$src_sha" ]]; then
  printf '%s\n' '::error::Release archive does not match the checked-out source commit.' >&2
  exit 1
fi

if [[ "$mode" == "small100" ]]; then
  model_dir="$extracted/model-cache/small100/a0d8498"

  for file in \
    "$extracted/run-repo-pins" \
    "$extracted/lib/libonnxruntime.so.1.22.0" \
    "$model_dir/tokenizer.json" \
    "$model_dir/lang_tokens.json" \
    "$model_dir/encoder_model.onnx" \
    "$model_dir/decoder_model_merged.onnx"; do
    if [[ -L "$file" || ! -s "$file" ]]; then
      printf '::error::SMALL100 bundle is missing required file: %s\n' "$file" >&2
      exit 1
    fi
  done
fi

mkdir -p "$bin_dir"
install -m 755 "$extracted/gh-profile-repo-pins" "$bin_dir/gh-profile-repo-pins"

if [[ "$mode" == "small100" ]]; then
  install -m 755 "$extracted/run-repo-pins" "$bin_dir/run-repo-pins"
  rm -rf -- "$bin_dir/lib" "$bin_dir/model-cache"
  mv -- "$extracted/lib" "$bin_dir/lib"
  mv -- "$extracted/model-cache" "$bin_dir/model-cache"
  run_bin="$bin_dir/run-repo-pins"
else
  run_bin="$bin_dir/gh-profile-repo-pins"
fi

"$run_bin" --help >/dev/null

if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'REPO_PINS_SRC_DIR=%s\n' "$src_dir" >> "$GITHUB_ENV"
  printf 'REPO_PINS_BIN=%s\n' "$run_bin" >> "$GITHUB_ENV"
fi

printf 'Ready: %s (%s, %s)\n' "$tag" "$platform" "$mode"

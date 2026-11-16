#!/usr/bin/env bash
set -euo pipefail

: "${GH_USER_NAME:?Did not supply GH_USER_NAME}"
: "${GH_USER_ID:?Did not supply GH_USER_ID}"
: "${GH_USERNAME:?GitHub login is required}"
: "${DEFAULT_BRANCH:?Default branch is required}"

git check-ref-format "refs/heads/$DEFAULT_BRANCH"

repo_dir="$(git rev-parse --show-toplevel)"
temp_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/repo-pins-publish.XXXXXX")"
gen_dir="$temp_dir/generated"
readme_dir="$temp_dir/readme"

cleanup() {
  git -C "$repo_dir" worktree remove --force "$gen_dir" 2>/dev/null || true
  git -C "$repo_dir" worktree remove --force "$readme_dir" 2>/dev/null || true
  rm -f -- "$temp_dir/readme.patch"
  rmdir "$temp_dir" 2>/dev/null || true
}
trap cleanup EXIT

git -C "$repo_dir" diff --binary -- README.md profile/README.md > "$temp_dir/readme.patch"
git -C "$repo_dir" fetch origin "$DEFAULT_BRANCH"

gen_base="HEAD"
if git -C "$repo_dir" ls-remote --exit-code --heads origin generated >/dev/null 2>&1; then
  git -C "$repo_dir" fetch origin generated
  gen_base="FETCH_HEAD"
fi

git -C "$repo_dir" worktree add --detach "$gen_dir" "$gen_base"
mkdir -p "$gen_dir/repo_pin_imgs"

for image in "$gen_dir"/repo_pin_imgs/*.svg; do
  if [[ -f "$image" && "${image##*/}" =~ ^[0-9]+\.svg$ ]]; then
    rm -f -- "$image"
  fi
done

cp -a -- "$repo_dir/repo_pin_imgs/." "$gen_dir/repo_pin_imgs/"

publish() {
  local dir="$1"
  local branch="$2"
  local message="$3"
  shift 3

  git -C "$dir" config user.name "$GH_USER_NAME"
  git -C "$dir" config user.email "${GH_USER_ID}+${GH_USERNAME}@users.noreply.github.com"
  git -C "$dir" add -A -- "$@"

  if git -C "$dir" diff --cached --quiet; then
    return
  fi

  git -C "$dir" -c core.hooksPath=/dev/null commit -m "$message"

  for ((attempt = 1; attempt <= 3; attempt++)); do
    if git -C "$dir" push origin "HEAD:refs/heads/$branch"; then
      return
    fi

    git -C "$dir" fetch origin "$branch"
    git -C "$dir" -c core.hooksPath=/dev/null rebase FETCH_HEAD
  done

  printf 'Could not publish %s after three attempts\n' "$branch" >&2
  return 1
}

publish "$gen_dir" generated "Auto-update profile repo pins" repo_pin_imgs

if [[ -s "$temp_dir/readme.patch" ]]; then
  git -C "$repo_dir" worktree add --detach "$readme_dir" "refs/remotes/origin/$DEFAULT_BRANCH"
  git -C "$readme_dir" apply --3way "$temp_dir/readme.patch"

  readme_paths=()
  for file in README.md profile/README.md; do
    if [[ -f "$readme_dir/$file" ]]; then
      readme_paths+=("$file")
    fi
  done

  publish "$readme_dir" "$DEFAULT_BRANCH" "Update README.md" "${readme_paths[@]}"
fi

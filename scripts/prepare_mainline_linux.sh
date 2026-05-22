#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
linux_src="${LINUX_SRC:-$repo_dir/linux/kernel}"
linux_tag="${LINUX_TAG:-v5.10}"
remote="${LINUX_REMOTE:-https://github.com/torvalds/linux.git}"
branch="zx32-bringup-${linux_tag}"

if [[ -d "$linux_src/.git" ]]; then
    git -C "$linux_src" fetch --tags origin "$linux_tag"
else
    git clone --branch "$linux_tag" --depth 1 "$remote" "$linux_src"
fi

git -C "$linux_src" checkout -B "$branch" "$linux_tag"

echo "Linux source: $linux_src"
echo "Linux tag: $linux_tag"
echo "Branch: $branch"

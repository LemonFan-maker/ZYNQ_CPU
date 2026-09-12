#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <script.xsct|script.xsbl>" >&2
  exit 2
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="$(readlink -f "$1")"

exec zsh -lc "cd $(printf '%q' "$repo_dir") && source /home/orionisli/.zshrc >/dev/null 2>&1 && vi25 && xsct $(printf '%q' "$script_path")"

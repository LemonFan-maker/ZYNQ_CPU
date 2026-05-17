#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <script.xsct|script.xsbl>" >&2
  exit 2
fi

exec zsh -lc "source /home/orionisli/.zshrc >/dev/null 2>&1 && vi25 && xsct $(printf '%q' "$1")"

